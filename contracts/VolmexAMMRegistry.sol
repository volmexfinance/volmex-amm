// SPDX-License-Identifier: BUSL-1.1

pragma solidity 0.7.6;

// Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import './IPool.sol';
import './interfaces/IPausablePool.sol';

contract VolmexAMMRegistry is OwnableUpgradeable {
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool,
        uint256 indexed poolIndex
    );

    uint256 public index;
    address[] internal _pools;
    mapping(address => bool) private _isPool;

    function initialize() external initializer {
        __Ownable_init();
    }

    function isPool(address _pool) external view returns (bool) {
        return _isPool[_pool];
    }

    function registerNewPool(address _newPool) external {
        require(!_isPool[_newPool], 'VolmexAMMRegistry: Pool already exist');

        _pools.push(_newPool);
        _isPool[_newPool] = true;
        index++;
        emit LOG_NEW_POOL(msg.sender, _newPool, index);
    }

    function pausePool(IPausablePool _pool) public onlyOwner {
        _pool.pause();
    }

    function unpausePool(IPausablePool _pool) public onlyOwner {
        _pool.unpause();
    }

    function collect(IPool pool) external onlyOwner {
        uint256 collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(owner(), collected);
        require(xfer, 'ERC20_FAILED');
    }

    function getPool(uint256 _index) external view returns (address) {
        return _pools[_index];
    }

    function getLastPoolIndex() external view returns (uint256) {
        return _pools.length - 1;
    }

    function getAllPools() external view returns (address[] memory) {
        return _pools;
    }
}
