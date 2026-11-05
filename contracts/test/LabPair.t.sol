// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {LabToken} from "../src/LabToken.sol";
import {LabPair} from "../src/LabPair.sol";

/// @notice Encounter E5. The room breaks this on purpose; the guardrails must hold.
contract LabPairTest is Test {
    LabToken gold;
    LabToken silver;
    LabPair pair;

    address trader = address(0x7ADE);

    uint256 constant SEED = 50_000e18;

    function setUp() public {
        gold = new LabToken("Gold", "GOLD", 1_000_000e18, address(this));
        silver = new LabToken("Silver", "SILVER", 1_000_000e18, address(this));

        pair = new LabPair(address(gold), address(silver), address(this));

        gold.mint(address(this), SEED * 2);
        silver.mint(address(this), SEED * 2);
        gold.approve(address(pair), type(uint256).max);
        silver.approve(address(pair), type(uint256).max);
        pair.seed(SEED, SEED);

        gold.mint(trader, 10_000e18);
        silver.mint(trader, 10_000e18);

        vm.startPrank(trader);
        gold.approve(address(pair), type(uint256).max);
        silver.approve(address(pair), type(uint256).max);
        vm.stopPrank();
    }

    function test_startsAtOneToOne() public view {
        assertEq(pair.spotPrice(), 1e18);
    }

    function test_swapMovesPrice() public {
        address token0 = address(pair.token0());
        address token1 = address(pair.token1());

        uint256 out = pair.getAmountOut(token0, 1_000e18);
        assertGt(out, 0);

        vm.prank(trader);
        pair.swap(token0, 1_000e18, 0);

        // Selling token0 in pushes its price down relative to token1.
        assertLt(pair.spotPrice(), 1e18);
        assertEq(pair.swapCount(), 1);

        (uint256 r0, uint256 r1) = pair.getReserves();
        assertGt(r0, SEED);
        assertLt(r1, SEED);
        assertGt(pair.getAmountOut(token1, 1_000e18), 0);
    }

    function test_feeIsTakenFromInput() public view {
        address token0 = address(pair.token0());
        uint256 out = pair.getAmountOut(token0, 1_000e18);

        // No-fee constant product for comparison.
        uint256 noFee = (1_000e18 * SEED) / (SEED + 1_000e18);
        assertLt(out, noFee);
        assertApproxEqRel(out, noFee, 0.005e18); // fee is 30bps, so out is ~0.3% lower
    }

    function test_priceImpactGrowsWithSize() public view {
        address token0 = address(pair.token0());
        uint256 small = pair.priceImpactBps(token0, 100e18);
        uint256 large = pair.priceImpactBps(token0, 5_000e18);
        assertLt(small, large);
        assertGt(large, 100); // 5000/50000 = 10% of reserves in, so impact is roughly 9-10%
    }

    function test_maxTradeIsEnforced() public {
        pair.setMaxTrade(200e18);
        address token0 = address(pair.token0()); // hoisted: an inline call would consume the prank
        vm.prank(trader);
        vm.expectRevert(LabPair.TradeTooLarge.selector);
        pair.swap(token0, 201e18, 0);
    }

    function test_slippageProtectionReverts() public {
        address token0 = address(pair.token0());
        uint256 out = pair.getAmountOut(token0, 1_000e18);
        vm.prank(trader);
        vm.expectRevert(LabPair.Slippage.selector);
        pair.swap(token0, 1_000e18, out + 1);
    }

    function test_cannotReseed() public {
        vm.expectRevert(LabPair.AlreadySeeded.selector);
        pair.seed(1, 1);
    }

    function testFuzz_swapPreservesK(uint256 amountIn) public {
        amountIn = bound(amountIn, 1e18, 5_000e18);
        uint256 kBefore = pair.reserve0() * pair.reserve1();

        vm.prank(trader);
        pair.swap(address(pair.token0()), amountIn, 0);

        uint256 kAfter = pair.reserve0() * pair.reserve1();
        assertGe(kAfter, kBefore); // fee accrues to the pool, so k never decreases
    }
}
