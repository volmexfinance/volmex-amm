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
        uint256 indexed volatilityIndex
    );

    // Store the price of volatility by indexes { 0 - ETHV, 1 = BTCV }
    mapping(uint256 => uint256) public volatilityTokenPriceByIndex;

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
        volatilityTokenPriceByIndex[
            0
        ] = 125 * 10**4;

        volatilityTokenPriceByIndex[
            1
        ] = 125 * 10**4;
    }

    /**
     * @notice Updates the volatility token price
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     *
     * @param _volatilityIndex Number value of the volatility index. { eg. 0 }
     * @param _volatilityTokenPrice Price of volatility token, between {0, 250}
     */
    function updateVolatilityTokenPrice(
        uint256 _volatilityIndex,
        uint256 _volatilityTokenPrice
    ) external onlyOwner {
        require(
            _volatilityTokenPrice > 0 && _volatilityTokenPrice < 250,
            "VolmexOracle: _volatilityTokenPrice should be greater than 0"
        );

        volatilityTokenPriceByIndex[
            _volatilityIndex
        ] = _volatilityTokenPrice * 10**4;

        emit VolatilityTokenPriceUpdated(
            _volatilityTokenPrice,
            _volatilityIndex
        );
    }
}
