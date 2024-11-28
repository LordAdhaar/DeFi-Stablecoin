// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {DeployDSCScript} from "../../script/DeployDSCScript.s.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import {Test, console} from "../../lib/forge-std/src/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";
import {Handler} from "./Handler.t.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

// Inavariant to be tested = DSC minted < CollateralAmountInUSD

contract OpenInvariantsTest is Test {
    DSCEngine public dscEngine;
    DecentralizedStableCoin public decentralizedStableCoin;

    HelperConfig.NetworkConfig public activeNetworkConfig;
    DeployDSCScript public deployDSCScript;

    Handler public handler;

    address public wethTokenAddress;
    address public wbtcTokenAddress;

    function setUp() external {
        deployDSCScript = new DeployDSCScript();
        (decentralizedStableCoin, dscEngine, activeNetworkConfig) = deployDSCScript.run();

        wethTokenAddress = activeNetworkConfig.wETH;
        wbtcTokenAddress = activeNetworkConfig.wBTC;

        handler = new Handler(dscEngine, decentralizedStableCoin);

        targetContract(address(handler));
    }

    function invariant_mintedDscLessThanCollateralInUsd() public view {
        uint256 totalMintedDsc = decentralizedStableCoin.totalSupply();

        uint256 wethCollateralAmount = ERC20Mock(wethTokenAddress).balanceOf(address(dscEngine));
        uint256 wbtcCollateralAmount = ERC20Mock(wbtcTokenAddress).balanceOf(address(dscEngine));

        uint256 wethCollateralAmountInUsd = dscEngine.getUSDValueOfCollateral(wethTokenAddress, wethCollateralAmount);
        uint256 wbtcCollateralAmountInUsd = dscEngine.getUSDValueOfCollateral(wbtcTokenAddress, wbtcCollateralAmount);

        assert(totalMintedDsc <= wethCollateralAmountInUsd + wbtcCollateralAmountInUsd);
    }
}
