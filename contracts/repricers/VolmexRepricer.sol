// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165Upgradeable.sol';

import '../interfaces/IVolmexOracle.sol';
import '../interfaces/IVolmexProtocol.sol';
import '../maths/NumExtra.sol';

/**
 * @title Volmex Repricer contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexRepricer is ERC165Upgradeable, NumExtra {
    // Instance of oracle contract
    IVolmexOracle public oracle;
    // Instance of protocol contract
    IVolmexProtocol public protocol;

    /**
     * @notice Initializes the contract, setting the required state variables
     *
     * @param _oracle Address of the Volmex Oracle contract
     * @param _protocol Address of the Volmex Protocol contract
     */
    function initialize(IVolmexOracle _oracle, IVolmexProtocol _protocol) external initializer {
        require(AddressUpgradeable.isContract(address(_oracle)), 'Repricer: Not an oracle contract');
        oracle = _oracle;

        require(AddressUpgradeable.isContract(address(_protocol)), 'Repricer: Not a protocol contract');
        protocol = _protocol;

        __ERC165_init();
    }

    /**
     * @notice Fetches the price of asset from oracle
     *
     * @dev Calculates the price of complement asset. { volatility cap ratio - primary asset price }
     *
     * @param _volatilityIndex Number value of the volatility index. { eg. 0 }
     */
    function reprice(uint256 _volatilityIndex)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        )
    {   
        (estPrimaryPrice, estComplementPrice) = oracle.getVolatilityTokenPriceByIndex(_volatilityIndex);
        estPrice = (estComplementPrice * BONE) / estPrimaryPrice;
    }

    /**
     * @notice Used to calculate the square root of the provided value
     *
     * @param x Value of which the square root will be calculated
     */
    function sqrtWrapped(int256 x) external pure returns (int256) {
        return sqrt(x);
    }
}
