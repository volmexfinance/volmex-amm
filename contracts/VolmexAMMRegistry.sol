// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

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
        _pools.push(_newPool);
        _isPool[_newPool] = true;
        IPool(_newPool).transferOwnership(address(this));
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
