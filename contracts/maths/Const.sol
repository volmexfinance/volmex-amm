// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

contract Const {
    uint256 public constant BONE = 10**18;

    int256 public constant iBONE = int256(BONE);

    uint256 public constant MAX_IN_RATIO = BONE / 2;
}

