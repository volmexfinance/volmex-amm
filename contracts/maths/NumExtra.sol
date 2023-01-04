// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "abdk-libraries-solidity/ABDKMathQuad.sol";
import "./Const.sol";

contract NumExtra is Const {
    function sqrt(int256 _x) public pure returns (int256) {
        return toIntMultiplied(ABDKMathQuad.sqrt(fromIntMultiplied(_x, BONE)), BONE);
    }

    function toIntMultiplied(bytes16 _value, uint256 _bone) internal pure returns (int256) {
        return ABDKMathQuad.toInt(ABDKMathQuad.mul(_value, ABDKMathQuad.fromUInt(_bone)));
    }

    function fromIntMultiplied(int256 _value, uint256 _bone) internal pure returns (bytes16) {
        return ABDKMathQuad.div(ABDKMathQuad.fromInt(_value), ABDKMathQuad.fromUInt(_bone));
    }
}
