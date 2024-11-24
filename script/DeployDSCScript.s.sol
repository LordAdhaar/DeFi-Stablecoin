// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {DecentralizedStableCoin} from "../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../src/DSCEngine.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract DeployDSCScript is Script {
    DecentralizedStableCoin public decentralizedStableCoin;
    DSCEngine public dscEngine;
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function run() public returns (DecentralizedStableCoin, DSCEngine) {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory activeNetworkConfig = helperConfig.getActiveNetworkConfig();

        tokenAddresses = [activeNetworkConfig.wETH, activeNetworkConfig.wBTC];
        priceFeedAddresses = [activeNetworkConfig.wethPriceFeedUSD, activeNetworkConfig.wbtcPriceFeedUSD];

        vm.startBroadcast();

        decentralizedStableCoin = new DecentralizedStableCoin();
        dscEngine = new DSCEngine(tokenAddresses, priceFeedAddresses, address(decentralizedStableCoin));

        decentralizedStableCoin.transferOwnership(address(dscEngine));

        vm.stopBroadcast();

        return (decentralizedStableCoin, dscEngine);
    }
}
