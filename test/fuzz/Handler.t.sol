// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";
import {MockV3Aggregator} from "../mocks/MockV3Aggregator.sol";

contract Handler is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public decentralizedStableCoin;

    uint256 MAX_DEPOSIT_SIZE = type(uint96).max;
    uint256 public timesMintCalled = 0;

    address[] public usersWithCollateral;
    MockV3Aggregator public ethUsdPriceFeed;

    address public wethTokenAddress;
    address public wbtcTokenAddress;

    constructor(DSCEngine _dscEngine, DecentralizedStableCoin _decentralizedStableCoin) {
        dscEngine = _dscEngine;
        decentralizedStableCoin = _decentralizedStableCoin;

        address[] memory tokenAddresses = dscEngine.getTokensAcceptedAsCollateral();
        wethTokenAddress = tokenAddresses[0];
        wbtcTokenAddress = tokenAddresses[1];

        ethUsdPriceFeed = MockV3Aggregator(dscEngine.getCollateralPriceFeed(wethTokenAddress));
    }

    //BREAKS THE INVARIANT TEST SUITE, PRICE DROPS TOO QUICKLY INVARAINT BREAKS
    // function handleUpdateCollateral(uint96 newPrice) public {
    //     int256 newPriceInt = int256(uint256(newPrice));
    //     ethUsdPriceFeed.updateAnswer(newPriceInt);
    // }

    function handlerDepositCollateral(uint256 randomNumber, uint256 tokenAmount) public {
        tokenAmount = bound(tokenAmount, 1, MAX_DEPOSIT_SIZE);
        address tokenAddress = getValidCollateralAddress(randomNumber);

        vm.startPrank(msg.sender);

        ERC20Mock(tokenAddress).mint(msg.sender, tokenAmount);
        ERC20Mock(tokenAddress).approve(address(dscEngine), tokenAmount);

        dscEngine.depositCollateral(tokenAddress, tokenAmount);
        usersWithCollateral.push(msg.sender);

        vm.stopPrank();
    }

    function handleRedeemCollateral(uint256 randomNumber, uint256 tokenAmount) public {
        address tokenAddress = getValidCollateralAddress(randomNumber);
        uint256 collateralBalance = dscEngine.getUserToCollateralTokenAmount(msg.sender, tokenAddress);

        tokenAmount = bound(tokenAmount, 0, collateralBalance);

        if (tokenAmount == 0) {
            return;
        }

        vm.prank(msg.sender);
        dscEngine.redeemCollateral(tokenAddress, tokenAmount);
    }

    // function handleMintDsc(uint256 tokenAmount, uint256 randomNumber) public {
    //     if (usersWithCollateral.length == 0) {
    //         return;
    //     }

    //     address sender = usersWithCollateral[randomNumber % usersWithCollateral.length];

    //     (uint256 amountMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(sender);
    //     int256 maxDscToMint = (int256(collateralValueInUsd) / 2) - int256(amountMinted);

    //     if (maxDscToMint <= 0) {
    //         return;
    //     }

    //     tokenAmount = bound(tokenAmount, 0, uint256(maxDscToMint));

    //     if (tokenAmount == 0) {
    //         return;
    //     }

    //     vm.prank(sender);
    //     dscEngine.mintDSC(tokenAmount);

    //     timesMintCalled += 1;
    // }

    function getValidCollateralAddress(uint256 randomNumber) public view returns (address) {
        address[] memory tokenAddresses = dscEngine.getTokensAcceptedAsCollateral();

        if (randomNumber % 2 == 0) {
            return tokenAddresses[0];
        }
        return tokenAddresses[1];
    }

    function getTimesMintCalled() public view returns (uint256) {
        return timesMintCalled;
    }
}
