// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

import "../oracles/IVolmexOracle.sol";

contract Repricer {
    using SafeMath for uint256;

    event UpdatedLeverageCoefficient(
        uint256 leverageCoefficient
    );

    uint256 public leverageCoefficient;

    IVolmexOracle public oracle;

    constructor(
        uint256 _leverageCoefficient,
        address _oracle
    ) {
        leverageCoefficient = _leverageCoefficient;
        oracle = IVolmexOracle(_oracle);
    }
}
