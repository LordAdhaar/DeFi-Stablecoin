// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of the contract file:
// version
// imports
// errors
// interfaces, libraries, contract

// Inside Contract:
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// within function:
// payable
// non - payable
// view
// pure

/// @title DecentralizedStableCoin
/// @author Adhaar Jain
/// @notice Stablecoin pegged to the dollar, minted and burnt through algorithms to keep it decentralized and can be borrowed against eth and btc as collateral
/// Minting - Algorithmic
// Stability - Pegged to USD
// Collateral - BTC and ETH
// Will be governed by the DSCEngine.sol

import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

error DecentralizedStableCoin__BurnValueLessThanZero();
error DecentralizedStableCoin__BurnValueLessThanBalanceOfSender();
error DecentralizedStableCoin__MintAmountLessThanZero();

contract DecentralizedStableCoin is ERC20, ERC20Burnable, Ownable {
    constructor() ERC20("DecentralizedStableCoin", "DSC") Ownable(msg.sender) {}

    function burn(uint256 value) public override onlyOwner {
        uint256 balances = balanceOf(msg.sender);

        if (value <= 0) {
            revert DecentralizedStableCoin__BurnValueLessThanZero();
        }

        if (balances < value) {
            revert DecentralizedStableCoin__BurnValueLessThanBalanceOfSender();
        }
        super.burn(value);
    }

    function mint(address to, uint256 amount) public onlyOwner returns (bool) {
        if (amount <= 0) {
            revert DecentralizedStableCoin__MintAmountLessThanZero();
        }

        _mint(to, amount);
        return true;
    }
}
