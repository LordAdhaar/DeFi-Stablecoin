// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

/// @title DSCEngine
/// @notice Engine for DSC
/// @dev Make sure 1 token == 1 USD
/// @dev Algorithmic minting and burning
/// @dev Borrowing using ETH and BTC as collateral

import {DecentralizedStableCoin} from "./DecentralizedStableCoin.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import {console} from "../lib/forge-std/src/console.sol";
import {OracleLib} from "./library/OracleLib.sol";

interface IDSCEngine {
    function depositCollateralAndMintDSC() external;

    function depositCollateral() external;

    function redeemCollateralForDSC() external;

    function redeemCollateral() external;

    function mintDSC() external;

    function burnDSC() external;

    function liquidate() external;

    function getHealthFactor() external view;
}

contract DSCEngine is ReentrancyGuard {
    // Mapping from token address to its corresponding price feed address
    mapping(address => address) private s_priceFeeds;

    // Mapping from user address to another mapping of token address to the amount of that token deposited as collateral
    mapping(address => mapping(address => uint256)) private s_userToCollateralAmount;

    // Mapping from user address to the amount of DSC minted by that user
    mapping(address => uint256) private s_userToDSCMinted;

    // Instance of the DecentralizedStableCoin contract
    DecentralizedStableCoin private immutable i_decentralizedStableCoin;

    // List of all accepted collateral token addresses
    address[] private s_collateralTokens;

    uint256 private constant ADDITIONAL_FEED_PRECISION = 1e10;
    uint256 private constant PRECISION = 1e18;

    uint256 private constant LIQUIDATION_BONUS = 10;
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;

    uint256 private constant HEALTH_FACTOR = 1e18;

    ////////////////
    //   Error   //
    ////////////////

    error DSCEngine__HealthFactorNotImproved();
    error DSCEngine__InvalidAmount();
    error DSCEngine__TokenNotAcceptedAsCollateral(address tokenAddress);
    error DSCEngine__TokenAndPricfeedArrayLengthDifferent();
    error DSCEngine_CollateralDepositFailed(address tokenAddress, uint256 tokenAmount);
    error DSCEngine__MintFailed(address user, uint256 amount);
    error DSCEngine__UserHealthFactorBelowMinimum(address user, uint256 userHealthFactor);
    error DSCEngine__HealthFactorOk(address user, uint256 userHealthFactor);
    error DSCEngine_CollateralRedeemFailed(address user, address tokenAddress, uint256 tokenAmount);
    error DSCEngine_DSCBurnFailed(address burnFrom, address transferTo, uint256 amount);

    ////////////////
    //   Type   //
    ////////////////
    using OracleLib for AggregatorV3Interface;

    ////////////////
    //   Events   //
    ////////////////

    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(
        address indexed redeemedFrom, address indexed redeemedTo, address indexed token, uint256 amount
    );

    /// @notice Constructor for DSCEngine
    /// @param tokenAddresses The addresses of the tokens accepted as collateral
    /// @param priceFeedAddresses The addresses of the price feeds for the collateral tokens
    /// @param DSCAddress The address of the DecentralizedStableCoin contract
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

    /// @notice Deposits collateral and mints DSC
    /// @param tokenAddress The address of the token to be deposited as collateral
    /// @param tokenAmount The amount of the token to be deposited as collateral
    /// @param amountDSCToMint The amount of DSC to mint
    function depositCollateralAndMintDSC(address tokenAddress, uint256 tokenAmount, uint256 amountDSCToMint) external {
        depositCollateral(tokenAddress, tokenAmount);
        mintDSC(amountDSCToMint);
    }

    /// @notice Deposits collateral
    /// @param tokenAddress The address of the token to be deposited as collateral
    /// @param tokenAmount The amount of the token to be deposited as collateral
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

    function redeemCollateralForDSC(address collateralAddress, uint256 collateralAmount, uint256 amountDSC) public {
        _burnDSC(msg.sender, msg.sender, amountDSC);
        _redeemCollateral(collateralAddress, collateralAmount, msg.sender, msg.sender);
    }

    function redeemCollateral(address tokenAddress, uint256 tokenAmount)
        public
        isValidAmount(tokenAmount)
        nonReentrant
    {
        _redeemCollateral(tokenAddress, tokenAmount, msg.sender, msg.sender);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /**
     * @notice Liquidates an insolvent user by burning DSC and seizing their collateral.
     * @param collateralTokenAddress The ERC20 token address of the collateral to seize from the insolvent user.
     * @param userBeingLiquidated The address of the user who is insolvent and has a health factor below the minimum.
     * @param DSCDebtCoveredByLiquidator The amount of DSC the liquidator wants to burn to cover the user's debt.
     * @dev The liquidator will receive a 10% liquidation bonus for seizing the user's collateral.
     * @dev Partial liquidation is allowed.
     * @dev Assumes the protocol is roughly 150% overcollateralized for proper functioning.
     * @dev A known issue is if the protocol is only 100% collateralized, liquidation may not be possible.
     * For example, if the collateral price drops significantly before liquidation can occur.
     */
    function liquidate(address collateralTokenAddress, address userBeingLiquidated, uint256 DSCDebtCoveredByLiquidator)
        external
        isValidAmount(DSCDebtCoveredByLiquidator)
        nonReentrant
    {
        uint256 startingUserHealthFactor = _healthFactor(userBeingLiquidated);

        if (startingUserHealthFactor >= HEALTH_FACTOR) {
            revert DSCEngine__HealthFactorOk(userBeingLiquidated, startingUserHealthFactor);
        }

        //Figure out how much eth to be give to liquidator for dsc debt covered by him
        uint256 collateralAmountFromDebtCovered =
            getCollateralAmountFromDebtCovered(collateralTokenAddress, DSCDebtCoveredByLiquidator);

        uint256 bonusCollateral = (collateralAmountFromDebtCovered * LIQUIDATION_BONUS) / LIQUIDATION_PRECISION;

        uint256 totalCollateralForLiquidator = collateralAmountFromDebtCovered + bonusCollateral;
        // give 10 percent bonus to liquidator
        // Example
        // $200 weth initial collateral
        // $100 DSC as debt
        // weth collateral falls to $150
        // Other user liquidates the inital user account
        // Deposits $100 USD to get $110 of weth (including bonus)
        // Remaing $40 weth stays with DSCEngine????
        _redeemCollateral(collateralTokenAddress, totalCollateralForLiquidator, userBeingLiquidated, msg.sender);
        _burnDSC(userBeingLiquidated, msg.sender, DSCDebtCoveredByLiquidator);

        uint256 endingUserHealthFactor = _healthFactor(userBeingLiquidated);

        if (endingUserHealthFactor <= startingUserHealthFactor) {
            revert DSCEngine__HealthFactorNotImproved();
        }

        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Mints DSC
    /// @param amount The amount of DSC to mintDSC(amount);
    // DSC minted directly to msg.sender
    function mintDSC(uint256 amount) public isValidAmount(amount) nonReentrant {
        s_userToDSCMinted[msg.sender] += amount;

        _revertIfHealthFactorIsBroken(msg.sender);

        bool minted = i_decentralizedStableCoin.mint(msg.sender, amount);

        if (!minted) {
            revert DSCEngine__MintFailed(msg.sender, amount);
        }
    }

    function burnDSC(uint256 amount) public isValidAmount(amount) {
        _burnDSC(msg.sender, msg.sender, amount);
        _revertIfHealthFactorIsBroken(msg.sender);
    }

    /// @notice Gets the collateral value of a user in USD
    /// @param user The address of the user
    /// @return The collateral value of the user in USD
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

    /// @notice Gets the USD value of a collateral token
    /// @param tokenAddress The address of the token
    /// @param tokenAmount The amount of the token
    /// @return The USD value of the collateral token
    function getUSDValueOfCollateral(address tokenAddress, uint256 tokenAmount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (uint256(price) * ADDITIONAL_FEED_PRECISION * tokenAmount) / PRECISION;
    }

    /// @notice Gets the precision constant
    /// @return The precision constant
    function getPrecision() public pure returns (uint256) {
        return PRECISION;
    }

    /**
     * @notice Retrieves the account information for a given user.
     * @dev This function is a public wrapper for the internal _getAccountInformation function.
     * @param user The address of the user whose account information is being requested.
     * @return A tuple containing two uint256 values:
     *         - The first value represents the user's collateral balance.
     *         - The second value represents the user's debt balance.
     */
    //create a public version of the getAccountInformation function
    function getAccountInformation(address user) public view returns (uint256, uint256) {
        return _getAccountInformation(user);
    }

    /// @notice Gets the collateral token amount of a user
    /// @param user The address of the user
    /// @param tokenAddress The address of the token
    /// @return The collateral token amount of the user
    function getUserToCollateralTokenAmount(address user, address tokenAddress) public view returns (uint256) {
        return s_userToCollateralAmount[user][tokenAddress];
    }

    function getUserToDSCBalance(address user) public view returns (uint256) {
        return s_userToDSCMinted[user];
    }

    function getCollateralAmountFromDebtCovered(address tokenAddress, uint256 amount) public view returns (uint256) {
        AggregatorV3Interface priceFeed = AggregatorV3Interface(s_priceFeeds[tokenAddress]);
        (, int256 price,,,) = priceFeed.staleCheckLatestRoundData();

        return (amount * PRECISION) / (uint256(price) * ADDITIONAL_FEED_PRECISION);
    }

    /// @notice Gets the account information of a user
    /// @param user The address of the user
    /// @return The amount of DSC minted and the collateral value in USD
    function _getAccountInformation(address user) private view returns (uint256, uint256) {
        uint256 amountMinted = s_userToDSCMinted[user];
        uint256 collateralValueInUSD = getAccountCollateralValue(user);
        return (amountMinted, collateralValueInUSD);
    }

    /// @notice Calculates the health factor of a user
    /// @param user The address of the user
    /// @return The health factor of the user
    function _healthFactor(address user) private view returns (uint256) {
        (uint256 amountMinted, uint256 collateralValueInUSD) = _getAccountInformation(user);

        if (amountMinted == 0) {
            return type(uint256).max;
        }

        console.log("amountMinted: ", amountMinted);

        uint256 amountCanMint = (collateralValueInUSD * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;

        console.log("amountCanMint: ", amountCanMint);

        uint256 healthFactor = (amountCanMint * PRECISION) / amountMinted;

        return healthFactor;
    }

    /// @notice Reverts if the health factor of a user is below the minimum
    /// @param user The address of the user
    function _revertIfHealthFactorIsBroken(address user) internal view {
        uint256 userHealthFactor = _healthFactor(user);
        if (userHealthFactor < HEALTH_FACTOR) {
            revert DSCEngine__UserHealthFactorBelowMinimum(user, userHealthFactor);
        }
    }

    function _redeemCollateral(address tokenAddress, uint256 tokenAmount, address from, address to) private {
        s_userToCollateralAmount[from][tokenAddress] -= tokenAmount;
        console.log("userCollateralBalance", s_userToCollateralAmount[from][tokenAddress]);
        emit CollateralRedeemed(from, to, tokenAddress, tokenAmount);

        bool success = IERC20(tokenAddress).transfer(to, tokenAmount);

        if (!success) {
            revert DSCEngine_CollateralRedeemFailed(to, tokenAddress, tokenAmount);
        }
    }

    function _burnDSC(address burnFrom, address transferTo, uint256 amount) private {
        s_userToDSCMinted[burnFrom] -= amount;

        bool success = i_decentralizedStableCoin.transferFrom(transferTo, address(this), amount);

        if (!success) {
            revert DSCEngine_DSCBurnFailed(burnFrom, transferTo, amount);
        }

        i_decentralizedStableCoin.burn(amount);
    }

    function getTokensAcceptedAsCollateral() public view returns (address[] memory) {
        return s_collateralTokens;
    }

    function getCollateralPriceFeed(address collateralAddress) public view returns (address) {
        return s_priceFeeds[collateralAddress];
    }
}
