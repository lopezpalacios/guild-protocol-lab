// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LabToken} from "../src/LabToken.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";
import {MerkleBuilder} from "./utils/MerkleBuilder.sol";

/// @notice Encounter E2. Everything the room is told about airdrops should be asserted here.
contract MerkleDistributorTest is Test {
    LabToken token;
    MerkleDistributor distributor;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    uint256[3] amounts;
    bytes32 root;
    bytes32[][] proofs;

    function setUp() public {
        amounts = [uint256(100e18), 200e18, 300e18];

        bytes32[] memory leaves = new bytes32[](3);
        leaves[0] = MerkleBuilder.leaf(0, alice, amounts[0]);
        leaves[1] = MerkleBuilder.leaf(1, bob, amounts[1]);
        leaves[2] = MerkleBuilder.leaf(2, carol, amounts[2]);

        (root, proofs) = MerkleBuilder.build(leaves);

        token = new LabToken("Loot", "LOOT", 1_000e18, address(this));
        distributor = new MerkleDistributor(token, root, block.timestamp + 30 days);
        token.mint(address(distributor), 600e18);
    }

    function test_claimTransfersAllocation() public {
        vm.prank(alice);
        distributor.claim(0, alice, amounts[0], proofs[0]);

        assertEq(token.balanceOf(alice), 100e18);
        assertTrue(distributor.claimed(alice));
        assertEq(distributor.totalClaimed(), 100e18);
    }

    /// @dev The censorship-resistance lesson, made executable: a third party can submit
    ///      someone else's claim, and the funds still go to the claimant.
    function test_relayedClaimPaysTheClaimantNotTheRelayer() public {
        vm.prank(bob); // bob is not the beneficiary
        distributor.claim(0, alice, amounts[0], proofs[0]);

        assertEq(token.balanceOf(alice), 100e18, "alice receives");
        assertEq(token.balanceOf(bob), 0, "relayer receives nothing");
    }

    function test_doubleClaimReverts() public {
        vm.startPrank(alice);
        distributor.claim(0, alice, amounts[0], proofs[0]);
        vm.expectRevert(MerkleDistributor.AlreadyClaimed.selector);
        distributor.claim(0, alice, amounts[0], proofs[0]);
        vm.stopPrank();
    }

    function test_wrongProofReverts() public {
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(1, alice, amounts[1], proofs[1]); // alice's address, bob's slot
    }

    function test_inflatedAmountReverts() public {
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, alice, 1_000e18, proofs[0]);
    }

    function test_claimAfterDeadlineReverts() public {
        vm.warp(block.timestamp + 31 days);
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.ClaimWindowClosed.selector);
        distributor.claim(0, alice, amounts[0], proofs[0]);
    }

    function test_isClaimableView() public {
        assertTrue(distributor.isClaimable(0, alice, amounts[0], proofs[0]));
        assertFalse(distributor.isClaimable(0, alice, amounts[1], proofs[1]));
    }

    function testFuzz_onlyTheExactAllocationVerifies(uint256 bad) public {
        bad = bound(bad, 1, 1_000_000e18);
        vm.assume(bad != amounts[0]);
        vm.prank(alice);
        vm.expectRevert(MerkleDistributor.InvalidProof.selector);
        distributor.claim(0, alice, bad, proofs[0]);
    }
}
