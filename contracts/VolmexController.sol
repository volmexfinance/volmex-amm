// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/introspection/IERC165Upgradeable.sol";

import "./interfaces/IVolmexPool.sol";
import "./interfaces/IVolmexProtocol.sol";
import "./interfaces/IERC20Modified.sol";
import "./interfaces/IVolmexOracle.sol";
import "./interfaces/IPausablePool.sol";
import "./interfaces/IVolmexController.sol";
import "./maths/Math.sol";

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexController is
    OwnableUpgradeable,
    PausableUpgradeable,
    ERC165StorageUpgradeable,
    Math,
    IVolmexController
{
    // Interface ID of VolmexController contract, hashId  = 0xe8f8535b
    bytes4 private constant _IVOLMEX_CONTROLLER_ID = type(IVolmexController).interfaceId;
    // Interface ID of VolmexPool contract, hashId = 0x71e45f88
    bytes4 private constant _IVOLMEX_POOL_ID = type(IVolmexPool).interfaceId;

    // Used to set the index of stableCoin
    uint256 public stableCoinIndex;
    // Used to set the index of pool
    uint256 public poolIndex;
    // Used to store the pools
    address[] public allPools;

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
    // Store the precision ratio according to stableCoin index
    mapping(uint256 => uint256) public precisionRatios;

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
        address _owner
    ) external initializer {
        uint256 protocolCount;
        // Note: Since loop size is very small so nested loop won't be a problem
        for (uint256 i; i < 2; i++) {
            require(
                IERC165Upgradeable(address(_pools[i])).supportsInterface(_IVOLMEX_POOL_ID),
                "VolmexController: Pool does not supports interface"
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
                    _pools[i].tokens(0) == address(_protocols[protocolCount].volatilityToken()),
                    "VolmexController: Incorrect pool for add protocol"
                );
                require(
                    _stableCoins[j] == _protocols[protocolCount].collateral(),
                    "VolmexController: Incorrect stableCoin for add protocol"
                );
                protocols[i][j] = _protocols[protocolCount];
                try protocols[i][j].precisionRatio() returns (uint256 ratio) {
                    precisionRatios[j] = ratio;
                } catch (bytes memory) {
                    precisionRatios[j] = 1;
                }
                protocolCount++;
            }
        }
        poolIndex++;
        stableCoinIndex++;

        __Ownable_init();
        __Pausable_init_unchained();
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_CONTROLLER_ID);
        _transferOwnership(_owner);
    }

    /**
     * @notice Used to set the pool on new index
     *
     * @param _pool Address of the Pool contract
     */
    function addPool(IVolmexPool _pool) external onlyOwner {
        require(
            IERC165Upgradeable(address(_pool)).supportsInterface(_IVOLMEX_POOL_ID),
            "VolmexController: Pool does not supports interface"
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
     * @param _stableCoinIndex index of stable coin
     */
    function addProtocol(
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        IVolmexProtocol _protocol
    ) external onlyOwner {
        require(
            stableCoins[_stableCoinIndex] == _protocol.collateral(),
            "VolmexController: Incorrect stableCoin for add protocol"
        );
        require(
            pools[_poolIndex].tokens(0) == address(_protocol.volatilityToken()),
            "VolmexController: Incorrect pool for add protocol"
        );

        protocols[_poolIndex][_stableCoinIndex] = _protocol;

        try _protocol.precisionRatio() returns (uint256 ratio) {
            precisionRatios[_stableCoinIndex] = ratio;
        } catch (bytes memory) {
            precisionRatios[_stableCoinIndex] = 1;
        }

        emit ProtocolAdded(_poolIndex, _stableCoinIndex, address(_protocol));
    }

    /**
     * @notice Pause/unpause volmex controller contract
     *
     * @param _isPause Boolean value to pause or unpause the position token { true = pause, false = unpause }
     */
    function togglePause(bool _isPause) external virtual onlyOwner {
        _isPause ? _pause() : _unpause();
    }

    /**
     * @notice Pause/unpause volmex pool contract
     *
     * @param _isPause Boolean value to pause or unpause the position token { true = pause, false = unpause }
     */
    function togglePoolPause(IVolmexPool _pool, bool _isPause) external virtual onlyOwner {
        _pool.togglePause(_isPause);
    }

    /**
     * @notice Used to collect the pool token
     *
     * @param _pool Address of the pool
     */
    function collect(IVolmexPool _pool) external onlyOwner {
        uint256 collected = IERC20(_pool).balanceOf(address(this));
        bool xfer = _pool.transfer(owner(), collected);
        require(xfer, "ERC20_FAILED");
        emit PoolTokensCollected(owner(), collected);
    }

    /**
     * @notice Finalizes the pool
     *
     * @param _primaryBalance Balance amount of primary token
     * @param _primaryLeverage Leverage value of primary token
     * @param _complementBalance  Balance amount of complement token
     * @param _complementLeverage  Leverage value of complement token
     * @param _exposureLimitPrimary Primary to complement swap difference limit
     * @param _exposureLimitComplement Complement to primary swap difference limit
     * @param _pMin Minimum amount of tokens in the pool
     * @param _qMin Minimum amount of token required for swap
     */
    function finalizePool(
        uint256 _poolIndex,
        uint256 _primaryBalance,
        uint256 _primaryLeverage,
        uint256 _complementBalance,
        uint256 _complementLeverage,
        uint256 _exposureLimitPrimary,
        uint256 _exposureLimitComplement,
        uint256 _pMin,
        uint256 _qMin
    ) external onlyOwner {
        IVolmexPool _pool = pools[_poolIndex];

        _pool.finalize(
            _primaryBalance,
            _primaryLeverage,
            _complementBalance,
            _complementLeverage,
            _exposureLimitPrimary,
            _exposureLimitComplement,
            _pMin,
            _qMin,
            msg.sender
        );
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
            fees[2],
            precisionRatios[_indices[1]]
        );

        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexPool _pool = pools[_indices[0]];

        bool isInverse = _pool.tokens(1) == _tokenOut;

        _pool.reprice();
        uint256 tokenAmountOut;
        (tokenAmountOut, fees[0]) = _pool.getTokenAmountOut(
            isInverse ? _pool.tokens(0) : _pool.tokens(1),
            volatilityAmount
        );

        _approveAssets(
            isInverse ? IERC20Modified(_pool.tokens(0)) : IERC20Modified(_pool.tokens(1)),
            volatilityAmount,
            address(this),
            address(this)
        );
        (tokenAmountOut, ) = _pool.swapExactAmountIn(
            isInverse ? _pool.tokens(0) : _pool.tokens(1),
            volatilityAmount,
            _tokenOut,
            tokenAmountOut,
            address(this),
            true
        );

        uint256 totalVolatilityAmount = volatilityAmount + tokenAmountOut;

        require(
            totalVolatilityAmount >= _amounts[1],
            "VolmexController: Insufficient expected volatility amount"
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
     * @param _amounts Amounts array of maximum volatility token and minimum expected collateral
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

        bool isInverse = _pool.tokens(1) == address(_tokenIn);

        _pool.reprice();
        // Pool and Protocol fee array { 0: Pool, 1: Protocol }
        uint256[2] memory fees;
        uint256[3] memory tokenAmounts; // 0: tokenAmountIn, 1: tokenAmountOut, 3: redeemAmount
        // Assuming the getter will return exact fee, considering the call in same transaction
        (tokenAmounts[0], tokenAmounts[1], fees[0]) = _getSwappedAssetAmount(
            address(_tokenIn),
            _amounts[0],
            _pool,
            isInverse
        );

        (tokenAmounts[1], ) = _pool.swapExactAmountIn(
            address(_tokenIn),
            tokenAmounts[0],
            isInverse ? _pool.tokens(0) : _pool.tokens(1),
            tokenAmounts[1],
            msg.sender,
            true
        );

        if (tokenAmounts[1] <= _amounts[0] - tokenAmounts[0]) {
            tokenAmounts[2] = tokenAmounts[1];
        } else {
            tokenAmounts[2] = _amounts[0] - tokenAmounts[0];
            require(
                (BONE / 10) > tokenAmounts[1] - tokenAmounts[2],
                "VolmexController: Deviation too large"
            );
        }

        uint256 collateralAmount;
        uint256 _volatilityCapRatio = _protocol.volatilityCapRatio();
        (collateralAmount, fees[1]) = _calculateAssetQuantity(
            tokenAmounts[2] * _volatilityCapRatio,
            _protocol.redeemFees(),
            false,
            _volatilityCapRatio,
            precisionRatios[_indices[1]]
        );

        require(
            collateralAmount >= _amounts[1],
            "VolmexController: Insufficient expected collateral amount"
        );

        _tokenIn.transferFrom(msg.sender, address(this), tokenAmounts[2]);
        _protocol.redeem(tokenAmounts[2]);

        IERC20Modified stableCoin = stableCoins[_indices[1]];
        _transferAsset(stableCoin, collateralAmount, msg.sender);
        if (tokenAmounts[1] - tokenAmounts[2] > 0) {
            _transferAsset(
                IERC20Modified(isInverse ? _pool.tokens(0) : _pool.tokens(1)),
                tokenAmounts[1] - tokenAmounts[2],
                msg.sender
            );
        }

        emit CollateralSwapped(
            tokenAmounts[0] + tokenAmounts[2],
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

        bool isInverse = _pool.tokens(1) == _tokens[0];

        _pool.reprice();
        // Array of swapAmount {0}, tokenAmountOut {1}, redeemAmount {2} adn leftOverAmount {3}
        uint256[4] memory tokenAmounts;
        // Pool and Protocol fee array { 0: Pool In, 1: Pool Out, 2: Protocol In Redeem, 3: Protocol Out Collateralize }
        uint256[4] memory fees;
        // Assuming the getter will return exact fee, considering the call in same transaction
        (tokenAmounts[0], tokenAmounts[1], fees[0]) = _getSwappedAssetAmount(
            _tokens[0],
            _amounts[0],
            _pool,
            isInverse
        );

        (tokenAmounts[1], ) = _pool.swapExactAmountIn(
            _tokens[0],
            tokenAmounts[0],
            isInverse ? _pool.tokens(0) : _pool.tokens(1),
            tokenAmounts[1],
            msg.sender,
            true
        );

        if (tokenAmounts[1] <= _amounts[0] - tokenAmounts[0]) {
            tokenAmounts[2] = tokenAmounts[1];
        } else {
            tokenAmounts[2] = _amounts[0] - tokenAmounts[0];
            require(
                (BONE / 10) > tokenAmounts[1] - tokenAmounts[2],
                "VolmexController: Deviation too large"
            );
            tokenAmounts[3] = tokenAmounts[1] - tokenAmounts[2];
        }

        IERC20Modified(_tokens[0]).transferFrom(msg.sender, address(this), tokenAmounts[2]);
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[2]];
        _protocol.redeem(tokenAmounts[2]);

        // Array of collateralAmount {0} and volatilityAmount {1}
        uint256[3] memory protocolAmounts;
        protocolAmounts[2] = _protocol.volatilityCapRatio();
        (protocolAmounts[0], fees[2]) = _calculateAssetQuantity(
            tokenAmounts[2] * protocolAmounts[2],
            _protocol.redeemFees(),
            false,
            protocolAmounts[2],
            precisionRatios[_indices[2]]
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
            protocolAmounts[2],
            precisionRatios[_indices[2]]
        );

        _pool = pools[_indices[1]];

        isInverse = _pool.tokens(0) != _tokens[1];
        address poolOutTokenIn = isInverse ? _pool.tokens(0) : _pool.tokens(1);

        _pool.reprice();
        (tokenAmounts[1], fees[1]) = _pool.getTokenAmountOut(poolOutTokenIn, protocolAmounts[1]);

        _approveAssets(
            IERC20Modified(poolOutTokenIn),
            protocolAmounts[1],
            address(this),
            address(this)
        );
        (tokenAmounts[1], ) = _pool.swapExactAmountIn(
            poolOutTokenIn,
            protocolAmounts[1],
            _tokens[1],
            tokenAmounts[1],
            address(this),
            true
        );

        require(
            protocolAmounts[1] + tokenAmounts[1] >= _amounts[1],
            "VolmexController: Insufficient expected volatility amount"
        );

        _transferAsset(
            IERC20Modified(_tokens[1]),
            protocolAmounts[1] + tokenAmounts[1],
            msg.sender
        );
        if (tokenAmounts[3] > 0) {
            _pool = pools[_indices[0]];
            _transferAsset(
                IERC20Modified(_pool.tokens(1) == _tokens[0] ? _pool.tokens(0) : _pool.tokens(1)),
                tokenAmounts[3],
                msg.sender
            );
        }

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
     * @notice Used to swap the exact amount in
     *
     * @param _poolIndex Index of the pool to which interact
     * @param _tokenIn Address of the token in
     * @param _amountIn Value of token amount in to swap
     * @param _tokenOut Address of the token out
     * @param _minAmountOut Minimum expected value of token amount out
     */
    function swap(
        uint256 _poolIndex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _minAmountOut
    ) external whenNotPaused {
        IVolmexPool _pool = pools[_poolIndex];

        _pool.swapExactAmountIn(_tokenIn, _amountIn, _tokenOut, _minAmountOut, msg.sender, false);
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
        require(isPool[msg.sender], "VolmexController: Caller is not pool");
        _token.transferFrom(_account, msg.sender, _amount);
    }

    function _transferAsset(
        IERC20Modified _token,
        uint256 _amount,
        address _receiver
    ) private {
        _token.transfer(_receiver, _amount);
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
}
