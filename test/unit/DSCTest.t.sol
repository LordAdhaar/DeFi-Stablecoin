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
    uint256 public constant WETH_DEPOSIT_AMOUNT = 5e7;
    uint256 public constant BOB_STARTING_WETH_BALANCE = 1e8;
    address public BOB = makeAddr("bob");

    function setUp() external {
        deployDSCScript = new DeployDSCScript();
        (decentralizedStableCoin, dscEngine, activeNetwork) = deployDSCScript.run();

        wethAdress = activeNetwork.wETH;

        ERC20Mock(wethAdress).mint(BOB, BOB_STARTING_WETH_BALANCE);
    }

    function testGetUSDValue() public view {
        address wethAddress = activeNetwork.wETH;
        uint256 wethInUSD = dscEngine.getUSDValueOfCollateral(wethAddress, 15e18);
        assertEq(wethInUSD, 30000e18);
    }

    function testDepositCollateral() public {
        vm.startPrank(BOB);

        ERC20Mock(wethAdress).approve(address(dscEngine), 1e8);
        dscEngine.depositCollateral(wethAdress, WETH_DEPOSIT_AMOUNT);
        vm.stopPrank();

        uint256 bobCollateralAmount = dscEngine.getUserToCollateralTokenAmount(BOB, wethAdress);

        assertEq(bobCollateralAmount, 5e7);
    }

    function testOwnerTransferredToDSCEngine() public view {
        assertEq(address(dscEngine), decentralizedStableCoin.owner());
    }
}
