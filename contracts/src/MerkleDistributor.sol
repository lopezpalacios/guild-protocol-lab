// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {MerkleProof} from "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title MerkleDistributor
/// @notice Encounter E2. The whole 45-address allocation lives off-chain; only a 32-byte root
///         is on-chain. This is why airdrops are cheap and why they are also a *claim*, not a gift.
///
/// @dev The important design property, and the one the lab teaches out loud:
///      **`claim` is permissionless and always pays `account`, never `msg.sender`.**
///      Anyone can submit anyone else's claim. A relayer that censors a claim can be bypassed by
///      any other address on the network, including one sitting in the audience. That is what
///      "censorship resistance" actually means in practice — not that nobody can stop you, but
///      that stopping you requires stopping everyone.
contract MerkleDistributor is ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token;
    bytes32 public immutable merkleRoot;
    uint256 public immutable claimDeadline;

    /// @notice One claim per address. Indexed by account, not by leaf index, so a re-generated
    ///         tree cannot be used to double-dip the same wallet.
    mapping(address => bool) public claimed;

    uint256 public totalClaimed;

    event Claimed(uint256 index, address indexed account, uint256 amount, address indexed submittedBy);

    error AlreadyClaimed();
    error InvalidProof();
    error ClaimWindowClosed();

    constructor(IERC20 token_, bytes32 merkleRoot_, uint256 claimDeadline_) {
        token = token_;
        merkleRoot = merkleRoot_;
        claimDeadline = claimDeadline_;
    }

    /// @notice Claim `amount` for `account` using a merkle proof.
    /// @param index Leaf index in the published tree. Included in the leaf so two accounts with
    ///        identical balances still have distinct leaves.
    /// @param account The recipient. Funds always go here, never to msg.sender.
    /// @param amount Allocation in token base units.
    /// @param proof Sibling hashes from leaf to root.
    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        external
        nonReentrant
    {
        if (block.timestamp > claimDeadline) revert ClaimWindowClosed();
        if (claimed[account]) revert AlreadyClaimed();
        if (!_verify(index, account, amount, proof)) revert InvalidProof();

        claimed[account] = true;
        totalClaimed += amount;

        token.safeTransfer(account, amount);

        emit Claimed(index, account, amount, msg.sender);
    }

    /// @notice Whether a given allocation is claimable, without sending a transaction.
    /// @dev Used by the frontend so a guild delegate can see "you are in the tree" before tapping.
    function isClaimable(uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        external
        view
        returns (bool)
    {
        return !claimed[account] && _verify(index, account, amount, proof);
    }

    function _verify(uint256 index, address account, uint256 amount, bytes32[] calldata proof)
        internal
        view
        returns (bool)
    {
        bytes32 leaf = keccak256(abi.encodePacked(index, account, amount));
        return MerkleProof.verify(proof, merkleRoot, leaf);
    }
}
