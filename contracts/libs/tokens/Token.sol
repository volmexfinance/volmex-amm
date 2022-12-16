// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "../../maths/Num.sol";
import "../../interfaces/IERC20.sol";

contract TokenBase is Num {
    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed _src, address indexed _dst, uint256 _amt);
    event Transfer(address indexed _src, address indexed _dst, uint256 _amt);

    function _mint(uint256 _amt) internal {
        _balance[address(this)] = _balance[address(this)] + _amt;
        _totalSupply = _totalSupply + _amt;
        emit Transfer(address(0), address(this), _amt);
    }

    function _burn(uint256 _amt) internal {
        require(_balance[address(this)] >= _amt, "INSUFFICIENT_BAL");
        _balance[address(this)] = _balance[address(this)] - _amt;
        _totalSupply = _totalSupply - _amt;
        require(_totalSupply != 0, "BAD_SUPPLY");
        emit Transfer(address(this), address(0), _amt);
    }

    function _move(
        address _src,
        address _dst,
        uint256 _amt
    ) internal {
        require(_balance[_src] >= _amt, "INSUFFICIENT_BAL");
        _balance[_src] = _balance[_src] - _amt;
        _balance[_dst] = _balance[_dst] + _amt;
        emit Transfer(_src, _dst, _amt);
    }

    function _push(address _to, uint256 _amt) internal {
        _move(address(this), _to, _amt);
    }

    function _pull(address _from, uint256 _amt) internal {
        _move(_from, address(this), _amt);
    }
}

contract Token is TokenBase, IERC20 {
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    function approve(address _dst, uint256 _amt) external override returns (bool) {
        _allowance[msg.sender][_dst] = _amt;
        emit Approval(msg.sender, _dst, _amt);
        return true;
    }

    function increaseApproval(address _dst, uint256 _amt) external returns (bool) {
        _allowance[msg.sender][_dst] = _allowance[msg.sender][_dst] + _amt;
        emit Approval(msg.sender, _dst, _allowance[msg.sender][_dst]);
        return true;
    }

    function decreaseApproval(address _dst, uint256 _amt) external returns (bool) {
        uint256 oldValue = _allowance[msg.sender][_dst];
        if (_amt > oldValue) {
            _allowance[msg.sender][_dst] = 0;
        } else {
            _allowance[msg.sender][_dst] = oldValue - _amt;
        }
        emit Approval(msg.sender, _dst, _allowance[msg.sender][_dst]);
        return true;
    }

    function transfer(address _dst, uint256 _amt) external override returns (bool) {
        _move(msg.sender, _dst, _amt);
        return true;
    }

    function transferFrom(
        address _src,
        address _dst,
        uint256 _amt
    ) external override returns (bool) {
        uint256 oldValue = _allowance[_src][msg.sender];
        require(msg.sender == _src || _amt <= oldValue, "TOKEN_BAD_CALLER");
        _move(_src, _dst, _amt);
        if (msg.sender != _src && oldValue != type(uint128).max) {
            _allowance[_src][msg.sender] = oldValue - _amt;
            emit Approval(msg.sender, _dst, _allowance[_src][msg.sender]);
        }
        return true;
    }

    function allowance(address _src, address _dst) external view override returns (uint256) {
        return _allowance[_src][_dst];
    }

    function balanceOf(address _whom) external view override returns (uint256) {
        return _balance[_whom];
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public pure returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function _setName(string memory _poolName) internal {
        _name = _poolName;
    }

    function _setSymbol(string memory _poolSymbol) internal {
        _symbol = _poolSymbol;
    }
}
