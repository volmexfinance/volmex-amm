// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '../VolmexPool.sol';
import 'hardhat/console.sol';

/**
 * @title Volmex Pool Mock Contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexPoolMock is VolmexPool {
    function mock_Initialize(
        IVolmexRepricer _repricer,
        IVolmexProtocol _protocol,
        uint256 _volatilityIndex,
        uint256 _baseFee,
        uint256 _maxFee,
        uint256 _feeAmpPrimary,
        uint256 _feeAmpComplement
    ) external initializer {
        initialize(_repricer, _protocol, _volatilityIndex, _baseFee, _maxFee, _feeAmpPrimary, _feeAmpComplement);

        controller = IVolmexController(owner());
    }

    function _pullUnderlying(
        address erc20,
        address from,
        uint256 amount
    ) internal override returns (uint256) {
        uint256 balanceBefore = IERC20(erc20).balanceOf(address(this));

        address(controller) == owner()
            ? EIP20NonStandardInterface(erc20).transferFrom(from, address(this), amount)
            : controller.transferAssetToPool(IERC20Modified(erc20), from, amount);

        bool success;
        //solium-disable-next-line security/no-inline-assembly
        assembly {
            switch returndatasize()
            case 0 {
                // This is a non-standard ERC-20
                success := not(0) // set success to true
            }
            case 32 {
                // This is a compliant ERC-20
                returndatacopy(0, 0, 32)
                success := mload(0) // Set `success = returndata` of external call
            }
            default {
                // This is an excessively non-compliant ERC-20, revert.
                revert(0, 0)
            }
        }
        require(success, 'VolmexPool: Token transfer failed');

        // Calculate the amount that was *actually* transferred
        uint256 balanceAfter = IERC20(erc20).balanceOf(address(this));
        require(balanceAfter >= balanceBefore, 'VolmexPool: Token transfer overflow met');
        return balanceAfter - balanceBefore; // underflow already checked above, just subtract
    }
}
