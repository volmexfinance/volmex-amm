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

pragma solidity =0.8.10;
pragma abicoder v2;

interface IDynamicFee {
    function calc(
        int256[3] calldata _inRecord,
        int256[3] calldata _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _maxFee
    ) external returns (int256 fee, int256 expStart);
}
