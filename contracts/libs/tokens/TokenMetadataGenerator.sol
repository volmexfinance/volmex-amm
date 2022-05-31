// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

contract TokenMetadataGenerator {
    function _formatMeta(
        string memory _prefix,
        string memory _concatenator,
        string memory _postfix
    ) internal pure returns (string memory) {
        return _concat(_prefix, _concat(_concatenator, _postfix));
    }

    function _makeTokenName(string memory _baseName, string memory _postfix)
        internal
        pure
        returns (string memory)
    {
        return _formatMeta(_baseName, " ", _postfix);
    }

    function _makeTokenSymbol(string memory _baseName, string memory _postfix)
        internal
        pure
        returns (string memory)
    {
        return _formatMeta(_baseName, "-", _postfix);
    }

    function _concat(string memory _a, string memory _b) internal pure returns (string memory) {
        return string(abi.encodePacked(bytes(_a), bytes(_b)));
    }
}
