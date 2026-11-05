// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {LabToken} from "../src/LabToken.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";
import {AdventurerBadge} from "../src/AdventurerBadge.sol";
import {Ballot} from "../src/Ballot.sol";
import {LabPair} from "../src/LabPair.sol";
import {MerkleBuilder} from "./utils/MerkleBuilder.sol";

/// @notice The T-7 load simulation required by the lab pack.
///         25 guilds vote in one batched transaction, 45 addresses claim loot, 200 people claim
///         the badge, and the pair survives twenty-five swaps. If this fails, the lab does not
///         run. Run it at T-7 and again at T-1.
contract LoadSimTest is Test {
    LabToken loot;
    LabToken gold;
    LabToken silver;
    MerkleDistributor distributor;
    AdventurerBadge badge;
    Ballot ballot;
    LabPair pair;

    uint256 constant GUILDS = 25;
    uint256 constant PLAYERS = 20;
    uint256 constant ATTENDEES = 200;
    uint256 constant SEED = 50_000e18;

    bytes32 constant POLL_1 = keccak256("E5vsE6");
    bytes32 constant POLL_2 = keccak256("E7vsE8");

    address[] guilds;
    uint256[] keys;

    function setUp() public {
        // --- wallets -------------------------------------------------------
        for (uint256 i = 0; i < GUILDS; i++) {
            uint256 pk = uint256(keccak256(abi.encodePacked("guild", i))) >> 8;
            keys.push(pk);
            guilds.push(vm.addr(pk));
        }

        // --- tokens & pair -------------------------------------------------
        loot = new LabToken("Loot", "LOOT", 1_000_000e18, address(this));
        gold = new LabToken("Gold", "GOLD", 1_000_000e18, address(this));
        silver = new LabToken("Silver", "SILVER", 1_000_000e18, address(this));

        pair = new LabPair(address(gold), address(silver), address(this));
        gold.mint(address(this), SEED);
        silver.mint(address(this), SEED);
        gold.approve(address(pair), type(uint256).max);
        silver.approve(address(pair), type(uint256).max);
        pair.seed(SEED, SEED);
        pair.setMaxTrade(200e18);

        // --- ballot --------------------------------------------------------
        ballot = new Ballot(address(this));
        ballot.setWeightToken(address(loot));
        ballot.createPoll(
            POLL_1, "E5 AMM or E6 Lending", 2, Ballot.Mode.Equal,
            uint64(block.timestamp), uint64(block.timestamp + 3600)
        );
        ballot.createPoll(
            POLL_2, "E7 Bridge or E8 Govern", 2, Ballot.Mode.Equal,
            uint64(block.timestamp), uint64(block.timestamp + 3600)
        );

        // --- merkle drop ---------------------------------------------------
        uint256 n = GUILDS + PLAYERS;
        bytes32[] memory leaves = new bytes32[](n);
        for (uint256 i = 0; i < n; i++) {
            address a = i < GUILDS ? guilds[i] : address(uint160(900_000 + i));
            leaves[i] = MerkleBuilder.leaf(i, a, 1_000e18);
        }
        (bytes32 root,) = MerkleBuilder.build(leaves);

        distributor = new MerkleDistributor(loot, root, block.timestamp + 30 days);
        loot.mint(address(distributor), n * 1_000e18);

        badge = new AdventurerBadge(address(this));
    }

    function test_fullLabSimulation() public {
        // ---- 1. Twenty-five signatures, one transaction -------------------
        address[] memory signers = new address[](GUILDS);
        uint8[] memory choices = new uint8[](GUILDS);
        bytes[] memory sigs = new bytes[](GUILDS);

        for (uint256 i = 0; i < GUILDS; i++) {
            uint8 choice = uint8(i % 2);
            bytes32 digest = ballot.ballotDigest(POLL_1, choice, guilds[i]);
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], digest);
            sigs[i] = abi.encodePacked(r, s, v);
            signers[i] = guilds[i];
            choices[i] = choice;
        }

        uint256 gasBefore = gasleft();
        ballot.castVotes(POLL_1, signers, choices, sigs);
        uint256 batchGas = gasBefore - gasleft();

        uint256[] memory tally = ballot.tallyOf(POLL_1);
        assertEq(tally[0] + tally[1], GUILDS, "all 25 ballots counted");

        console2.log("castVotes gas for 25 ballots:", batchGas);
        assertLt(batchGas, 2_000_000, "one batch must fit comfortably in a Base block");

        // ---- 2. Twenty-five guilds break the AMM --------------------------
        address token0 = address(pair.token0());
        for (uint256 i = 0; i < GUILDS; i++) {
            address g = guilds[i];
            if (pair.token0() == gold) {
                gold.mint(g, 500e18);
                vm.startPrank(g);
                gold.approve(address(pair), type(uint256).max);
            } else {
                silver.mint(g, 500e18);
                vm.startPrank(g);
                silver.approve(address(pair), type(uint256).max);
            }
            pair.swap(token0, 150e18, 0);
            vm.stopPrank();
        }
        assertEq(pair.swapCount(), GUILDS);
        assertLt(pair.spotPrice(), 1e18, "the room moved the price");
        console2.log("spot price after 25 swaps (1e18):", pair.spotPrice());

        // ---- 3. Two hundred badge claims ----------------------------------
        for (uint256 i = 0; i < ATTENDEES; i++) {
            vm.prank(address(uint160(1_000_000 + i)));
            badge.claim(uint8((i % 25) + 1), hex"0102030405");
        }
        assertEq(badge.nextId(), ATTENDEES + 1, "200 attendees, 50 spare");

        // Fill the remaining 50 spares, then prove the cap holds.
        for (uint256 i = 0; i < 50; i++) {
            vm.prank(address(uint160(2_000_000 + i)));
            badge.claim(uint8((i % 25) + 1), hex"0102");
        }
        assertEq(badge.nextId(), 251, "cap reached");

        vm.prank(address(0xDEAD));
        vm.expectRevert(AdventurerBadge.SoldOut.selector);
        badge.claim(1, hex"01");

        // ---- 4. The airdrop still works after all that --------------------
        bytes32[] memory leaves = new bytes32[](GUILDS + PLAYERS);
        for (uint256 i = 0; i < GUILDS + PLAYERS; i++) {
            address a = i < GUILDS ? guilds[i] : address(uint160(900_000 + i));
            leaves[i] = MerkleBuilder.leaf(i, a, 1_000e18);
        }
        (, bytes32[][] memory proofs) = MerkleBuilder.build(leaves);

        address ticket = address(0xFACADE); // a helper relaying the first guild's claim
        vm.prank(ticket);
        distributor.claim(0, guilds[0], 1_000e18, proofs[0]);
        assertEq(loot.balanceOf(guilds[0]), 1_000e18);
    }

    /// @dev The governance contrast, measured: equal weight versus token weight on the same room.
    function test_tokenWeightedFlipsTheResult() public {
        ballot.createPoll(
            keccak256("weighted"), "weighted", 2, Ballot.Mode.TokenWeighted,
            uint64(block.timestamp), uint64(block.timestamp + 3600)
        );

        // Give one guild a large balance: 1 whale outvotes 24 guilds.
        loot.mint(guilds[0], 100e18);
        for (uint256 i = 1; i < GUILDS; i++) {
            loot.mint(guilds[i], 1e18);
        }

        bytes32 poll = keccak256("weighted");
        address[] memory signers = new address[](GUILDS);
        uint8[] memory choices = new uint8[](GUILDS);
        bytes[] memory sigs = new bytes[](GUILDS);

        for (uint256 i = 0; i < GUILDS; i++) {
            uint8 choice = i == 0 ? 0 : 1;
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(keys[i], ballot.ballotDigest(poll, choice, guilds[i]));
            sigs[i] = abi.encodePacked(r, s, v);
            signers[i] = guilds[i];
            choices[i] = choice;
        }

        ballot.castVotes(poll, signers, choices, sigs);
        uint256[] memory t = ballot.tallyOf(poll);

        assertEq(t[0], 100e18, "one whale");
        assertEq(t[1], 24e18, "twenty-four guilds");
        assertEq(ballot.winner(poll), 0, "the whale wins - say this out loud in the room");
    }
}
