// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

contract TestCollateralToken is ERC20PresetMinterPauser {
    uint8 private decimal;

    constructor(
        string memory _symbol,
        uint256 _initSupply,
        uint8 _decimal
    ) ERC20PresetMinterPauser("VolmexTestCollateralToken", _symbol) {
        mint(msg.sender, _initSupply);
        decimal = _decimal;
    }

    function decimals() public view override returns (uint8) {
        return decimal;
    }
}
