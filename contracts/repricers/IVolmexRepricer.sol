// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

interface IVolmexRepricer {
    function leverageCoefficient() external view returns (uint256);

    function reprice(string calldata _volatilitySymbol)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice,
            uint256 upperBoundary
        );

    function sqrtWrapped(int256 value) external pure returns (int256);
}
