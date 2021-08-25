// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../oracles/IVolmexOracle.sol";

contract VolmexRepricer {
    using SafeMath for uint256;

    event UpdatedLeverageCoefficient(uint256 leverageCoefficient);

    event Repriced(
        uint256 collateralReserve,
        uint256 volatilityReserve,
        uint256 spotPrice
    );

    uint256 public leverageCoefficient;

    IVolmexOracle public oracle;

    constructor(uint256 _leverageCoefficient, IVolmexOracle _oracle) {
        leverageCoefficient = _leverageCoefficient;
        oracle = _oracle;
    }

    function reprice(
        uint256 _collateralReserve,
        uint256 _volatilityReserve,
        uint256 _tradeAmount,
        string calldata _volatilitySymbol
    ) external returns (uint256 spotPrice) {
        require(
            _collateralReserve > 0 && _volatilityReserve > 0,
            "Repricer: reserve should be greater than 0"
        );

        _updateLeverageCoefficient(
            _collateralReserve,
            _volatilityReserve,
            _volatilitySymbol
        );

        spotPrice = (_collateralReserve.add(_tradeAmount)).div(
            leverageCoefficient.mul(_volatilityReserve)
        );

        emit Repriced(
            _collateralReserve,
            _volatilityReserve,
            spotPrice
        );
    }

    function _updateLeverageCoefficient(
        uint256 _collateralReserve,
        uint256 _volatilityReserve,
        string memory _volatilitySymbol
    ) internal {
        uint256 volatilityPrice = oracle.volatilityTokenPrice(
            _volatilitySymbol
        );

        leverageCoefficient = _collateralReserve.div(
            volatilityPrice.mul(_volatilityReserve)
        );

        emit UpdatedLeverageCoefficient(leverageCoefficient);
    }
}
