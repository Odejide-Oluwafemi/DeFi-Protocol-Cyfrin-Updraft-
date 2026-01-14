// SPDX-License-Identifier: MIT

// This is considered an Exogenous, Decentralized, Anchored (pegged), Crypto Collateralized low volitility coin

// Layout of Contract:
// version
// imports
// interfaces, libraries, contracts
// errors
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// view & pure functions

pragma solidity ^0.8.19;

// Imports
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {DecentralizedStableCoin} from "src/DecentralizedStableCoin.sol";

/**
 * @title DSCEngine
 * @author Odejide Oluwafemi
 *
 * The system is designed to be as minimal as possible, and have the tokens maintain a 1 token == $1 peg at all times.
 * This is a stablecoin with the properties:
 * - Exogenously Collateralized
 * - Dollar Pegged
 * - Algorithmically Stable
 *
 * It is similar to DAI if DAI had no governance, no fees, and was backed by only WETH and WBTC.
 *
 * Our DSC system should always be "overcollateralized". At no point, should the value of
 * all collateral <= the $ backed value of all the DSC.
 *
 * @notice This contract is the core of the Decentralized Stablecoin system. It handles all the logic
 * for minting and redeeming DSC, as well as depositing and withdrawing collateral.
 * @notice This contract is VERY loosely based on the MakerDAO DSS (DAI) system.
 */
contract DSCEngine is ReentrancyGuard {
    ////////////////
    //   Errors  //
    ///////////////
    error DSCEngine__NeedsMoreThanZero();
    error DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
    error DSCEngine__NotAllowedToken();
    error DSCEngine__TransferFailed();
    error DSCEngine__BreaksHealthFactor(uint256 userHealthFactor);
    error DSCEngine__MintFailed();

    //////////////////////////
    //    State Variables  //
    /////////////////////////
    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50; // 200% Overcollateralized
    uint256 private constant LIQUIDATION_PRECISION = 100; // 200% Overcollateralized
    uint256 private constant MIN_HEALTH_FACTOR = 1;

    DecentralizedStableCoin private immutable I_DSC;

    mapping(address token => address priceFeed) private sPriceFeeds;
    mapping(address user => mapping(address token => uint256 amount)) private sCollateralDeposited;
    mapping(address user => uint256 amountDscMinted) private sDscMinted;
    
    address[] private sCollateralTokens;

    ////////////////
    //   Events  //
    ///////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);

    ////////////////
    //  Modifiers //
    ////////////////
    modifier moreThanZero(uint256 amount) {
        _moreThanZero(amount);
        _;
    }

    modifier isAllowedToken(address token) {
        _isAllowedToken(token);
        _;
    }

    /////////////////
    //  Functions //
    ////////////////
    constructor(address[] memory tokenAddresses, address[] memory priceFeedsAddresses, address dscAddress) {
        // USD Price Feeds
        if (tokenAddresses.length != priceFeedsAddresses.length) {
            revert DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength();
        }

        for (uint256 i = 0; i < tokenAddresses.length; i++) {
            sPriceFeeds[tokenAddresses[i]] = priceFeedsAddresses[i];
            sCollateralTokens.push(tokenAddresses[i]);
        }

        I_DSC = DecentralizedStableCoin(dscAddress);
    }

    // External Functions

    function depositCollateralAndMintDsc() external {}

    /**
     * @notice follows CEI pattern
     * @param tokenCollateralAddress The Address of the token to deposit as collateral
     * @param amountCollateral The Amount of collateral to deposit
     */
    function depositCollateral(address tokenCollateralAddress, uint256 amountCollateral)
        external
        moreThanZero(amountCollateral)
        isAllowedToken(tokenCollateralAddress)
        nonReentrant
    {
        sCollateralDeposited[msg.sender][tokenCollateralAddress] += amountCollateral;
        emit CollateralDeposited(msg.sender, tokenCollateralAddress, amountCollateral);

        bool success = IERC20(tokenCollateralAddress).transferFrom(msg.sender, address(this), amountCollateral);
        if (!success) {
            revert DSCEngine__TransferFailed();
        }
    }

    function redeemCollateralForDsc() external {}

    function redeemCollateral() external {}

    /**
     * 
     * @param amountDscToMint The amount of DecentralizedStableCoin to mint
     * @notice They must have more collateral value than the minimum threshold
    */
    function mintDsc(uint256 amountDscToMint) external moreThanZero(amountDscToMint) nonReentrant {
      sDscMinted[msg.sender] += amountDscToMint;
      // if the minted too much ($100 ETH -> $150 DSC)
      _revertIfHealthFactorIsBroken(msg.sender);
      bool minted = I_DSC.mint(msg.sender, amountDscToMint);

      if (!minted) {
        revert DSCEngine__MintFailed();
      }
    }

    function burnDsc() external {}

    function liquidate() external {}

    // function _getHealthFactor() external view {}

    function _isAllowedToken(address token) internal view {
        if (sPriceFeeds[token] == address(0)) {
            revert DSCEngine__NotAllowedToken();
        }
    }

    function _moreThanZero(uint256 amount) internal pure {
        if (amount == 0) revert DSCEngine__NeedsMoreThanZero();
    }

    // Private & Internal View Functions
    /**
     * 
     * @param user User Address to check
     * @return totalDscMinted 
     * @return collateralValueInUsd 
     */
    function _getAccountInformation(address user) internal view returns (uint256 totalDscMinted, uint256 collateralValueInUsd) {
      totalDscMinted = sDscMinted[user];
      collateralValueInUsd = getAccountCollateralValueInUsd(user);
    }

    /**
     * @param user The user to check his health factor
     * @return How close to liquidtion the `user` is. If it is below 1, then the `user` can get liquidated
     */
    function _healthFactor(address user) private view returns (uint256) {
      // 1. Get their total DSC minted
      // 2. Get total collateral value
      (uint256 totalDscMinted, uint256 collateralValueInUsd) = _getAccountInformation(user);
      uint256 collateralAdjustedForThreshold = (collateralValueInUsd * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
      
      // $1000 ETH * 50 = 50,000 / 100 = 500
      // $1000 ETH * 50 = 50,000 / 100 = 500
      // $150 ETH * 50 = 7500 / 100 = (75 / 100) < 1

      return (collateralAdjustedForThreshold * LIQUIDATION_PRECISION) / totalDscMinted;
    }
    function _revertIfHealthFactorIsBroken(address user) internal view {
      // 1. Check Health Factor (do they have enough collateral?)
      uint256 userHealthFactor = _healthFactor(user);
      if (userHealthFactor < MIN_HEALTH_FACTOR) {
        revert DSCEngine__BreaksHealthFactor(userHealthFactor);
      }

      // 2. Revert if they do not have a good health factor
    }

    // Public & External View Functions
    /**
     * @param user The User to check
     * @return totalCollateralValueInUsd The user's total collateral value in USD,
     *  gotten by AggregtorV3Interface of the token's priceFeed
     */
    function getAccountCollateralValueInUsd(address user) public view returns (uint256 totalCollateralValueInUsd) {
      // Loop through all the collateral token, get the amount they have deposited,  and map it to price to get the USD value
      for (uint256 i = 0; i < sCollateralTokens.length; i++) {
        address token = sCollateralTokens[i];
        uint256 amount = sCollateralDeposited[user][token];
        totalCollateralValueInUsd += getUsdValue(token, amount);
      }
      return totalCollateralValueInUsd;
    }

    function getUsdValue(address token, uint256 amount) public view returns (uint256) {
      AggregatorV3Interface priceFeed = AggregatorV3Interface(sPriceFeeds[token]);
      (,int256 price,,,) = priceFeed.latestRoundData();
      // if 1 ETH = $1000, then the returned value from CL will be 1000 * 1e8 (decimal places of the priceFeed address)
  
      return ((uint256(price) * ADDITIONAL_FEED_PRECISION) * amount) / PRECISION;
    }
}