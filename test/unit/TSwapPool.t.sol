// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import { Test, console } from "forge-std/Test.sol";
import { TSwapPool } from "../../src/PoolFactory.sol";
import { ERC20Mock } from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import { WeirdERC20Mock } from "../mocks/WeirdERC20Mock.sol";
import { IERC20 } from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TSwapPoolTest is Test {
    TSwapPool pool;
    ERC20Mock poolToken;
    ERC20Mock weth;
    WeirdERC20Mock feeOnTransferPoolToken;

    address liquidityProvider = makeAddr("liquidityProvider");
    address user = makeAddr("user");

    function setUp() public {
        poolToken = new ERC20Mock();
        weth = new ERC20Mock();
        pool = new TSwapPool(address(poolToken), address(weth), "LTokenA", "LA");

        weth.mint(liquidityProvider, 200e18);
        poolToken.mint(liquidityProvider, 200e18);

        weth.mint(user, 10e18);
        poolToken.mint(user, 10e18);
    }

    function testDeposit() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.balanceOf(liquidityProvider), 100e18);
        assertEq(weth.balanceOf(liquidityProvider), 100e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 100e18);

        assertEq(weth.balanceOf(address(pool)), 100e18);
        assertEq(poolToken.balanceOf(address(pool)), 100e18);
    }

    function testDepositSwap() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        poolToken.approve(address(pool), 10e18);
        // After we swap, there will be ~110 tokenA, and ~91 WETH
        // 100 * 100 = 10,000
        // 110 * ~91 = 10,000
        uint256 expected = 9e18;

        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        assert(weth.balanceOf(user) >= expected);
    }

    function testWithdraw() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));

        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 100e18, 100e18, uint64(block.timestamp));

        assertEq(pool.totalSupply(), 0);
        assertEq(weth.balanceOf(liquidityProvider), 200e18);
        assertEq(poolToken.balanceOf(liquidityProvider), 200e18);
    }

    function testCollectFees() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(user);
        uint256 expected = 9e18;
        poolToken.approve(address(pool), 10e18);
        pool.swapExactInput(poolToken, 10e18, weth, expected, uint64(block.timestamp));
        vm.stopPrank();

        vm.startPrank(liquidityProvider);
        pool.approve(address(pool), 100e18);
        pool.withdraw(100e18, 90e18, 100e18, uint64(block.timestamp));
        assertEq(pool.totalSupply(), 0);
        assert(weth.balanceOf(liquidityProvider) + poolToken.balanceOf(liquidityProvider) > 400e18);
    }

    function testSwapExactOutputChargesEnormousFee() external {
        // Crate the pool
        uint256 initialLiquidity = 100 ether;
        vm.startPrank(liquidityProvider);
        poolToken.approve(address(pool), initialLiquidity);
        weth.approve(address(pool), initialLiquidity);
        pool.deposit({
            wethToDeposit: initialLiquidity,
            minimumLiquidityTokensToMint: 0,
            maximumPoolTokensToDeposit: initialLiquidity,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();

        // Give the swapper a starting poolToken balance
        address swapper = makeAddr("swapper");
        uint256 swapperInitialPoolTokenBalance = 20 ether;
        poolToken.mint(swapper, swapperInitialPoolTokenBalance);

        // Swapper tries to swap poolTokens for 1 WETH (which should cost about 1 poolToken, since the original ratio is 1:1)
        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput({
            inputToken: poolToken,
            outputToken: weth,
            outputAmount: 1 ether,
            deadline: uint64(block.timestamp)
        });
        vm.stopPrank();

        // Check that the swapper has spent over 10 poolTokens instead of approximately 1 that was expected
        assertLt(poolToken.balanceOf(swapper), 10 ether);
    }

    function testInvariantBroken() public {
        vm.startPrank(liquidityProvider);
        weth.approve(address(pool), 100e18);
        poolToken.approve(address(pool), 100e18);
        pool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        uint256 outputWeth = 1e17;

        vm.startPrank(user);
        poolToken.approve(address(pool), type(uint256).max);
        poolToken.mint(user, 100e18);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));

        int256 startingY = int256(weth.balanceOf(address(pool)));
        int256 expectedDeltaY = int256(-1) * int256(outputWeth);

        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        int256 actualDeltaY = int256(endingY) - int256(startingY);
        assertEq(actualDeltaY, expectedDeltaY);
    }

    // This proof of code is not done! Finish later!
    function testWeirdERC20BreaksInvariant() external {

        // Complete setup
        TSwapPool weirdPool;        
        feeOnTransferPoolToken = new WeirdERC20Mock();
        weirdPool = new TSwapPool(address(feeOnTransferPoolToken), address(weth), "LTokenB", "LB");
        weth.mint(liquidityProvider, 200e18);
        feeOnTransferPoolToken.mint(liquidityProvider, 200e18);
        feeOnTransferPoolToken.mint(user, 10e18);

        // Test
        vm.startPrank(liquidityProvider);
        weth.approve(address(weirdPool), 100e18);
        feeOnTransferPoolToken.approve(address(weirdPool), 100e18);
        weirdPool.deposit(100e18, 100e18, 100e18, uint64(block.timestamp));
        vm.stopPrank();

        uint256 outputWeth = 5 ether;

        vm.startPrank(user);
        feeOnTransferPoolToken.approve(address(weirdPool), type(uint256).max);
        feeOnTransferPoolToken.mint(user, 100e18);
        // int256 startingY = int256(weth.balanceOf(address(weirdPool)));
        // int256 expectedDeltaY = int256(-1) * int256(outputWeth);
        int256 startingX = int256(feeOnTransferPoolToken.balanceOf(address(weirdPool)));
        int256 expectedDeltaX = int256(-1) * int256(outputWeth);

        weirdPool.swapExactOutput(feeOnTransferPoolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(weirdPool));
        int256 actualDeltaY = int256(endingY) - int256(startingY);
        assertEq(actualDeltaY, expectedDeltaY);
    }
}
