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

pragma solidity 0.7.6;
// pragma abicoder v2;

// import './IPool.sol';
// import './libs/complifi/tokens/IERC20Metadata.sol';

// /// @title Reading key data from specified derivative trading Pool
// contract PoolView {

//     /// @notice Contains key information about a derivative token
//     struct TokenRecord {
//         address self;
//         uint256 balance;
//         uint256 leverage;
//         uint8 decimals;
//         uint256 userBalance;
//     }

//     /// @notice Contains key information about arbitrary ERC20 token
//     struct Token {
//         address self;
//         uint256 totalSupply;
//         uint8 decimals;
//         uint256 userBalance;
//     }

//     /// @notice Contains key information about a Pool's configuration
//     struct Config {
//         address derivativeVault;
//         address dynamicFee;
//         address repricer;
//         uint256 exposureLimitPrimary;
//         uint256 exposureLimitComplement;
//         uint256 repricerParam1;
//         uint256 repricerParam2;
//         uint256 pMin;
//         uint256 qMin;
//         uint8 qMinDecimals;
//         uint256 baseFee;
//         uint256 maxFee;
//         uint256 feeAmpPrimary;
//         uint256 feeAmpComplement;
//         uint8 decimals;
//         bool isPaused;
//     }

//     /// @notice Getting information about Pool configuration, it's derivative and pool(LP) tokens
//     /// @param _pool the vault address
//     /// @return primary pool's primary token metadata
//     /// @return complement pool' complement token metadata
//     /// @return poolToken pool's own token metadata
//     /// @return config pool configuration
//     function getPoolInfo(address _pool, address _sender)
//         external
//         view
//         returns (
//             TokenRecord memory primary,
//             TokenRecord memory complement,
//             Token memory poolToken,
//             Config memory config
//         )
//     {
//         IPool pool = IPool(_pool);

//         address _primaryAddress = address(pool.derivativeVault().primaryToken());
//         primary = TokenRecord(
//             _primaryAddress,
//             pool.getBalance(_primaryAddress),
//             pool.getLeverage(_primaryAddress),
//             IERC20Metadata(_primaryAddress).decimals(),
//             _sender == address(0) ? 0 : IERC20(_primaryAddress).balanceOf(_sender)
//         );

//         address _complementAddress = address(pool.derivativeVault().complementToken());
//         complement = TokenRecord(
//             _complementAddress,
//             pool.getBalance(_complementAddress),
//             pool.getLeverage(_complementAddress),
//             IERC20Metadata(_complementAddress).decimals(),
//             _sender == address(0) ? 0 : IERC20(_complementAddress).balanceOf(_sender)
//         );

//         poolToken = Token(
//             _pool,
//             pool.totalSupply(),
//             IERC20Metadata(_pool).decimals(),
//             _sender == address(0) ? 0 : IERC20(_pool).balanceOf(_sender)
//         );

//         config = Config(
//             address(pool.derivativeVault()),
//             address(pool.dynamicFee()),
//             address(pool.repricer()),
//             pool.exposureLimitPrimary(),
//             pool.exposureLimitComplement(),
//             pool.repricerParam1(),
//             pool.repricerParam2(),
//             pool.pMin(),
//             pool.qMin(),
//             IERC20Metadata(_primaryAddress).decimals(),
//             pool.baseFee(),
//             pool.maxFee(),
//             pool.feeAmpPrimary(),
//             pool.feeAmpComplement(),
//             IERC20Metadata(_pool).decimals(),
//             pool.paused()
//         );
//     }

//     /// @notice Getting current state of Pool, token balances and leverages, LP token supply
//     /// @param _pool vault address
//     /// @return primary pool's primary token address
//     /// @return primaryBalance pool's primary token balance
//     /// @return primaryLeverage pool's primary token leverage
//     /// @return primaryDecimals pool's primary token decimals
//     /// @return complement pool's complement token address
//     /// @return complementBalance pool's complement token balance
//     /// @return complementLeverage pool's complement token leverage
//     /// @return complementDecimals pool's complement token decimals
//     /// @return lpTotalSupply pool's LP token total supply
//     /// @return lpDecimals pool's LP token decimals
//     function getPoolTokenData(address _pool)
//         external
//         view
//         returns (
//             address primary,
//             uint256 primaryBalance,
//             uint256 primaryLeverage,
//             uint8 primaryDecimals,
//             address complement,
//             uint256 complementBalance,
//             uint256 complementLeverage,
//             uint8 complementDecimals,
//             uint256 lpTotalSupply,
//             uint8 lpDecimals
//         )
//     {
//         IPool pool = IPool(_pool);

//         primary = address(pool.derivativeVault().primaryToken());
//         complement = address(pool.derivativeVault().complementToken());

//         primaryBalance = pool.getBalance(primary);
//         primaryLeverage = pool.getLeverage(primary);
//         primaryDecimals = IERC20Metadata(primary).decimals();

//         complementBalance = pool.getBalance(complement);
//         complementLeverage = pool.getLeverage(complement);
//         complementDecimals = IERC20Metadata(complement).decimals();

//         lpTotalSupply = pool.totalSupply();
//         lpDecimals = IERC20Metadata(_pool).decimals();
//     }

//     /// @notice Getting Pool configuration only to reduce data loading time
//     function getPoolConfig(address _pool)
//         external
//         view
//         returns (
//             address derivativeVault,
//             address dynamicFee,
//             address repricer,
//             uint256 exposureLimitPrimary,
//             uint256 exposureLimitComplement,
//             uint256 repricerParam1,
//             uint256 repricerParam2,
//             uint256 pMin,
//             uint256 qMin,
//             uint256 baseFee,
//             uint256 maxFee,
//             uint256 feeAmpPrimary,
//             uint256 feeAmpComplement
//         )
//     {
//         IPool pool = IPool(_pool);
//         derivativeVault = address(pool.derivativeVault());
//         dynamicFee = address(pool.dynamicFee());
//         repricer = address(pool.repricer());
//         pMin = pool.pMin();
//         qMin = pool.qMin();
//         exposureLimitPrimary = pool.exposureLimitPrimary();
//         exposureLimitComplement = pool.exposureLimitComplement();
//         baseFee = pool.baseFee();
//         feeAmpPrimary = pool.feeAmpPrimary();
//         feeAmpComplement = pool.feeAmpComplement();
//         maxFee = pool.maxFee();
//         repricerParam1 = pool.repricerParam1();
//         repricerParam2 = pool.repricerParam2();
//     }
// }
