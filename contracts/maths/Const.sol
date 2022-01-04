// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

contract Const {
    uint256 public constant BONE = 10**18;
    int256 public constant iBONE = int256(BONE);

    uint256 public constant MIN_POW_BASE = 1 wei;
    uint256 public constant MAX_POW_BASE = (2 * BONE) - 1 wei;
    uint256 public constant POW_PRECISION = BONE / 10**10;

    uint256 public constant MAX_IN_RATIO = BONE / 2;

    uint256 public constant VOLATILITY_PRICE_PRECISION = 10**6;
}
