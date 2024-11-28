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

    function handleRedeemCollateral(uint256 randomNumber, uint256 tokenAmount) public {
        address tokenAddress = getValidCollateralAddress(randomNumber);
        uint256 collateralBalance = dscEngine.getUserToCollateralTokenAmount(address(this), tokenAddress);

        tokenAmount = bound(tokenAmount, 0, collateralBalance);

        if (tokenAmount == 0) {
            return;
        }

        dscEngine.redeemCollateral(tokenAddress, tokenAmount);
    }

    // function handleMintDsc(uint256 tokenAmount) public {
    //     (uint256 amountMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(address(this));
    //     int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(amountMinted);

    //     if (maxDscToMint < 0) {
    //         return;
    //     }

    //     tokenAmount = bound(tokenAmount, 0, uint256(maxDscToMint));

    //     if (tokenAmount == 0) {
    //         return;
    //     }
    //     dscEngine.mintDSC(tokenAmount);
    // }

    function getValidCollateralAddress(uint256 randomNumber) public view returns (address) {
        address[] memory tokenAddresses = dscEngine.getTokensAcceptedAsCollateral();

        if (randomNumber % 2 == 0) {
            return tokenAddresses[0];
        }
        return tokenAddresses[1];
    }
}
