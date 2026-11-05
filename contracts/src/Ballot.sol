// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {ECDSA} from "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Ballot
/// @notice Encounter E1 and E8. The room's steering wheel, and the proof that a signature is not
///         a transaction: 25 delegates sign off-chain, one relayer submits, one transaction lands.
///
/// @dev Two things this contract teaches by being built this way:
///
///      1. `castVotes` is permissionless. The presenter's laptop is a convenience, not an
///         authority. Any address holding a valid signature can submit it. That is the
///         difference between a relayer and a gatekeeper, and the room should be told so.
///
///      2. `Mode.TokenWeighted` reads `balanceOf` at cast time. That is exactly the flaw that
///         production governance avoids with `ERC20Votes` snapshots: borrow the token, vote,
///         return it. We do it the naive way on purpose, then show the room the flash-loan
///         attack in one sentence. Do not reuse this contract for anything real.
contract Ballot is EIP712, Ownable, ReentrancyGuard {
    bytes32 public constant BALLOT_TYPEHASH =
        keccak256("Ballot(bytes32 pollId,uint8 choice,uint256 nonce)");

    enum Mode {
        Equal, // one address, one vote
        TokenWeighted // weight = token balance at cast time (naive, see @dev)
    }

    struct Poll {
        string label;
        uint8 optionCount;
        Mode mode;
        uint64 opensAt;
        uint64 closesAt;
        bool exists;
        bool finalized;
    }

    /// @notice pollId => poll metadata. pollId is chosen by the operator (e.g. keccak256("E5vsE6")).
    mapping(bytes32 => Poll) public polls;

    /// @notice pollId => option index => accumulated weight.
    mapping(bytes32 => uint256[]) private _tally;

    /// @notice pollId => voter => has voted. Blocks double-voting per poll.
    mapping(bytes32 => mapping(address => bool)) public hasVoted;

    /// @notice Signer nonce. Included in the signed struct so a ballot cannot be replayed
    ///         against a later poll that reuses the same pollId.
    mapping(address => uint256) public nonce;

    /// @notice Token used as weight in TokenWeighted polls. Set once to the Loot token.
    address public weightToken;

    event PollCreated(bytes32 indexed pollId, string label, uint8 optionCount, Mode mode);
    event VoteCast(bytes32 indexed pollId, address indexed voter, uint8 choice, uint256 weight);
    event PollFinalized(bytes32 indexed pollId, uint256[] tally);

    error PollUnknown();
    error PollExists();
    error PollNotOpen();
    error PollClosed();
    error PollAlreadyFinalized();
    error BadChoice();
    error AlreadyVoted();
    error BadSignature();
    error LengthMismatch();
    error EmptyBatch();
    error NoWeightToken();

    constructor(address owner_) EIP712("GuildBallot", "1") Ownable(owner_) {}

    // ---------------------------------------------------------------------
    // Operator
    // ---------------------------------------------------------------------

    function setWeightToken(address token) external onlyOwner {
        weightToken = token;
    }

    function createPoll(
        bytes32 pollId,
        string calldata label,
        uint8 optionCount,
        Mode mode,
        uint64 opensAt,
        uint64 closesAt
    ) external onlyOwner {
        if (polls[pollId].exists) revert PollExists();
        if (optionCount < 2 || optionCount > 4) revert BadChoice();
        if (closesAt <= opensAt) revert PollClosed();

        polls[pollId] = Poll({
            label: label,
            optionCount: optionCount,
            mode: mode,
            opensAt: opensAt,
            closesAt: closesAt,
            exists: true,
            finalized: false
        });
        _tally[pollId] = new uint256[](optionCount);

        emit PollCreated(pollId, label, optionCount, mode);
    }

    // ---------------------------------------------------------------------
    // Anyone
    // ---------------------------------------------------------------------

    /// @notice Submit a batch of signed ballots. Permissionless by design.
    /// @param pollId Which poll.
    /// @param signers The delegating addresses, in any order.
    /// @param choices Option index each signer chose.
    /// @param sigs 65-byte ECDSA signatures over the EIP-712 Ballot struct.
    function castVotes(
        bytes32 pollId,
        address[] calldata signers,
        uint8[] calldata choices,
        bytes[] calldata sigs
    ) external nonReentrant {
        uint256 n = signers.length;
        if (n == 0) revert EmptyBatch();
        if (n != choices.length || n != sigs.length) revert LengthMismatch();

        for (uint256 i = 0; i < n; i++) {
            _cast(pollId, signers[i], choices[i], sigs[i]);
        }
    }

    /// @notice Close a poll and freeze its tally. Callable by anyone once the window has passed.
    function finalize(bytes32 pollId) external {
        Poll storage p = polls[pollId];
        if (!p.exists) revert PollUnknown();
        if (block.timestamp <= p.closesAt) revert PollNotOpen();
        if (p.finalized) revert PollAlreadyFinalized();

        p.finalized = true;
        emit PollFinalized(pollId, _tally[pollId]);
    }

    // ---------------------------------------------------------------------
    // Views
    // ---------------------------------------------------------------------

    function tallyOf(bytes32 pollId) external view returns (uint256[] memory) {
        return _tally[pollId];
    }

    /// @notice Index of the winning option. Ties resolve to the lowest index — say so out loud,
    ///         because tie-breaking is a governance decision nobody notices until it matters.
    function winner(bytes32 pollId) external view returns (uint8) {
        uint256[] storage t = _tally[pollId];
        uint256 best = 0;
        for (uint256 i = 1; i < t.length; i++) {
            if (t[i] > t[best]) best = i;
        }
        return uint8(best);
    }

    /// @notice The digest a delegate must sign. Exposed so the frontend and the audit trail agree.
    function ballotDigest(bytes32 pollId, uint8 choice, address signer)
        external
        view
        returns (bytes32)
    {
        return _hashTypedDataV4(_structHash(pollId, choice, nonce[signer]));
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _structHash(bytes32 pollId, uint8 choice, uint256 nonce_)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(BALLOT_TYPEHASH, pollId, choice, nonce_));
    }

    function _cast(bytes32 pollId, address signer, uint8 choice, bytes calldata sig) internal {
        Poll storage p = polls[pollId];
        if (!p.exists) revert PollUnknown();
        if (block.timestamp < p.opensAt) revert PollNotOpen();
        if (block.timestamp > p.closesAt) revert PollClosed();
        if (choice >= p.optionCount) revert BadChoice();
        if (hasVoted[pollId][signer]) revert AlreadyVoted();

        bytes32 digest = _hashTypedDataV4(_structHash(pollId, choice, nonce[signer]));
        if (ECDSA.recover(digest, sig) != signer) revert BadSignature();

        uint256 weight = 1;
        if (p.mode == Mode.TokenWeighted) {
            if (weightToken == address(0)) revert NoWeightToken();
            weight = IERC20(weightToken).balanceOf(signer);
        }

        hasVoted[pollId][signer] = true;
        nonce[signer] += 1;
        _tally[pollId][choice] += weight;

        emit VoteCast(pollId, signer, choice, weight);
    }
}
