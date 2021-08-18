// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../oracles/IVolmexOracle.sol";

contract Repricer {
    using SafeMath for uint256;

    event UpdatedLeverageCoefficient(uint256 leverageCoefficient);

    uint256 public leverageCoefficient;

    IVolmexOracle public oracle;

    constructor(uint256 _leverageCoefficient, address _oracle) {
        leverageCoefficient = _leverageCoefficient;
        oracle = IVolmexOracle(_oracle);
    }

    function reprice(
        uint256 _collateralReserve,
        uint256 _volatilityReserve,
        uint256 _tradeAmount,
        string calldata _volatilitySymbol
    )
        external
        returns (
            uint256 spotPrice,
            uint256 averagePrice,
            uint256 volatilityPrice
        )
    {
        require(
            _collateralReserve > 0 && _volatilityReserve > 0,
            "Repricer: reserve should be greater than 0"
        );
        spotPrice = _collateralReserve.div(
            leverageCoefficient.mul(_volatilityReserve)
        );
        averagePrice = (_collateralReserve.add(_tradeAmount)).div(
            leverageCoefficient.mul(_volatilityReserve)
        );

        oracle.updateVolatilityTokenPrice(
            _volatilitySymbol,
            spotPrice
        );

        volatilityPrice = oracle.volatilityTokenPrice(
            _volatilitySymbol
        );

        _updateLeverageCoefficient(_volatilityReserve, _tradeAmount);
    }

    function _updateLeverageCoefficient(
        uint256 _volatilityReserve,
        uint256 _tradeAmount
    ) internal {
        uint256 numerator = (
            leverageCoefficient.mul(_volatilityReserve)
        ).add(_tradeAmount);
        uint256 denominator = _volatilityReserve.add(_tradeAmount);

        leverageCoefficient = numerator.div(denominator);

        emit UpdatedLeverageCoefficient(leverageCoefficient);
    }
}
