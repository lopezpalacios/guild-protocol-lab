// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title LabPair
/// @notice Encounter E5. A constant-product market maker the room is allowed to break.
/// @dev Deliberately NOT Uniswap. We seed our own pair at T-7 with 50k/50k so that the demo
///      cannot die from thin testnet liquidity, and so the price curve is small enough that
///      twenty-five guilds moving it is visible on a projector.
///
///      Two deliberate simplifications, both of which are stated on screen:
///      - No LP tokens. Liquidity is operator-seeded and never withdrawn. Real pools pay LPs.
///      - `maxTrade` is a hard cap enforced on-chain, so one enthusiastic guild cannot drain
///        the pool and end the lab early.
contract LabPair is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    IERC20 public immutable token0;
    IERC20 public immutable token1;

    uint256 public reserve0;
    uint256 public reserve1;

    /// @notice 30 basis points, i.e. 0.30%. Same as Uniswap V2, so the number is familiar.
    uint256 public constant FEE_BPS = 30;
    uint256 public constant BPS = 10_000;

    /// @notice Max tokens per single swap, in token base units. 0 means unlimited.
    /// @dev This is the guardrail that keeps the demo alive. Set it before doors open.
    uint256 public maxTrade;

    uint256 public swapCount;

    event Seeded(uint256 reserve0, uint256 reserve1);
    event Swap(
        address indexed trader,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut,
        uint256 reserve0,
        uint256 reserve1
    );

    error BadToken();
    error ZeroAmount();
    error TradeTooLarge();
    error Slippage();
    error AlreadySeeded();

    constructor(address tokenA, address tokenB, address owner_) Ownable(owner_) {
        if (tokenA == tokenB) revert BadToken();
        (token0, token1) = tokenA < tokenB
            ? (IERC20(tokenA), IERC20(tokenB))
            : (IERC20(tokenB), IERC20(tokenA));
    }

    // ---------------------------------------------------------------------

    /// @notice One-time liquidity seed. Pulls both tokens from the caller.
    function seed(uint256 amount0, uint256 amount1) external onlyOwner {
        if (reserve0 != 0 || reserve1 != 0) revert AlreadySeeded();
        token0.safeTransferFrom(msg.sender, address(this), amount0);
        token1.safeTransferFrom(msg.sender, address(this), amount1);
        _sync();
        emit Seeded(reserve0, reserve1);
    }

    function setMaxTrade(uint256 maxTrade_) external onlyOwner {
        maxTrade = maxTrade_;
    }

    /// @notice Swap `amountIn` of `tokenIn` for the other token.
    /// @param minOut Slippage protection. The UI sets it from a quote taken ~2 seconds earlier.
    function swap(address tokenIn, uint256 amountIn, uint256 minOut)
        external
        nonReentrant
        returns (uint256 amountOut)
    {
        if (amountIn == 0) revert ZeroAmount();
        if (maxTrade != 0 && amountIn > maxTrade) revert TradeTooLarge();

        bool zeroForOne = tokenIn == address(token0);
        if (!zeroForOne && tokenIn != address(token1)) revert BadToken();

        (uint256 reserveIn, uint256 reserveOut) =
            zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);

        amountOut = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (amountOut < minOut) revert Slippage();
        if (amountOut >= reserveOut) revert Slippage();

        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        IERC20(zeroForOne ? address(token1) : address(token0)).safeTransfer(msg.sender, amountOut);

        _sync();
        swapCount += 1;

        emit Swap(msg.sender, tokenIn, amountIn, amountOut, reserve0, reserve1);
    }

    // ---------------------------------------------------------------------
    // Pricing
    // ---------------------------------------------------------------------

    /// @notice Classic constant product with the fee taken out of the input.
    function getAmountOut(address tokenIn, uint256 amountIn) public view returns (uint256) {
        bool zeroForOne = tokenIn == address(token0);
        if (!zeroForOne && tokenIn != address(token1)) revert BadToken();
        (uint256 reserveIn, uint256 reserveOut) =
            zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);
        return _getAmountOut(amountIn, reserveIn, reserveOut);
    }

    /// @notice Price of one token0 expressed in token1, scaled by 1e18.
    /// @dev The number the projector shows. It moves because the room moved it.
    function spotPrice() external view returns (uint256) {
        if (reserve0 == 0) return 0;
        return (reserve1 * 1e18) / reserve0;
    }

    /// @notice The same trade against the same reserves if the fee were zero.
    /// @dev Used to show the cost of the fee separately from the cost of the curve.
    function spotPriceAfter(address tokenIn, uint256 amountIn) external view returns (uint256) {
        bool zeroForOne = tokenIn == address(token0);
        (uint256 reserveIn, uint256 reserveOut) =
            zeroForOne ? (reserve0, reserve1) : (reserve1, reserve0);
        if (reserveIn == 0) return 0;
        uint256 out = _getAmountOut(amountIn, reserveIn, reserveOut);
        if (zeroForOne) return ((reserveOut - out) * 1e18) / (reserveIn + amountIn);
        return ((reserveIn + amountIn) * 1e18) / (reserveOut - out);
    }

    function priceImpactBps(address tokenIn, uint256 amountIn) external view returns (uint256) {
        uint256 before = (reserve1 * 1e18) / reserve0;
        bool zeroForOne = tokenIn == address(token0);
        uint256 out = getAmountOut(tokenIn, amountIn);
        uint256 afterPrice = zeroForOne
            ? ((reserve1 - out) * 1e18) / (reserve0 + amountIn)
            : ((reserve1 + amountIn) * 1e18) / (reserve0 - out);
        if (before == 0) return 0;
        return afterPrice > before
            ? ((afterPrice - before) * BPS) / before
            : ((before - afterPrice) * BPS) / before;
    }

    function getReserves() external view returns (uint256, uint256) {
        return (reserve0, reserve1);
    }

    // ---------------------------------------------------------------------
    // Internal
    // ---------------------------------------------------------------------

    function _getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        internal
        pure
        returns (uint256)
    {
        if (reserveIn == 0 || reserveOut == 0) return 0;
        uint256 amountInWithFee = amountIn * (BPS - FEE_BPS);
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * BPS + amountInWithFee;
        return numerator / denominator;
    }

    function _sync() internal {
        reserve0 = token0.balanceOf(address(this));
        reserve1 = token1.balanceOf(address(this));
    }
}
