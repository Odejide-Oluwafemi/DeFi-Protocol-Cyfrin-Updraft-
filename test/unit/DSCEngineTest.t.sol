// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
import {DeployDSC} from "script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DSCEngineTest is Test {
  DeployDSC deployer;
  DecentralizedStableCoin dsc;
  DSCEngine engine;
  HelperConfig config;
  address ethUsdPriceFeed;
  address btcUsdPriceFeed;
  address weth;

  function setUp() public {
    deployer = new DeployDSC();
    (dsc, engine, config) = deployer.run();
    (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();
  }

  // Constructor Tests
  address[] public tokenAddresses;
  address[] public priceFeedAddresses;

  function testRevertsIfTokenLengthDoestMatchPriceFeeds() public {
    tokenAddresses.push(weth);
    priceFeedAddresses.push(ethUsdPriceFeed);
    priceFeedAddresses.push(btcUsdPriceFeed);

    vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
    new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
  }


  // PriceFeed Tests
  function testGetUsdValue() public view {
    uint256 ethAmount = 15 ether;
    uint256 expectedUsd = 30000 ether;
    uint256 actualUsd = engine.getUsdValue(weth, ethAmount);
    assertEq(expectedUsd, actualUsd);
  }

  function testGetTokenAmountFromUsd() public view {
    uint256 usdAmount = 100 ether;
    uint256 expectedWeth = 0.05 ether;
    uint256 actualWeth = engine.getTokenAmountFromUsd(weth, usdAmount);

    assertEq(actualWeth, expectedWeth);
  }
}