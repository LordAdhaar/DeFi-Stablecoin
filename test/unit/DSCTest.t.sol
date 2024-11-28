// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {DeployDSCScript} from "../../script/DeployDSCScript.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

contract DSCTest is Test {
    DeployDSCScript public deployDSCScript;

    DSCEngine public dscEngine;
    DecentralizedStableCoin public decentralizedStableCoin;
    HelperConfig.NetworkConfig public activeNetwork;

    address public wethAdress;
    address public wethPriceFeedUSD;
    address public btcPriceFeedUSD;

    address public BOB = makeAddr("bob");
    uint256 public constant BOB_STARTING_WETH_BALANCE = 20e18;

    uint256 public constant WETH_DEPOSIT_AMOUNT = 10e18;
    uint256 public constant WETH_REDEEM_AMOUNT = 5e18;

    uint256 public constant BOB_DSC_TO_BE_MINTED = 10000e18;
    uint256 public constant BOB_DSC_TO_BE_BURNT = 5000e18;

    function setUp() external {
        deployDSCScript = new DeployDSCScript();
        (decentralizedStableCoin, dscEngine, activeNetwork) = deployDSCScript.run();

        wethAdress = activeNetwork.wETH;
        wethPriceFeedUSD = activeNetwork.wethPriceFeedUSD;
        btcPriceFeedUSD = activeNetwork.wbtcPriceFeedUSD;

        ERC20Mock(wethAdress).mint(BOB, BOB_STARTING_WETH_BALANCE);
    }

    //////////////////////////////////
    ///// Contructor Test ///////////
    ////////////////////////////////

    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenAndPriceFeedArraysLengthUnequal() public {
        tokenAddresses.push(wethAdress);
        priceFeedAddresses.push(wethPriceFeedUSD);
        priceFeedAddresses.push(btcPriceFeedUSD);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAndPricfeedArrayLengthDifferent.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(decentralizedStableCoin));
    }

    function testOwnerTransferredToDSCEngine() public view {
        assertEq(address(dscEngine), decentralizedStableCoin.owner());
    }

    function testGetUSDValue() public view {
        address wethAddress = activeNetwork.wETH;
        uint256 wethInUSD = dscEngine.getUSDValueOfCollateral(wethAddress, 15e18);
        assertEq(wethInUSD, 30000e18);
    }

    function testGetCollateralAmountFromDebtCovered() public view {
        uint256 usdAmount = 4000e18;
        uint256 expectedAmount = 2e18;
        uint256 actualWeth = dscEngine.getCollateralAmountFromDebtCovered(wethAdress, usdAmount);

        assertEq(actualWeth, expectedAmount);
    }

    ////////////////////////////
    ///// Modifiers ///////////
    //////////////////////////

    //create modifier where we deposit somem collateral as bob
    modifier depositCollateral() {
        vm.startPrank(BOB);
        ERC20Mock(wethAdress).approve(address(dscEngine), WETH_DEPOSIT_AMOUNT);
        dscEngine.depositCollateral(wethAdress, WETH_DEPOSIT_AMOUNT);
        vm.stopPrank();
        _;
    }

    modifier depositCollateralAndMintDSC() {
        vm.startPrank(BOB);
        ERC20Mock(wethAdress).approve(address(dscEngine), WETH_DEPOSIT_AMOUNT);
        dscEngine.depositCollateralAndMintDSC(wethAdress, WETH_DEPOSIT_AMOUNT, BOB_DSC_TO_BE_MINTED);
        vm.stopPrank();
        _;
    }

    function testDepositCollateral() public depositCollateral {
        uint256 bobCollateralAmount = dscEngine.getUserToCollateralTokenAmount(BOB, wethAdress);

        assertEq(bobCollateralAmount, WETH_DEPOSIT_AMOUNT);
    }

    function testDepositCollateralAndMintDSC() public depositCollateralAndMintDSC {
        uint256 bobCollateralAmount = dscEngine.getUserToCollateralTokenAmount(BOB, wethAdress);
        uint256 bobDSCBalance = dscEngine.getUserToDSCBalance(BOB);

        assertEq(bobCollateralAmount, WETH_DEPOSIT_AMOUNT);
        assertEq(bobDSCBalance, BOB_DSC_TO_BE_MINTED);
    }

    function testRedeemCollateralForDSC() public depositCollateralAndMintDSC {
        uint256 bobCollateralAmount = dscEngine.getUserToCollateralTokenAmount(BOB, wethAdress);
        uint256 bobDSCBalance = dscEngine.getUserToDSCBalance(BOB);

        vm.startPrank(BOB);
        ERC20Mock(address(decentralizedStableCoin)).approve(address(dscEngine), BOB_DSC_TO_BE_BURNT);
        dscEngine.redeemCollateralForDSC(wethAdress, WETH_REDEEM_AMOUNT, BOB_DSC_TO_BE_BURNT);
        vm.stopPrank();

        bobCollateralAmount = dscEngine.getUserToCollateralTokenAmount(BOB, wethAdress);
        bobDSCBalance = dscEngine.getUserToDSCBalance(BOB);

        assertEq(bobCollateralAmount, WETH_DEPOSIT_AMOUNT - WETH_REDEEM_AMOUNT);
        assertEq(bobDSCBalance, BOB_DSC_TO_BE_MINTED - BOB_DSC_TO_BE_BURNT);
    }
}
