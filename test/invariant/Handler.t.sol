// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {TSwapPool} from "../../src/TSwapPool.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    TSwapPool pool;
    ERC20Mock weth;
    ERC20Mock poolToken;

    address liquidityProvider = makeAddr("LP");
    address swapper = makeAddr("swapper");

    // Ghost variables (they don't exist in the contract, only in our handler)
    int256 public startingY; // weth
    int256 public startingX; // poolToken
    int256 public expectedDeltaY; 
    int256 public expectedDeltaX; 
    int256 public actualDeltaY; 
    int256 public actualDeltaX; 


    constructor(TSwapPool _pool) {
        pool = _pool;
        weth = ERC20Mock(_pool.getWeth());
        poolToken = ERC20Mock(_pool.getPoolToken());
    }
    
    function deposit(uint256 wethAmount) public {
        uint256 minWethDeposit = pool.getMinimumWethDepositAmount();
        wethAmount = bound(wethAmount, minWethDeposit, type(uint64).max); // Below 19 ETH max, but let's go with that for now
        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));
        expectedDeltaY = int256(wethAmount);
        expectedDeltaX = int256(pool.getPoolTokensToDepositBasedOnWeth(wethAmount));

        vm.startPrank(liquidityProvider);
        weth.mint(liquidityProvider, wethAmount); 
        poolToken.mint(liquidityProvider, uint256(expectedDeltaX)); 
        weth.approve(address(pool), type(uint256).max);
        poolToken.approve(address(pool), type(uint256).max);

        pool.deposit(wethAmount, 0, uint256(expectedDeltaX), uint64(block.timestamp));
        vm.stopPrank();

        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);
    }

    function swapPoolTokenForWethBasedOnOutputWeth(uint256 outputWeth) public {
        uint256 minWethDeposit = pool.getMinimumWethDepositAmount();
        outputWeth = bound(outputWeth, minWethDeposit, type(uint64).max);
        if (outputWeth >= weth.balanceOf(address(pool))) {
            return;
        }

        // ∆x = (β/(1-β)) * x
        uint256 poolTokenAmount = pool.getInputAmountBasedOnOutput(outputWeth, poolToken.balanceOf(address(pool)), weth.balanceOf(address(pool)));

        if (poolTokenAmount >= type(uint64).max){
            return;
        }

        startingY = int256(weth.balanceOf(address(pool)));
        startingX = int256(poolToken.balanceOf(address(pool)));
        expectedDeltaY = int256(-1) * int256(outputWeth); // the pool has WETH withdrawn when the poolToken is swapped for it, so delta is negative
        expectedDeltaX = int256(poolTokenAmount);

        if(poolToken.balanceOf(swapper) < poolTokenAmount){
            poolToken.mint(swapper, poolTokenAmount - poolToken.balanceOf(swapper) + 1);
        }

        vm.startPrank(swapper);
        poolToken.approve(address(pool), type(uint256).max);
        pool.swapExactOutput(poolToken, weth, outputWeth, uint64(block.timestamp));
        vm.stopPrank();
        
        uint256 endingY = weth.balanceOf(address(pool));
        uint256 endingX = poolToken.balanceOf(address(pool));

        actualDeltaY = int256(endingY) - int256(startingY);
        actualDeltaX = int256(endingX) - int256(startingX);

    }
}