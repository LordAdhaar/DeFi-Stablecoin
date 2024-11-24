// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title DSCEngine
/// @author Adhaar Jain
/// @notice Engine for DSC
/// - Make sure 1 token == 1 USD
/// - Algorithmic minting and burning
/// - Borrowing using ETH and BTC as collateral

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

error DSCEngine__InvalidAmount();
error DSCEngine__TokenNotAcceptedAsCollateral(address tokenAddress);
error DSCEngine__TokenAndPricfeedArrayLengthDifferent();
error DSCEngine_CollateralDepositFailed(address tokenAddress, uint256 tokenAmount);
error DSCEngine__MintFailed(address user, uint256 amount);
error DSCEngine__UserHealthFactorBelowMinimum(address user, uint256 userHealthFactor);

interface IDSCEngine {
    function depositCollateralAndMintDSC() external;

    function depositCollateral() external;

    function withdrawCollateralAndDepositDSC() external;

    function redeemCollateral() external;

    function mintDSC() external;

    function burnDSC() external;

    function liquidate() external;

    function getHealthFactor() external view;
}

contract DSCEngine is ReentrancyGuard {
    //Token address to pricefeed
    mapping(address tokenAddress => address tokenPricefeed) private s_priceFeeds;

    // User to token address to token amount
    mapping(address user => mapping(address tokenAddress => uint256 tokenAmount)) private s_userToCollateralAmount;

    // user to dsc minted
    mapping(address user => uint256 amountOfDSCMinted) private s_userToDSCMinted;

    // DecentralizedStableCoin type
    DecentralizedStableCoin private immutable i_decentralizedStableCoin;

    // list of all collateral tokens
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant HEALTH_FACTOR = 1e18;

    event CollateralDeposited(address userAddress, address tokenAddress, uint256 tokenAmount);

    constructor(address[] memory tokenAddresses, address[] memory priceFeedAddresses, address DSCAddress) {
        uint256 tokenAddressesLength = tokenAddresses.length;
        uint256 priceFeedAddressesLength = priceFeedAddresses.length;

        if (tokenAddressesLength != priceFeedAddressesLength) {
            revert DSCEngine__TokenAndPricfeedArrayLengthDifferent();
        }

        for (uint256 i = 0; i < tokenAddressesLength; i += 1) {
            s_priceFeeds[tokenAddresses[i]] = priceFeedAddresses[i];
            s_collateralTokens.push(tokenAddresses[i]);
        }

        i_decentralizedStableCoin = DecentralizedStableCoin(DSCAddress);
    }

    modifier isValidAmount(uint256 amount) {
        if (amount <= 0) {
            revert DSCEngine__InvalidAmount();
        }
        _;
    }

    modifier isAcceptedAsCollateral(address tokenAddress) {
        if (s_priceFeeds[tokenAddress] == address(0)) {
            revert DSCEngine__TokenNotAcceptedAsCollateral(tokenAddress);
        }
        _;
    }

    function depositCollateral(address tokenAddress, uint256 tokenAmount)
        public
        isValidAmount(tokenAmount)
        isAcceptedAsCollateral(tokenAddress)
        nonReentrant
    {
        s_userToCollateralAmount[msg.sender][tokenAddress] += tokenAmount;

        emit CollateralDeposited(msg.sender, tokenAddress, tokenAmount);

        bool success = IERC20(tokenAddress).transferFrom(msg.sender, address(this), tokenAmount);

        if (!success) {
            revert DSCEngine_CollateralDepositFailed(tokenAddress, tokenAmount);
        }
    }

    function mintDSC(uint256 amount) public isValidAmount(amount) nonReentrant {
        s_userToDSCMinted[msg.sender] += amount;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_decentralizedStableCoin.mint(msg.sender, amount);

        if (!minted) {
            revert DSCEngine__MintFailed(msg.sender, amount);
        }
    }

    function _healthFactor(address user) private view returns (uint256) {
        // DSC minted for user
        // user collateral value in USD
        (uint256 amountMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        uint256 amountCanMint = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        uint256 healthFactor = (amountCanMint * PRECISION) / amountMinted;

        return healthFactor;
    }

    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        uint256 amountMinted = s_userToDSCMinted[user];
        uint256 collateralValueInUSD = getAccountCollateralValue(user);
        return (amountMinted, collateralValueInUSD);
    }

    function getAccountCollateralValue(address user) public view returns (uint256) {
        uint256 s_collateralTokensLength = s_collateralTokens.length;
        uint256 totalCollateralValueInUSD;

        for (uint256 i = 0; i < s_collateralTokensLength; i += 1) {
            address tokenAddress = s_collateralTokens[i];
            uint256 tokenAmount = s_userToCollateralAmount[user][tokenAddress];
            totalCollateralValueInUSD += getUSDValueOfCollateral(tokenAddress, tokenAmount);
        }

        return totalCollateralValueInUSD;
    }

    function getUSDValueOfCollateral(address tokenAddress, uint256 tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.latestRoundData();

        return (uint256(price) * ADDITIONAL_FEED_PRECISION * tokenAmount) / PRECISION;
    }

    function _revertIfHealthFactorIsBroken(address user) internal view {
        // Do they have enough collateral
        // revert if Dont
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < HEALTH_FACTOR) {
            revert DSCEngine__UserHealthFactorBelowMinimum(user, userHealthFactor);
        }
    }

    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    function getUserToCollateralTokenAmount(address user, address tokenAddress) public view returns (uint256) {
        return s_userToCollateralAmount[user][tokenAddress];
    }
}
