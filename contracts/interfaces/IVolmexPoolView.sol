// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

interface IVolmexPoolView {
    struct TokenRecord {
        address self;
        uint256 balance;
        uint256 leverage;
        uint8 decimals;
        uint256 userBalance;
    }

    struct TokenData {
        address self;
        uint256 totalSupply;
        uint8 decimals;
        uint256 userBalance;
    }

    struct Config {
        address protocol;
        address repricer;
        bool isPaused;
        uint8 qMinDecimals;
        uint8 decimals;
        uint256 exposureLimitPrimary;
        uint256 exposureLimitComplement;
        uint256 pMin;
        uint256 qMin;
        uint256 baseFee;
        uint256 maxFee;
        uint256 feeAmpPrimary;
        uint256 feeAmpComplement;
    }

    function getPoolInfo(address _pool, address _sender)
        external
        view
        returns (
            TokenRecord memory primary,
            TokenRecord memory complement,
            TokenData memory poolToken,
            Config memory config
        );

    function getPoolTokenData(address _pool)
        external
        view
        returns (
            address primary,
            uint256 primaryBalance,
            uint256 primaryLeverage,
            uint8 primaryDecimals,
            address complement,
            uint256 complementBalance,
            uint256 complementLeverage,
            uint8 complementDecimals,
            uint256 lpTotalSupply,
            uint8 lpDecimals
        );

    function getPoolConfig(address _pool)
        external
        view
        returns (
            address protocol,
            address repricer,
            uint256 exposureLimitPrimary,
            uint256 exposureLimitComplement,
            uint256 pMin,
            uint256 qMin,
            uint256 baseFee,
            uint256 maxFee,
            uint256 feeAmpPrimary,
            uint256 feeAmpComplement
        );
}
