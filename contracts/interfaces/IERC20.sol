// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address _whom) external view returns (uint256);
    function allowance(address _src, address _dst) external view returns (uint256);
    function approve(address _dst, uint256 _amt) external returns (bool);
    function transfer(address _dst, uint256 _amt) external returns (bool);
    function transferFrom(
        address _src,
        address _dst,
        uint256 _amt
    ) external returns (bool);
}
