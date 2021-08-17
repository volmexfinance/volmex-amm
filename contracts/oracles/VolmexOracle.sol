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
        string volatilityTokenSymbol
    );

    // Store the price of volatility of ETHV and BTCV
    mapping(string => uint256) public volatilityTokenPrice;

    /**
     * @notice Initializes the contract setting the deployer as the initial owner.
     */
    function initialize() external initializer {
        __Ownable_init();
    }

    /**
     * @notice Updates the volatility token price
     *
     * @dev Check if volatility token price is greater than zero (0)
     * @dev Update the volatility token price corresponding to the volatility token symbol
     * @dev Store the volatility token price corresponding to the block number
     */
    function updateVolatilityTokenPrice(string calldata _volatilityTokenSymbol, uint256 _volatilityTokenPrice) external onlyOwner {
        require(_volatilityTokenPrice > 0 && _volatilityTokenPrice < 250, "VolmexOracle: _volatilityTokenPrice should be greater than 0");

        volatilityTokenPrice[_volatilityTokenSymbol] = _volatilityTokenPrice;

        emit VolatilityTokenPriceUpdated(
            _volatilityTokenPrice,
            _volatilityTokenSymbol
        );
    }
}
