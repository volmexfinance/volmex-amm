// "SPDX-License-Identifier: GNU General Public License v3.0"

pragma solidity 0.7.6;

import '../libs/complifi/IVault.sol';

interface IRepricer {
    function isRepricer() external pure returns (bool);

    function symbol() external pure returns (string memory);

    function reprice(
        IVault _vault,
        uint256 _pMin,
        int256 _repricerParam1,
        int256 _repricerParam2
    )
        external
        view
        returns (
            int256 estPricePrimary,
            int256 estPriceComplement,
            uint256 estPrice,
            uint256 upperBoundary
        );

    function sqrtWrapped(int256 x) external pure returns (int256);
}
