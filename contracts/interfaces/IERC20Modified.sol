// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.7.6;

/**
 * @dev Modified Interface of the OpenZeppelin's IERC20 extra functions to add features in position token.
 */
interface IERC20Modified {
    // IERC20 Methods
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    // Custom Methods
    function symbol() external view returns (string memory);

    function name() external view returns (string memory);

    function mint(address _toWhom, uint256 amount) external;

    function burn(address _whose, uint256 amount) external;

    function grantRole(bytes32 role, address account) external;

    function renounceRole(bytes32 role, address account) external;

    function pause() external;

    function unpause() external;
}
