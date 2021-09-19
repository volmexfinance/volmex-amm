// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/**
 * @title Volmex Oracle contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexOracle is OwnableUpgradeable {
    event VolatilityTokenPriceUpdated(
        uint256 volatilityTokenPrice,
        string volatilityTokenSymbol,
        uint256 indexed priceIndex
    );

    // Store the price of volatility of ETHV and BTCV
    mapping(string => uint256) public volatilityTokenPrice;

    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) public volatilityTokenPriceByIndex;

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
        volatilityTokenPrice[
            "ETHV"
        ] = 125 * 10**4;

        volatilityTokenPrice[
            "BTCV"
        ] = 125 * 10**4;
    }

    /**
     * @notice Updates the volatility token price
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     *
     * @param _volatilityTokenSymbol String value of the volatility symbol. { eg. ETHV }
     * @param _volatilityTokenPrice Price of volatility token, between {0, 250}
     */
    function updateVolatilityTokenPrice(
        string calldata _volatilityTokenSymbol,
        uint256 _priceIndex,
        uint256 _volatilityTokenPrice
    ) external onlyOwner {
        require(
            _volatilityTokenPrice > 0 && _volatilityTokenPrice < 250,
            "VolmexOracle: _volatilityTokenPrice should be greater than 0"
        );

        volatilityTokenPrice[
            _volatilityTokenSymbol
        ] = _volatilityTokenPrice * 10**4;

        volatilityTokenPriceByIndex[
            _priceIndex
        ] = _volatilityTokenPrice * 10**4;

        emit VolatilityTokenPriceUpdated(
            _volatilityTokenPrice,
            _volatilityTokenSymbol,
            _priceIndex
        );
    }
}
