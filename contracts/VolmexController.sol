// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol';

import './interfaces/IVolmexPool.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';
import './interfaces/IVolmexOracle.sol';
import './interfaces/IPausablePool.sol';
import './interfaces/IVolmexController.sol';
import './maths/Const.sol';

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexController is
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC165StorageUpgradeable,
    Const,
    IVolmexController
{
    // Interface ID of VolmexController contract
    bytes4 private constant _IVOLMEX_CONTROLLER_ID = type(IVolmexController).interfaceId;
    // Interface ID of VolmexOracle contract
    bytes4 private constant _IVOLMEX_ORACLE_ID = type(IVolmexOracle).interfaceId;
    // Interface ID of VolmexPool contract
    bytes4 private constant _IVOLMEX_POOL_ID = type(IVolmexPool).interfaceId;

    // Used to set the index of stableCoin
    uint256 public stableCoinIndex;
    // Used to set the index of pool
    uint256 public poolIndex;
    // Used to store the pools
    address[] public allPools;
    // Address of the oracle
    IVolmexOracle public oracle;

    /**
     * Indices for Pool, Stablecoin and Protocol mappings
     *
     * Pool { 0 = ETHV, 1 = BTCV }
     * Stablecoin { 0 = DAI, 1 = USDC }
     * Protocol { 0 = ETHV-DAI, 1 = ETHV-USDC, 2 = BTCV-DAI, 3 = BTCV-USDC }
     *
     * Pools(Index)   Stablecoin(Index)     Protocol(Address)
     *    0                 0                     0
     *    0                 1                     1
     *    1                 0                     2
     *    1                 1                     3
     */
    // Store the addresses of protocols { pool index => stableCoin index => protocol address }
    mapping(uint256 => mapping(uint256 => IVolmexProtocol)) public protocols;
    /// @notice We have used IERC20Modified instead of IERC20, because the volatility tokens
    /// can't be typecasted to IERC20.
    /// Note: We have used the standard methods on IERC20 only.
    // Store the addresses of stableCoins
    mapping(uint256 => IERC20Modified) public stableCoins;
    // Store the addresses of pools
    mapping(uint256 => IVolmexPool) public pools;
    // Store the bool value of pools to confirm it is pool
    mapping(address => bool) public isPool;

    /**
     * @notice Initializes the contract
     *
     * @dev Sets the volatilityCapRatio
     *
     * @param _stableCoins Address of the collateral token used in protocol
     * @param _pools Address of the pool contract
     * @param _protocols Address of the protocol contract
     */
    function initialize(
        IERC20Modified[2] memory _stableCoins,
        IVolmexPool[2] memory _pools,
        IVolmexProtocol[4] memory _protocols,
        IVolmexOracle _oracle
    ) external initializer {
        require(
            IERC165Upgradeable(address(_oracle)).supportsInterface(_IVOLMEX_ORACLE_ID),
            'VolmexController: Oracle does not supports interface'
        );

        uint256 protocolCount;
        // Note: Since loop size is very small so nested loop won't be a problem
        for (uint256 i; i < 2; i++) {
            require(
                IERC165Upgradeable(address(_pools[i])).supportsInterface(_IVOLMEX_POOL_ID),
                'VolmexController: Pool does not supports interface'
            );
            require(
                address(_stableCoins[i]) != address(0),
                "VolmexController: address of stable coin can't be zero"
            );

            pools[i] = _pools[i];
            stableCoins[i] = _stableCoins[i];
            isPool[address(_pools[i])] = true;
            allPools.push(address(_pools[i]));
            for (uint256 j; j < 2; j++) {
                require(
                    _pools[i].getPrimaryDerivativeAddress() ==
                        address(_protocols[protocolCount].volatilityToken()),
                    'VolmexController: Incorrect pool for add protocol'
                );
                require(
                    _stableCoins[j] == _protocols[protocolCount].collateral(),
                    'VolmexController: Incorrect stableCoin for add protocol'
                );
                protocols[i][j] = _protocols[protocolCount];
                protocolCount++;
            }
        }
        oracle = _oracle;

        __Ownable_init();
        __Pausable_init_unchained(); // Used this, because ownable init is calling context init
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_CONTROLLER_ID);
    }

    /**
     * @notice Used to set the pool on new index
     *
     * @param _pool Address of the Pool contract
     */
    function addPool(IVolmexPool _pool) external onlyOwner {
        require(
            IERC165Upgradeable(address(_pool)).supportsInterface(_IVOLMEX_POOL_ID),
            'VolmexController: Pool does not supports interface'
        );
        poolIndex++;
        pools[poolIndex] = _pool;

        isPool[address(_pool)] = true;
        allPools.push(address(_pool));

        emit PoolAdded(poolIndex, address(_pool));
    }

    /**
     * @notice Usesd to add the stableCoin on new index
     *
     * @param _stableCoin Address of the stableCoin
     */
    function addStableCoin(IERC20Modified _stableCoin) external onlyOwner {
        require(
            address(_stableCoin) != address(0),
            "VolmexController: address of stable coin can't be zero"
        );
        stableCoinIndex++;
        stableCoins[stableCoinIndex] = _stableCoin;

        emit StableCoinAdded(stableCoinIndex, address(_stableCoin));
    }

    /**
     * @notice Used to add the protocol on a particular pool and stableCoin index
     *
     * @param _protocol Address of the Protocol contract
     */
    function addProtocol(
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        IVolmexProtocol _protocol
    ) external onlyOwner {
        require(
            stableCoins[_stableCoinIndex] == _protocol.collateral(),
            'VolmexController: Incorrect stableCoin for add protocol'
        );
        require(
            pools[_poolIndex].getPrimaryDerivativeAddress() ==
                address(_protocol.volatilityToken()),
            'VolmexController: Incorrect pool for add protocol'
        );

        protocols[_poolIndex][_stableCoinIndex] = _protocol;

        emit ProtocolAdded(_poolIndex, _stableCoinIndex, address(_protocol));
    }

    /**
     * @notice Used to pause the pool
     */
    function pausePool(IPausablePool _pool) external onlyOwner {
        _pool.pause();
    }

    /**
     * @notice Used to un-pause the pool
     */
    function unpausePool(IPausablePool _pool) external onlyOwner {
        _pool.unpause();
    }

    /**
     * @notice Used to collect the pool token
     *
     * @param _pool Address of the pool
     */
    function collect(IVolmexPool _pool) external onlyOwner {
        uint256 collected = IERC20(_pool).balanceOf(address(this));
        bool xfer = _pool.transfer(owner(), collected);
        require(xfer, 'ERC20_FAILED');
        emit PoolTokensCollected(owner(), collected);
    }

    /**
     * @notice Used to swap collateral token to a type of volatility token
     *
     * @param _amounts Amount of collateral token and minimum expected volatility token
     * @param _tokenOut Address of the volatility token out
     * @param _indices Indices of the pool and stablecoin to operate { 0: ETHV, 1: BTCV } { 0: DAI, 1: USDC }
     */
    function swapCollateralToVolatility(
        uint256[2] calldata _amounts,
        address _tokenOut,
        uint256[2] calldata _indices
    ) external whenNotPaused {
        IERC20Modified stableCoin = stableCoins[_indices[1]];
        stableCoin.transferFrom(msg.sender, address(this), _amounts[0]);
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[1]];
        _approveAssets(stableCoin, _amounts[0], address(this), address(_protocol));

        _protocol.collateralize(_amounts[0]);

        // Pool and Protocol fee array { 0: Pool, 1: Protocol }
        uint256[3] memory fees;
        uint256 volatilityAmount;
        fees[2] = _protocol.volatilityCapRatio();
        (volatilityAmount, fees[1]) = _calculateAssetQuantity(
            _amounts[0],
            _protocol.issuanceFees(),
            true,
            fees[2]
        );

        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexPool _pool = pools[_indices[0]];

        bool isInverse = _pool.getComplementDerivativeAddress() == _tokenOut;

        uint256 tokenAmountOut;
        (tokenAmountOut, fees[0]) = _pool.getTokenAmountOut(
            isInverse
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            volatilityAmount
        );

        _approveAssets(
            isInverse
                ? IERC20Modified(_pool.getPrimaryDerivativeAddress())
                : IERC20Modified(_pool.getComplementDerivativeAddress()),
            volatilityAmount,
            address(this),
            address(_pool)
        );
        (tokenAmountOut, ) = _pool.swapExactAmountIn(
            isInverse
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            volatilityAmount,
            _tokenOut,
            tokenAmountOut,
            address(this),
            true
        );

        uint256 totalVolatilityAmount = volatilityAmount + tokenAmountOut;

        require(
            totalVolatilityAmount >= _amounts[1],
            'VolmexController: Insufficient expected volatility amount'
        );

        _transferAsset(
            isInverse ? inverseVolatilityToken : volatilityToken,
            totalVolatilityAmount,
            msg.sender
        );

        emit CollateralSwapped(
            _amounts[0],
            totalVolatilityAmount,
            fees[1],
            fees[0],
            _indices[1],
            _tokenOut
        );
    }

    /**
     * @notice Used to swap a type of volatility token to collateral token
     *
     * @param _amounts Amounts array of volatility token and expected collateral
     * @param _indices Indices of the pool and stablecoin to operate { 0: ETHV, 1: BTCV } { 0: DAI, 1: USDC }
     * @param _tokenIn Address of in token
     */
    function swapVolatilityToCollateral(
        uint256[2] calldata _amounts,
        uint256[2] calldata _indices,
        IERC20Modified _tokenIn
    ) external whenNotPaused {
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[1]];
        IVolmexPool _pool = pools[_indices[0]];

        bool isInverse = _pool.getComplementDerivativeAddress() == address(_tokenIn);

        (uint256 swapAmount, uint256 tokenAmountOut, ) = _getSwappedAssetAmount(
            address(_tokenIn),
            _amounts[0],
            _pool,
            isInverse
        );

        // Pool and Protocol fee array { 0: Pool, 1: Protocol }
        uint256[2] memory fees;
        (tokenAmountOut, fees[0]) = _pool.swapExactAmountIn(
            address(_tokenIn),
            swapAmount,
            isInverse
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            tokenAmountOut,
            msg.sender,
            true
        );

        require(
            tokenAmountOut <= _amounts[0] - swapAmount,
            'VolmexController: Amount out limit exploit'
        );

        uint256 collateralAmount;
        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio();
        (collateralAmount, fees[1]) = _calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false,
            _volatilityCapRatio
        );

        require(
            collateralAmount >= _amounts[1],
            'VolmexController: Insufficient expected collateral amount'
        );

        _tokenIn.transferFrom(msg.sender, address(this), tokenAmountOut);
        _protocol.redeem(tokenAmountOut);

        IERC20Modified stableCoin = stableCoins[_indices[1]];
        _transferAsset(stableCoin, collateralAmount, msg.sender);

        emit CollateralSwapped(
            _amounts[0],
            collateralAmount,
            fees[1],
            fees[0],
            _indices[1],
            address(_tokenIn)
        );
    }

    /**
     * @notice Used to swap a a volatility token to another volatility token from another pool
     *
     * @param _tokens Addresses of the tokens { 0: tokenIn, 1: tokenOut }
     * @param _amounts Amounts of the volatility token and expected amount out { 0: amountIn, 1: expAmountOut }
     * @param _indices Indices of the pools and stablecoin to operate { 0: poolIn, 1: poolOut, 2: stablecoin }
     * { 0: ETHV, 1: BTCV } { 0: DAI, 1: USDC }
     */
    function swapBetweenPools(
        address[2] calldata _tokens,
        uint256[2] calldata _amounts,
        uint256[3] calldata _indices
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_indices[0]];

        bool isInverse = _pool.getComplementDerivativeAddress() == _tokens[0];

        // Array of swapAmount {0} and tokenAmountOut {1}
        uint256[2] memory tokenAmounts;
        (tokenAmounts[0], tokenAmounts[1], ) = _getSwappedAssetAmount(
            _tokens[0],
            _amounts[0],
            _pool,
            isInverse
        );

        // Pool and Protocol fee array { 0: Pool In, 1: Pool Out, 2: Protocol In Redeem, 3: Protocol Out Collateralize }
        uint256[4] memory fees;
        (tokenAmounts[1], fees[0]) = _pool.swapExactAmountIn(
            _tokens[0],
            tokenAmounts[0],
            isInverse
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            tokenAmounts[1],
            msg.sender,
            true
        );

        require(
            tokenAmounts[1] <= _amounts[0] - tokenAmounts[0],
            'VolmexController: Amount out limit exploit'
        );

        IERC20Modified(_tokens[0]).transferFrom(msg.sender, address(this), tokenAmounts[1]);
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[2]];
        _protocol.redeem(tokenAmounts[1]);

        // Array of collateralAmount {0} and volatilityAmount {1}
        uint256[3] memory protocolAmounts;
        protocolAmounts[2] = _protocol.volatilityCapRatio();
        (protocolAmounts[0], fees[2]) = _calculateAssetQuantity(
            tokenAmounts[1] * protocolAmounts[2],
            _protocol.redeemFees(),
            false,
            protocolAmounts[2]
        );

        _protocol = protocols[_indices[1]][_indices[2]];
        _approveAssets(
            stableCoins[_indices[2]],
            protocolAmounts[0],
            address(this),
            address(_protocol)
        );
        _protocol.collateralize(protocolAmounts[0]);

        protocolAmounts[2] = _protocol.volatilityCapRatio();
        (protocolAmounts[1], fees[3]) = _calculateAssetQuantity(
            protocolAmounts[0],
            _protocol.issuanceFees(),
            true,
            protocolAmounts[2]
        );

        _pool = pools[_indices[1]];

        isInverse = _pool.getPrimaryDerivativeAddress() != _tokens[1];
        address poolOutTokenIn = isInverse
            ? _pool.getPrimaryDerivativeAddress()
            : _pool.getComplementDerivativeAddress();

        (tokenAmounts[1], ) = _pool.getTokenAmountOut(
            poolOutTokenIn,
            protocolAmounts[1]
        );

        (tokenAmounts[1], fees[1]) = _pool.swapExactAmountIn(
            poolOutTokenIn,
            protocolAmounts[1],
            _tokens[1],
            tokenAmounts[1],
            msg.sender,
            true
        );

        require(
            protocolAmounts[1] + tokenAmounts[1] >= _amounts[1],
            'VolmexController: Insufficient expected volatility amount'
        );

        _transferAsset(
            IERC20Modified(_tokens[1]),
            protocolAmounts[1] + tokenAmounts[1],
            msg.sender
        );

        emit PoolSwapped(
            _amounts[0],
            protocolAmounts[1] + tokenAmounts[1],
            fees[2] + fees[3],
            [fees[0], fees[1]],
            _indices[2],
            _tokens
        );
    }

    /**
     * @notice Used to add liquidity in the pool
     *
     * @param _poolAmountOut Amount of pool token mint and transfer to LP
     * @param _maxAmountsIn Max amount of pool assets an LP can supply
     * @param _poolIndex Index of the pool in which user wants to add liquidity
     */
    function addLiquidity(
        uint256 _poolAmountOut,
        uint256[2] calldata _maxAmountsIn,
        uint256 _poolIndex
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_poolIndex];

        _pool.joinPool(_poolAmountOut, _maxAmountsIn, msg.sender);
    }

    /**
     * @notice Used to remove liquidity from the pool
     *
     * @param _poolAmountIn Amount of pool token transfer to the pool
     * @param _minAmountsOut Min amount of pool assets an LP wish to redeem
     * @param _poolIndex Index of the pool in which user wants to add liquidity
     */
    function removeLiquidity(
        uint256 _poolAmountIn,
        uint256[2] calldata _minAmountsOut,
        uint256 _poolIndex
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_poolIndex];

        _pool.exitPool(_poolAmountIn, _minAmountsOut, msg.sender);
    }

    /**
     * @notice Used to call flash loan on Pool
     *
     * @dev This method is for developers.
     * Make sure you call this method from a contract with the implementation
     * of IFlashLoanReceiver interface
     *
     * @param _assetToken Address of the token in need
     * @param _amount Amount of token in need
     * @param _params msg.data for verifying the loan
     * @param _poolIndex Index of the Pool
     */
    function makeFlashLoan(
        address _assetToken,
        uint256 _amount,
        bytes calldata _params,
        uint256 _poolIndex
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_poolIndex];
        _pool.flashLoan(msg.sender, _assetToken, _amount, _params);
    }

    function swapIn(
        uint256 _poolIndex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_poolIndex];

        _pool.swapExactAmountIn(_tokenIn, _amountIn, _tokenOut, _amountOut, msg.sender, false);
    }

    /**
     * @notice Used by VolmexPool contract to transfer the token amount to VolmexPool
     *
     * @param _token Address of the token contract
     * @param _account Address of the user/contract from balance transfer
     * @param _amount Amount of the token
     */
    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        uint256 _amount
    ) external {
        require(isPool[msg.sender], 'VolmexController: Caller is not pool');
        _token.transferFrom(_account, msg.sender, _amount);
    }

    /**
     * @notice Used to get the volatility amount out
     *
     * @param _collateralAmount Amount of minimum expected collateral
     * @param _tokenOut Address of the token out
     * @param _indices Index of pool and stableCoin
     */
    function getCollateralToVolatility(
        uint256 _collateralAmount,
        address _tokenOut,
        uint256[2] calldata _indices
    ) external view returns (uint256 volatilityAmount, uint256[2] memory fees) {
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[1]];
        IVolmexPool _pool = pools[_indices[0]];

        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio();
        (volatilityAmount, fees[1]) = _calculateAssetQuantity(
            _collateralAmount,
            _protocol.issuanceFees(),
            true,
            _volatilityCapRatio
        );

        bool isInverse = _pool.getComplementDerivativeAddress() == _tokenOut;

        uint256 tokenAmountOut;
        (tokenAmountOut, fees[0]) = _pool.getTokenAmountOut(
            isInverse
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            volatilityAmount
        );

        volatilityAmount += tokenAmountOut;
    }

    /**
     * @notice Used to get collateral amount, fees, left over amount while swapping volatility
     * to collateral/stablecoin
     *
     * @param _tokenIn Address of token in
     * @param _amount Value of amount wants to swap
     * @param _poolIndex Index of pool on operation
     * @param _stableCoinIndex Index of the stable coin / collateral
     * @param _isInverse Bool value of passed token in type
     */
    function getVolatilityToCollateral(
        address _tokenIn,
        uint256 _amount,
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        bool _isInverse
    ) external view returns (uint256 collateralAmount, uint256[2] memory fees) {
        IVolmexProtocol _protocol = protocols[_poolIndex][_stableCoinIndex];
        IVolmexPool _pool = pools[_poolIndex];

        uint256 swapAmount;
        uint256 tokenAmountOut;
        uint256 poolFee;
        uint256 protocolFee;
        (swapAmount, tokenAmountOut, poolFee) = _getSwappedAssetAmount(
            _tokenIn,
            _amount,
            _pool,
            _isInverse
        );
        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio();
        (collateralAmount, protocolFee) = _calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false,
            _volatilityCapRatio
        );

        fees = [poolFee, protocolFee];
    }

    /**
     * @notice Used to get the token out amount of swap in between multiple pools
     *
     * @param _tokens Addresses of token in and out
     * @param _amountIn Value of amount in or change
     * @param _indices Array of indices of poolOut, poolIn and stable coin
     *
     * returns amountOut, and fees array {0: pool in fee, 1: pool out fee, 2: protocolFee}
     */
    function getSwapAmountBetweenPools(
        address[2] calldata _tokens,
        uint256 _amountIn,
        uint256[3] calldata _indices
    ) external view returns (uint256 amountOut, uint256[3] memory fees) {
        IVolmexPool _pool = IVolmexPool(pools[_indices[0]]);

        uint256 tokenAmountOut;
        uint256 fee;
        (, tokenAmountOut, fee) = _getSwappedAssetAmount(
            _tokens[0],
            _amountIn,
            _pool,
            _pool.getComplementDerivativeAddress() == _tokens[0]
        );
        fees[0] = fee;

        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[2]];
        uint256[3] memory protocolAmount;
        protocolAmount[2] = _protocol.volatilityCapRatio();
        (protocolAmount[0], fee) = _calculateAssetQuantity(
            tokenAmountOut * protocolAmount[2],
            _protocol.redeemFees(),
            false,
            protocolAmount[2]
        );
        fees[2] = fee;

        _protocol = protocols[_indices[1]][_indices[2]];
        protocolAmount[2] = _protocol.volatilityCapRatio();

        (protocolAmount[1], fee) = _calculateAssetQuantity(
            protocolAmount[0],
            _protocol.issuanceFees(),
            true,
            protocolAmount[2]
        );
        fees[2] += fee;

        _pool = pools[_indices[1]];

        (tokenAmountOut, fee) = _pool.getTokenAmountOut(
            _pool.getPrimaryDerivativeAddress() != _tokens[1]
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            protocolAmount[1]
        );
        fees[1] += fee;

        amountOut = protocolAmount[1] + tokenAmountOut;
    }

    function _calculateAssetQuantity(
        uint256 _amount,
        uint256 _feePercent,
        bool _isVolatility,
        uint256 _volatilityCapRatio
    ) private pure returns (uint256 amount, uint256 protocolFee) {
        protocolFee = (_amount * _feePercent) / 10000;
        _amount = _amount - protocolFee;

        amount = _isVolatility ? _amount / _volatilityCapRatio : _amount;
    }

    function _transferAsset(
        IERC20Modified _token,
        uint256 _amount,
        address receiver
    ) private {
        _token.transfer(receiver, _amount);
    }

    function _approveAssets(
        IERC20Modified _token,
        uint256 _amount,
        address _owner,
        address _spender
    ) private {
        uint256 _allowance = _token.allowance(_owner, _spender);

        if (_amount <= _allowance) return;

        _token.approve(_spender, _amount);
    }

    function _volatilityAmountToSwap(
        uint256 _amount,
        IVolmexPool _pool,
        bool _isInverse,
        uint256 _fee
    ) private view returns (uint256 volatilityAmount) {
        (uint256 price, uint256 iPrice) = oracle.getVolatilityTokenPriceByIndex(
            _pool.volatilityIndex()
        );

        uint256 leverage = _pool.getLeverage(_pool.getPrimaryDerivativeAddress());
        uint256 iLeverage = _pool.getLeverage(_pool.getComplementDerivativeAddress());

        volatilityAmount = !_isInverse
            ? ((_amount * iPrice * iLeverage) * BONE) /
                (price * leverage * (BONE - _fee) + iPrice * iLeverage * BONE)
            : ((_amount * price * leverage) * BONE) /
                (iPrice * iLeverage * (BONE - _fee) + price * leverage * BONE);
    }

    function _getSwappedAssetAmount(
        address _tokenIn,
        uint256 _amount,
        IVolmexPool _pool,
        bool _isInverse
    )
        private
        view
        returns (
            uint256 swapAmount,
            uint256 amountOut,
            uint256 fee
        )
    {
        swapAmount = _volatilityAmountToSwap(_amount, _pool, _isInverse, 0);

        (, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount
        );

        swapAmount = _volatilityAmountToSwap(_amount, _pool, _isInverse, fee);

        (amountOut, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount
        );
    }
}
