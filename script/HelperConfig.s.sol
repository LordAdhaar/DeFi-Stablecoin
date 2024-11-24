// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Script} from "../lib/forge-std/src/Script.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "../test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    struct NetworkConfig {
        address wETH;
        address wBTC;
        address wethPriceFeedUSD;
        address wbtcPriceFeedUSD;
    }

    NetworkConfig public activeNetworkConfig;

    uint256 public constant ANVIL_CHAIN_ID = 31337;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint8 public constant DECIMALS = 8;
    int256 public constant ETH_USD_PRICE = 2000e8;
    int256 public constant BTC_USD_PRICE = 1000e8;

    constructor() {
        if (block.chainid == ANVIL_CHAIN_ID) {
            activeNetworkConfig = getOrCreateAnvilConfig();
        } else {
            activeNetworkConfig = getSepoliaConfig();
        }
    }

    function getSepoliaConfig() public pure returns (NetworkConfig memory) {
        NetworkConfig memory sepoliaConifg = NetworkConfig({
            wETH: 0xdd13E55209Fd76AfE204dBda4007C227904f0a81,
            wBTC: 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063,
            wethPriceFeedUSD: 0x694AA1769357215DE4FAC081bf1f309aDC325306,
            wbtcPriceFeedUSD: 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43
        });

        return sepoliaConifg;
    }

    function getOrCreateAnvilConfig() public returns (NetworkConfig memory) {
        if (activeNetworkConfig.wethPriceFeedUSD != address(0)) {
            return activeNetworkConfig;
        }

        vm.startBroadcast();

        MockV3Aggregator wethPriceFeedUSDMock = new MockV3Aggregator(DECIMALS, ETH_USD_PRICE);
        MockV3Aggregator wbtcPriceFeedUSDMock = new MockV3Aggregator(DECIMALS, BTC_USD_PRICE);

        ERC20Mock wethMock = new ERC20Mock("WETH", "WETH", msg.sender, 1000e8);
        ERC20Mock wbtcMock = new ERC20Mock("WBTC", "WBTC", msg.sender, 1000e8);
        vm.stopBroadcast();

        NetworkConfig memory anvilConfig = NetworkConfig({
            wETH: address(wethMock),
            wBTC: address(wbtcMock),
            wethPriceFeedUSD: address(wethPriceFeedUSDMock),
            wbtcPriceFeedUSD: address(wbtcPriceFeedUSDMock)
        });

        return anvilConfig;
    }

    function getActiveNetworkConfig() public view returns (NetworkConfig memory) {
        return activeNetworkConfig;
    }
}

//jo error aaye red vaala resolve pehle varna does not show new errors
