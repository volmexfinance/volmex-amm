// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "./IVolmexOracle.sol";

interface IVolmexRepricer {
    // Event emitted when the allowed delay in the oracle price is updated
    event UpdatedAllowedDelay(uint256 newDuration);

    // Getter method
    function oracle() external view returns (IVolmexOracle);

    // Setter methods
    function sqrtWrapped(int256 value) external pure returns (int256);
    function reprice(uint256 _volatilityIndex)
        external
        view
        returns (
            uint256 estPrimaryPrice,
            uint256 estComplementPrice,
            uint256 estPrice
        );
    function updatePriceTimestampDuration(uint256 _newDuration) external;
}
