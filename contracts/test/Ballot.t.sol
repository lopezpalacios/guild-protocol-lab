// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {Ballot} from "../src/Ballot.sol";
import {LabToken} from "../src/LabToken.sol";

/// @notice Encounter E1/E8. The steering wheel.
contract BallotTest is Test {
    Ballot ballot;
    LabToken loot;

    bytes32 constant POLL = keccak256("E5vsE6");

    uint256 pkA = 0xA11CE;
    uint256 pkB = 0xB0B;
    uint256 pkC = 0xC0C;

    address a;
    address b;
    address c;

    uint64 opens;
    uint64 closes;

    function setUp() public {
        a = vm.addr(pkA);
        b = vm.addr(pkB);
        c = vm.addr(pkC);

        ballot = new Ballot(address(this));
        loot = new LabToken("Loot", "LOOT", 1_000_000e18, address(this));
        ballot.setWeightToken(address(loot));

        opens = uint64(block.timestamp);
        closes = uint64(block.timestamp + 600);
        ballot.createPoll(POLL, "E5 AMM or E6 Lending", 2, Ballot.Mode.Equal, opens, closes);
    }

    function _sig(uint256 pk, uint8 choice) internal view returns (bytes memory) {
        address signer = vm.addr(pk);
        bytes32 digest = ballot.ballotDigest(POLL, choice, signer);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(pk, digest);
        return abi.encodePacked(r, s, v);
    }

    function test_batchTally() public {
        address[] memory signers = new address[](3);
        uint8[] memory choices = new uint8[](3);
        bytes[] memory sigs = new bytes[](3);

        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkA, 0);
        signers[1] = b; choices[1] = 1; sigs[1] = _sig(pkB, 1);
        signers[2] = c; choices[2] = 1; sigs[2] = _sig(pkC, 1);

        ballot.castVotes(POLL, signers, choices, sigs);

        uint256[] memory t = ballot.tallyOf(POLL);
        assertEq(t[0], 1);
        assertEq(t[1], 2);
        assertEq(ballot.winner(POLL), 1);
    }

    /// @dev The presenter's laptop is a convenience, not an authority.
    function test_anyoneCanRelay() public {
        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);
        signers[0] = a; choices[0] = 1; sigs[0] = _sig(pkA, 1);

        address stranger = address(0xBEEF);
        vm.prank(stranger);
        ballot.castVotes(POLL, signers, choices, sigs);

        assertEq(ballot.tallyOf(POLL)[1], 1);
        assertTrue(ballot.hasVoted(POLL, a));
    }

    function test_doubleVoteReverts() public {
        address[] memory signers = new address[](2);
        uint8[] memory choices = new uint8[](2);
        bytes[] memory sigs = new bytes[](2);
        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkA, 0);
        signers[1] = a; choices[1] = 1; sigs[1] = _sig(pkA, 1);

        vm.expectRevert(Ballot.AlreadyVoted.selector);
        ballot.castVotes(POLL, signers, choices, sigs);
    }

    function test_wrongSignerReverts() public {
        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);
        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkB, 0); // bob signs, claims to be alice

        vm.expectRevert(Ballot.BadSignature.selector);
        ballot.castVotes(POLL, signers, choices, sigs);
    }

    function test_choiceMismatchReverts() public {
        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);
        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkA, 1); // signed option 1, submitted 0

        vm.expectRevert(Ballot.BadSignature.selector);
        ballot.castVotes(POLL, signers, choices, sigs);
    }

    function test_outOfRangeChoiceReverts() public {
        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);
        signers[0] = a; choices[0] = 9;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(pkA, ballot.ballotDigest(POLL, 9, a));
        sigs[0] = abi.encodePacked(r, s, v);

        vm.expectRevert(Ballot.BadChoice.selector);
        ballot.castVotes(POLL, signers, choices, sigs);
    }

    function test_voteAfterCloseReverts() public {
        vm.warp(closes + 1);
        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);
        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkA, 0);

        vm.expectRevert(Ballot.PollClosed.selector);
        ballot.castVotes(POLL, signers, choices, sigs);
    }

    function test_tokenWeighted() public {
        bytes32 poll2 = keccak256("whoPays");
        ballot.createPoll(poll2, "Who pays the gas?", 2, Ballot.Mode.TokenWeighted, opens, closes);

        loot.mint(a, 10e18);
        loot.mint(b, 1e18);

        address[] memory signers = new address[](2);
        uint8[] memory choices = new uint8[](2);
        bytes[] memory sigs = new bytes[](2);

        signers[0] = a; choices[0] = 0;
        signers[1] = b; choices[1] = 1;

        (uint8 v1, bytes32 r1, bytes32 s1) = vm.sign(pkA, ballot.ballotDigest(poll2, 0, a));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(pkB, ballot.ballotDigest(poll2, 1, b));
        sigs[0] = abi.encodePacked(r1, s1, v1);
        sigs[1] = abi.encodePacked(r2, s2, v2);

        ballot.castVotes(poll2, signers, choices, sigs);

        uint256[] memory t = ballot.tallyOf(poll2);
        assertEq(t[0], 10e18);
        assertEq(t[1], 1e18);
        assertEq(ballot.winner(poll2), 0);
    }

    function test_finalizeFreezesTally() public {
        vm.warp(closes + 1);
        ballot.finalize(POLL);
        (,,,,, bool exists, bool finalized) = ballot.polls(POLL);
        assertTrue(exists);
        assertTrue(finalized);
        vm.expectRevert(Ballot.PollAlreadyFinalized.selector);
        ballot.finalize(POLL);
    }

    function test_finalizeBeforeCloseReverts() public {
        vm.expectRevert(Ballot.PollNotOpen.selector);
        ballot.finalize(POLL);
    }

    function test_replayAgainstNewPollReverts() public {
        bytes32 poll2 = keccak256("second");
        ballot.createPoll(poll2, "Second", 2, Ballot.Mode.Equal, opens, closes);

        address[] memory signers = new address[](1);
        uint8[] memory choices = new uint8[](1);
        bytes[] memory sigs = new bytes[](1);

        signers[0] = a; choices[0] = 0; sigs[0] = _sig(pkA, 0);
        ballot.castVotes(POLL, signers, choices, sigs);

        // Same signature, different poll: the pollId is inside the signed struct, so it fails.
        vm.expectRevert(Ballot.BadSignature.selector);
        ballot.castVotes(poll2, signers, choices, sigs);
    }
}
