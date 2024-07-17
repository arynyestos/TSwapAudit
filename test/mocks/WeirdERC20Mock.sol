// SPDX-License-Identifier: MIT 

pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract WeirdERC20Mock is ERC20{
    constructor() ERC20("WeirdERC20", "WERC20"){}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function transfer(address to, uint256 value) public override returns (bool) {
        address owner = _msgSender();
        value = value * 99 / 100; // 1% fee on transfer
        _transfer(owner, to, value);
        return true;
    }
}