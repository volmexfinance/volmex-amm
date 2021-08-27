// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../oracles/IVolmexOracle.sol";
import "../interfaces/IVolmexProtocol.sol";
import "../NumExtra.sol";

contract VolmexRepricer is NumExtra {
    using SafeMath for uint256;

    IVolmexOracle public oracle;
    IVolmexProtocol public protocol;

    uint256 public protocolVolatilityCapRatio;

    constructor(IVolmexOracle _oracle, IVolmexProtocol _protocol) {
        protocol = _protocol;
        oracle = _oracle;

        protocolVolatilityCapRatio = protocol.volatilityCapRatio();
    }

    function reprice(string calldata _volatilitySymbol)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        )
    {
        estPrimaryPrice = oracle.volatilityTokenPrice(
            _volatilitySymbol
        );

        uint256 estPrimaryPriceWithoutPrecision = estPrimaryPrice.div(
            VOLATILITY_PRICE_PRECISION
        );
        estComplementPrice = (
            protocolVolatilityCapRatio.sub(
                estPrimaryPriceWithoutPrecision
            )
        ).mul(VOLATILITY_PRICE_PRECISION);

        estPrice = (estPrimaryPrice.mul(BONE)).div(
            estComplementPrice
        );
    }

    function sqrtWrapped(int256 x) external pure returns (int256) {
        return sqrt(x); // Need to understand the sqrt method from abdk-libraries
    }
}
