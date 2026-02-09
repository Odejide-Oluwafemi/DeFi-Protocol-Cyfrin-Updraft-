// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

import {Test} from "forge-std/Test.sol";
// import {StdInvariant} from "forge-std/StdInvariant.sol";
import {OpenInvariantsTest} from "test/fuzz/OpenInvariantTest.t.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract Handler is Test {
  DecentralizedStableCoin dsc;
  DSCEngine engine;
  ERC20Mock weth;
  ERC20Mock wbtc;

  uint256 constant MAX_DEPOSIT_SIZE = type(uint96).max;

  constructor(DecentralizedStableCoin _dsc, DSCEngine _engine) {
    dsc = _dsc;
    engine = _engine;

    address[] memory collateralTokens = engine.getCollateralTokens();
    weth = ERC20Mock(collateralTokens[0]);
    wbtc = ERC20Mock(collateralTokens[1]);
  }

  function depositCollateral(uint256 collateralSeed, uint256 amountCollateral) public {
    ERC20Mock collateral = _getCollateralFromSeed(collateralSeed);
    amountCollateral = bound(amountCollateral, 1, MAX_DEPOSIT_SIZE);

    vm.startPrank(msg.sender);
    collateral.mint(msg.sender, amountCollateral);
    collateral.approve(address(engine), amountCollateral);
    engine.depositCollateral(address(collateral), amountCollateral);

    vm.stopPrank();
  }

  function _getCollateralFromSeed(uint256 collateralSeed) private view returns (ERC20Mock) {
    if (collateralSeed % 2 == 0) return weth;
    else return wbtc;
  }
}