// // "SPDX-License-Identifier: GNU General Public License v3.0"

// pragma solidity 0.7.6;

// import './TPool.sol';
// import '../IPoolBuilder.sol';

// contract TPoolBuilder is IPoolBuilder {
//     function buildPool(
//         address controller,
//         address derivativeVault,
//         address feeCalculator,
//         address repricer,
//         uint256 _baseFee,
//         uint256 _maxFee,
//         uint256 _feeAmp
//     ) public override returns (address) {
//         TPool pool = new TPool(derivativeVault, feeCalculator, repricer, controller);
//         pool.transferOwnership(msg.sender);
//         return address(pool);
//     }
// }
