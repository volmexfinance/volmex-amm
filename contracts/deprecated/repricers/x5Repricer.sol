// "SPDX-License-Identifier: GNU General Public License v3.0"

pragma solidity 0.7.6;

import '@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol';
import '@openzeppelin/contracts/math/SafeMath.sol';
import './IRepricer.sol';
import '../../Const.sol';
import '../../Num.sol';
import '../../NumExtra.sol';

contract x5Repricer is IRepricer, Const, Num, NumExtra {
    int256 public constant NEGATIVE_INFINITY = type(int256).min;

    function isRepricer() external pure override returns (bool) {
        return true;
    }

    function symbol() external pure override returns (string memory) {
        return 'x5Repricer';
    }

    function reprice(
        IVault _vault,
        uint256 _pMin,
        int256 _repricerParam1,
        int256 _repricerParam2
    )
        external
        view
        override
        returns (
            int256 estPricePrimary,
            int256 estPriceComplement,
            uint256 estPrice,
            uint256 upperBoundary
        )
    {
        require(address(_vault) != address(0), 'Zero vault');

        upperBoundary = calcDenomination(_vault) * BONE;

        (estPricePrimary, estPriceComplement) = calcEstPrices(
            calcEstPricePrimary(
                calcUnv(_vault.underlyingStarts(0), getCurrentUnderlingValue(_vault)),
                calcTtm(_vault.settleTime()),
                _repricerParam1,
                _repricerParam2
            ),
            int256(upperBoundary),
            int256(_pMin)
        );
        estPrice = uint256((estPriceComplement * iBONE) / estPricePrimary);
    }

    function getCurrentUnderlingValue(IVault _vault)
        internal
        view
        returns (int256 currentUnderlingValue)
    {
        uint256 currentTimestamp;
        (, currentUnderlingValue, , currentTimestamp, ) = AggregatorV3Interface(_vault.oracles(0))
            .latestRoundData();
        require(currentTimestamp > 0, 'EMPTY_ORACLE_LATEST_ROUND');
    }

    function calcTtm(uint256 _settledTimestamp) internal view returns (int256) {
        return ((int256(_settledTimestamp) - int256(block.timestamp)) * iBONE) / 31536000; // 365 * 24 * 3600
    }

    function calcUnv(int256 _liveUnderlingValue, int256 _currentUnderlingValue)
        internal
        pure
        returns (int256)
    {
        return
            5 *
            iBONE +
            5 *
            (((_currentUnderlingValue - _liveUnderlingValue) * iBONE) / _liveUnderlingValue);
    }

    function calcDenomination(IVault _vault) internal view returns (uint256 denomination) {
        denomination =
            _vault.derivativeSpecification().primaryNominalValue() +
            _vault.derivativeSpecification().complementNominalValue();
    }

    function calcEstPricePrimary(
        int256 _spotPrice,
        int256 _ttm,
        int256 _volatilityOption4,
        int256 _volatilityOption6
    ) internal pure returns (int256) {
        int256 ttmSqrt = sqrt(_ttm);
        int256 option4 = calcOption(_spotPrice, _volatilityOption4, ttmSqrt, _ttm, 4);
        int256 option6 = calcOption(_spotPrice, _volatilityOption6, ttmSqrt, _ttm, 6);
        return option4 - option6;
    }

    function calcOption(
        int256 _spotPrice,
        int256 _volatility,
        int256 _ttmSqrt,
        int256 _ttm,
        int256 _strike
    ) internal pure returns (int256) {
        int256 volatilityBySqrtTtm = (_volatility * _ttmSqrt) / iBONE;
        int256 volatilityByTtm = ((_volatility * _volatility) * _ttm) / (iBONE * iBONE * 2);

        int256 d =
            (((iBONE * iBONE) / volatilityBySqrtTtm) *
                (ln(_spotPrice / _strike) + volatilityByTtm)) / iBONE;
        return (ncdf(d) * _spotPrice) / iBONE - ncdf(d - volatilityBySqrtTtm) * _strike;
    }

    function calcEstPrices(
        int256 _estPricePrimary,
        int256 _upperBoundary,
        int256 _lowerBoundary
    ) internal pure returns (int256 estPricePrimary, int256 estPriceComplement) {
        estPricePrimary = _estPricePrimary;

        if (estPricePrimary < _lowerBoundary) {
            estPricePrimary = _lowerBoundary;
        }

        if (estPricePrimary > _upperBoundary - _lowerBoundary) {
            estPricePrimary = _upperBoundary - _lowerBoundary;
        }

        estPriceComplement = _upperBoundary - estPricePrimary;
    }

    function sqrtWrapped(int256 x) external pure override returns (int256) {
        return sqrt(x);
    }
}
