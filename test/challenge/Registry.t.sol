// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console2} from "forge-std/Test.sol";
import {Registry} from "../../challenge/Registry.sol";

contract RegistryTest is Test {
    Registry registry;
    address alice;

    function setUp() public {
        alice = makeAddr("alice");
        
        registry = new Registry();
    }

    function test_register() public {
        uint256 amountToPay = registry.PRICE();
        
        vm.deal(alice, amountToPay);
        vm.startPrank(alice);

        uint256 aliceBalanceBefore = address(alice).balance;

        registry.register{value: amountToPay}();

        uint256 aliceBalanceAfter = address(alice).balance;
        
        assertTrue(registry.isRegistered(alice), "Did not register user");
        assertEq(address(registry).balance, registry.PRICE(), "Unexpected registry balance");
        assertEq(aliceBalanceAfter, aliceBalanceBefore - registry.PRICE(), "Unexpected user balance");
    }

    function test_registerGivesBackChange(uint256 feeToSend) external {
        if(feeToSend > 1 ether) {
            vm.deal(alice, feeToSend);
            vm.prank(alice);
            uint256 aliceBalanceBefore = address(alice).balance;
            registry.register{value: feeToSend}();
            uint256 aliceBalanceAfter = address(alice).balance;
            assertEq(aliceBalanceAfter, aliceBalanceBefore - registry.PRICE());
        } else return;
    }
}
