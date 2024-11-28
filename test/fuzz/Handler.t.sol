// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public decentralizedStableCoin;
    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        dscEngine = _dscEngine;
        decentralizedStableCoin = _decentralizedStableCoin;
    }

    function handlerDepositCollateral(uint256 randomNumber, uint256 tokenAmount) public {
        tokenAmount = bound(tokenAmount, 1, MAX_DEPOSIT_SIZE);
        address tokenAddress = getValidCollateralAddress(randomNumber);

        ERC20Mock(tokenAddress).mint(address(this), tokenAmount);
        ERC20Mock(tokenAddress).approve(address(dscEngine), tokenAmount);

        dscEngine.depositCollateral(tokenAddress, tokenAmount);
    }

    function getValidCollateralAddress(uint256 randomNumber) public view returns (address) {
        address[] memory tokenAddresses = dscEngine.getTokensAcceptedAsCollateral();

        if (randomNumber % 2 == 0) {
            return tokenAddresses[0];
        }
        return tokenAddresses[1];
    }
}
