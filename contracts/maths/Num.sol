// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.
// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import './Const.sol';

contract Num is Const {
    function _subSign(uint256 _a, uint256 _b) internal pure returns (uint256, bool) {
        if (_a >= _b) {
            return (_a - _b, false);
        } else {
            return (_b - _a, true);
        }
    }

    function _mul(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
        uint256 c0 = _a * _b;
        uint256 c1 = c0 + (BONE / 2);
        c = c1 / BONE;
    }

    function _div(uint256 _a, uint256 _b) internal pure returns (uint256 c) {
        require(_b != 0, 'DIV_ZERO');
        uint256 c0 = _a * BONE;
        uint256 c1 = c0 + (_b / 2);
        c = c1 / _b;
    }

    function _min(uint256 _first, uint256 _second) internal pure returns (uint256) {
        if (_first < _second) {
            return _first;
        }
        return _second;
    }
}
