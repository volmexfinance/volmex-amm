// "SPDX-License-Identifier: GNU General Public License v3.0"

pragma solidity 0.7.6;

// import './Pool.sol';
// import './IPoolBuilder.sol';

// contract PoolBuilder is IPoolBuilder {
//     function buildPool(
//         address _controller,
//         address _derivativeVault,
//         address _feeCalculator,
//         address _repricer,
//         //TODO: remove params when a new factory is deploying
//         uint256 _baseFee,
//         uint256 _maxFee,
//         uint256 _feeAmp
//     ) public override returns (address) {
//         Pool pool =
//             new Pool(
//                 _derivativeVault,
//                 _feeCalculator,
//                 _repricer,
//                 _controller
//             );
//         pool.transferOwnership(msg.sender);
//         return address(pool);
//     }
// }
