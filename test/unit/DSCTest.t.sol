// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {console} from "../../lib/forge-std/src/console.sol";
import {DeployDSCScript} from "../../script/DeployDSCScript.s.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";

contract DSCTest is Test {
    DeployDSCScript public deployDSCScript;
    DSCEngine public dscEngine;
    DecentralizedStableCoin public decentralizedStableCoin;

    function setUp() external {
        deployDSCScript = new DeployDSCScript();
        (decentralizedStableCoin, dscEngine) = deployDSCScript.run();
    }

    function testNothing() public view {
        assertEq(address(dscEngine), decentralizedStableCoin.owner());
    }
}
