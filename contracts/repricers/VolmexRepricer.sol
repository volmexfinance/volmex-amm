// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import '@openzeppelin/contracts/math/SafeMath.sol';
import '@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/introspection/ERC165Upgradeable.sol';

import '../interfaces/IVolmexOracle.sol';
import '../interfaces/IVolmexProtocol.sol';
import '../maths/NumExtra.sol';

/**
 * @title Volmex Repricer contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexRepricer is ERC165Upgradeable, NumExtra {
    using SafeMath for uint256;

    // Instance of oracle contract
    IVolmexOracle public oracle;
    // Instance of protocol contract
    IVolmexProtocol public protocol;

    // Has the value of volatility cap ratio of protocol { 250 }
    uint256 public protocolVolatilityCapRatio;

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

        protocolVolatilityCapRatio = protocol.volatilityCapRatio().mul(VOLATILITY_PRICE_PRECISION);
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
        estPrimaryPrice = oracle.volatilityTokenPriceByIndex(_volatilityIndex);

        estComplementPrice = protocolVolatilityCapRatio.sub(estPrimaryPrice);

        estPrice = estPrimaryPrice.mul(BONE).div(estComplementPrice);
    }

    /**
     * @notice Used to calculate the square root of the provided value
     *
     * @param x Value of which the square root will be calculated
     */
    function sqrtWrapped(int256 x) external pure returns (int256) {
        return sqrt(x); // TODO: Need to understand the sqrt method from abdk-libraries
    }
}
