// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

interface ILayerZeroVolmexPositionToken {
    function __LayerZero_init( string memory _name, string memory _symbol, address _lzEndpoint) external;
}