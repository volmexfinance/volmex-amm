// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165CheckerUpgradeable.sol';
import '../interfaces/IVolmexOracle.sol';
import '../interfaces/IVolmexRepricer.sol';
import '../maths/NumExtra.sol';

/**
 * @title Volmex Repricer contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexRepricer is ERC165StorageUpgradeable, NumExtra {
    // Instance of oracle contract
    IVolmexOracle public oracle;

    /**
     * @notice Initializes the contract, setting the required state variables
     * @param _oracle Address of the Volmex Oracle contract
     */
    function initialize(IVolmexOracle _oracle) external initializer {
        require(
            AddressUpgradeable.isContract(address(_oracle)),
            'Repricer: Not an oracle contract'
        );
        oracle = _oracle;
        __ERC165Storage_init_unchained();
        _registerInterface(type(IVolmexRepricer).interfaceId);
        require(
            ERC165CheckerUpgradeable.supportsInterface(address(_oracle), type(IVolmexOracle).interfaceId),
            'VolmexController: Oracle does not supports interface'
        );
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
        (estPrimaryPrice, estComplementPrice) = oracle.getVolatilityTokenPriceByIndex(
            _volatilityIndex
        );
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
