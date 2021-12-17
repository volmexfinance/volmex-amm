// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.10;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';

import './interfaces/IVolmexAMM.sol';
import './interfaces/IVolmexProtocol.sol';
import './interfaces/IERC20Modified.sol';
import './interfaces/IVolmexOracle.sol';

/**
 * @title Volmex Controller contract
 * @author volmex.finance [security@volmexlabs.com]
 */
contract VolmexController is OwnableUpgradeable {
    event AdminFeeUpdated(uint256 adminFee);

    event AssetSwaped(
        uint256 assetInAmount,
        uint256 assetOutAmount,
        uint256 protocolFee,
        uint256 aMMFee,
        uint256 stableCoinIndex,
        address indexed token
    );

    event AssetBetweemPoolSwapped(
        uint256 assetInAmount,
        uint256 assetOutAmount,
        uint256 protocolFee,
        uint256 aMMFee,
        uint256 stableCoinIndex,
        address[2] tokens
    );

    event SetPool(
        uint256 indexed poolIndex,
        address indexed pool
    );

    event SetStablecoin(
        uint256 indexed stableCoinIndex,
        address indexed stableCoin
    );

    event SetProtocol(
        uint256 poolIndex,
        uint256 stableCoinIndex,
        address indexed protocol
    );

    event UpdatedMinimumCollateral(uint256 newMinimumCollateralQty);

    // Ratio of volatility to be minted per 250 collateral
    uint256 private _volatilityCapRatio;
    // Minimum amount of collateral amount needed to collateralize
    uint256 private _minimumCollateralQty;
    // Used to set the index of stableCoin
    uint256 public stableCoinIndex;
    // Used to set the index of pool
    uint256 public poolIndex;


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

    // Store the addresses of pools
    mapping(uint256 => address) public pools;
    /// @notice We have used IERC20Modified instead of IERC20, because the volatility tokens
    /// can't be typecasted to IERC20.
    /// Note: We have used the standard methods on IERC20 only.
    // Store the addresses of stableCoins
    mapping(uint256 => IERC20Modified) public stableCoins;
    // Store the addresses of protocols { pool index => stableCoin index => protocol address }
    mapping(uint256 => mapping(uint256 => IVolmexProtocol)) public protocols;
    // Store the bool value of pools to confirm it is pool
    mapping(address => bool) public isPool;
    // Address of the oracle
    IVolmexOracle public oracle;
    // Value of token decimal precision 10^18
    uint256 private constant BONE = 1000000000000000000;

    /**
     * @notice Initializes the contract
     *
     * @dev Sets the volatilityCapRatio and _minimumCollateralQty
     *
     * @param _stableCoin Address of the collateral token used in protocol
     * @param _pool Address of the pool contract
     * @param _protocol Address of the protocol contract
     */
    function initialize(
        IERC20Modified _stableCoin,
        address _pool,
        IVolmexProtocol _protocol,
        IVolmexOracle _oracle
    ) external initializer {
        pools[poolIndex] = _pool;
        stableCoins[stableCoinIndex] = _stableCoin;
        protocols[poolIndex][stableCoinIndex] = _protocol;
        oracle = _oracle;

        isPool[_pool] = true;

        _volatilityCapRatio = _protocol.volatilityCapRatio();
        _minimumCollateralQty = _protocol.minimumCollateralQty();
    }

    /**
     * @notice Used to set the pool on new index
     *
     * @param _pool Address of the AMM contract
     */
    function setPool(address _pool) external onlyOwner {
        poolIndex++;
        pools[poolIndex] = _pool;

        emit SetPool(poolIndex, _pool);
    }

    /**
     * @notice Usesd to set the stableCoin on new index
     *
     * @param _stableCoin Address of the stableCoin
     */
    function setStablecoin(IERC20Modified _stableCoin) external onlyOwner {
        stableCoinIndex++;
        stableCoins[stableCoinIndex] = _stableCoin;

        emit SetStablecoin(stableCoinIndex, address(_stableCoin));
    }

    /**
     * @notice Used to set the protocol on a particular pool and stableCoin index
     *
     * @param _protocol Address of the Protocol contract
     */
    function setProtocol(
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        IVolmexProtocol _protocol
    ) external onlyOwner {
        require(
            stableCoins[_stableCoinIndex] == _protocol.collateral(),
            "VolmexController: Incorrect stableCoin for set protocol"
        );
        require(
            IVolmexAMM(pools[_poolIndex]).getPrimaryDerivativeAddress() == address(_protocol.volatilityToken()),
            "VolmexController: Incorrect pool for set protocol"
        );

        protocols[_poolIndex][_stableCoinIndex] = _protocol;

        emit SetProtocol(_poolIndex, _stableCoinIndex, address(_protocol));
    }

    /**
     * @notice Used to update the minimum collateral qty value
     */
    function updateMinCollateralQty(uint256 _minCollateralQty) external onlyOwner {
        _minimumCollateralQty = _minCollateralQty;

        emit UpdatedMinimumCollateral(_minCollateralQty);
    }

    /**
     * @notice Used to swap collateral token to a type of volatility token
     *
     * @dev Amount if transferred to the controller and approved for pool
     * @dev collateralize the amount to get volatility
     * @dev Swaps half the quantity of volatility asset using pool contract
     * @dev Transfers the asset to caller
     *
     * @param _amount Amount of collateral token
     * @param _isInverseRequired Bool value token type required { true: iETHV, false: ETHV }
     * @param _indices Indices of the pool and stablecoin to operate { 0: ETHV, 1: BTCV } { 0: DAI, 1: USDC }
     */
    function swapCollateralToVolatility(
        uint256 _amount,
        bool _isInverseRequired,
        uint256[2] calldata _indices
    ) external {
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[1]];
        IERC20Modified stableCoin = stableCoins[_indices[1]];
        stableCoin.transferFrom(msg.sender, address(this), _amount);
        _approveAssets(stableCoin, _amount, address(this), address(_protocol));

        _protocol.collateralize(_amount);

        // AMM and Protocol fee array { 0: AMM, 1: Protocol }
        uint256[] memory fees = new uint256[](2);
        uint256 volatilityAmount;
        (volatilityAmount, fees[1]) = calculateAssetQuantity(_amount, _protocol.issuanceFees(), true);

        IERC20Modified volatilityToken = _protocol.volatilityToken();
        IERC20Modified inverseVolatilityToken = _protocol.inverseVolatilityToken();

        IVolmexAMM _pool = IVolmexAMM(pools[_indices[0]]);

        uint256 tokenAmountOut;
        if (_isInverseRequired) {
            _approveAssets(volatilityToken, volatilityAmount, address(this), address(_pool));
            (tokenAmountOut, fees[0]) = _pool.swapExactAmountIn(
                address(_protocol.volatilityToken()),
                volatilityAmount,
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount >> 1,
                msg.sender,
                true
            );
        } else {
            _approveAssets(inverseVolatilityToken, volatilityAmount, address(this), address(_pool));
            (tokenAmountOut, fees[0]) = _pool.swapExactAmountIn(
                address(_protocol.inverseVolatilityToken()),
                volatilityAmount,
                address(_protocol.volatilityToken()),
                volatilityAmount >> 1,
                msg.sender,
                true
            );
        }

        uint256 totalVolatilityAmount = volatilityAmount + tokenAmountOut;
        transferAsset(
            _isInverseRequired ? inverseVolatilityToken : volatilityToken,
            totalVolatilityAmount,
            msg.sender
        );

        emit AssetSwaped(
            _amount,
            totalVolatilityAmount,
            fees[1],
            fees[0],
            _indices[1],
            _isInverseRequired ? address(inverseVolatilityToken) : address(volatilityToken)
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
    ) external {
        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[1]];
        IVolmexAMM _pool = IVolmexAMM(pools[_indices[0]]);

        bool isInverse = _pool.getComplementDerivativeAddress() == address(_tokenIn);

        (uint256 swapAmount, uint256 tokenAmountOut,) = _getSwappedAssetAmount(
            address(_tokenIn),
            _amounts[0],
            _pool,
            isInverse
        );

        // AMM and Protocol fee array { 0: AMM, 1: Protocol }
        uint256[] memory fees = new uint256[](2);
        (tokenAmountOut, fees[0]) = _pool.swapExactAmountIn(
            address(_tokenIn),
            swapAmount,
            isInverse ? _pool.getPrimaryDerivativeAddress() : _pool.getComplementDerivativeAddress(),
            tokenAmountOut,
            msg.sender,
            true
        );

        require(tokenAmountOut <= _amounts[0] - swapAmount, 'VolmexController: Amount out limit exploit');

        uint256 collateralAmount;
        (collateralAmount, fees[1]) = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        require(collateralAmount >= _amounts[1], 'VolmexController: Insufficient collateral amount');

        _tokenIn.transferFrom(msg.sender, address(this), tokenAmountOut);
        _protocol.redeem(tokenAmountOut);

        IERC20Modified stableCoin = stableCoins[_indices[1]];
        transferAsset(stableCoin, collateralAmount, msg.sender);

        emit AssetSwaped(
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
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_indices[0]]);

        bool isInverse = _pool.getComplementDerivativeAddress() == _tokens[0];

        // Array of swapAmount {0} and tokenAmountOut {1}
        uint256[] memory tokenAmounts = new uint256[](2);
        (tokenAmounts[0], tokenAmounts[1],) = _getSwappedAssetAmount(
            _tokens[0],
            _amounts[0],
            _pool,
            isInverse
        );

        // AMM and Protocol fee array { 0: AMM-1, 1: AMM-2, 2: Protocol-Redeem, 3: Protocol-Collateralize }
        uint256[] memory fees = new uint256[](4);
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

        require(tokenAmounts[1] <= _amounts[0] - tokenAmounts[0], 'VolmexController: Amount out limit exploit');

        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[2]];
        IERC20Modified(_tokens[0]).transferFrom(msg.sender, address(this), tokenAmounts[1]);
        _protocol.redeem(tokenAmounts[1]);

        // Array of collateralAmount {0} and volatilityAmount {1}
        uint256[] memory protocolAmounts = new uint256[](2);
        (protocolAmounts[0], fees[2]) = calculateAssetQuantity(
            tokenAmounts[1] * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        _protocol = protocols[_indices[1]][_indices[2]];
        _approveAssets(stableCoins[_indices[2]], protocolAmounts[0], address(this), address(_protocol));
        _protocol.collateralize(protocolAmounts[0]);

        (protocolAmounts[1], fees[3]) = calculateAssetQuantity(
            protocolAmounts[0],
            _protocol.issuanceFees(),
            true
        );

        _pool = IVolmexAMM(pools[_indices[1]]);

        isInverse = _pool.getPrimaryDerivativeAddress() != _tokens[1];
        address poolOutTokenIn = isInverse ? _pool.getPrimaryDerivativeAddress() : _pool.getComplementDerivativeAddress();

        (tokenAmounts[1], ) = _pool.getTokenAmountOut(poolOutTokenIn, protocolAmounts[1], _tokens[1]);

        (tokenAmounts[1], fees[1]) = _pool.swapExactAmountIn(
            poolOutTokenIn,
            protocolAmounts[1],
            _tokens[1],
            tokenAmounts[1],
            msg.sender,
            true
        );

        require(protocolAmounts[1] + tokenAmounts[1] >= _amounts[1], 'VolmexController: Volatility amount below expectation');

        transferAsset(IERC20Modified(_tokens[1]), protocolAmounts[1] + tokenAmounts[1], msg.sender);

        emit AssetBetweemPoolSwapped(
            _amounts[0],
            protocolAmounts[1] + tokenAmounts[1],
            fees[2] + fees[3],
            fees[0] + fees[1],
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
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

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
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        _pool.exitPool(_poolAmountIn, _minAmountsOut, msg.sender);
    }

    /**
     * @notice Used to call flash loan on AMM
     *
     * @dev This method is for developers.
     * Make sure you call this metehod from a contract with the implementation
     * of IFlashLoanReceiver interface
     *
     * @param _assetToken Address of the token in need
     * @param _amount Amount of token in need
     * @param _params msg.data for verifying the loan
     * @param _poolIndex Index of the AMM
     */
    function makeFlashLoan(
        address _assetToken,
        uint256 _amount,
        bytes calldata _params,
        uint256 _poolIndex
    ) external {
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);
        _pool.flashLoan(
            msg.sender,
            _assetToken,
            _amount,
            _params
        );
    }

    function swap(
        uint256 _poolIndex,
        address _tokenIn,
        uint256 _amountIn,
        address _tokenOut,
        uint256 _amountOut
    ) external {
        IVolmexAMM _amm = IVolmexAMM(pools[_poolIndex]);

        _amm.swapExactAmountIn(
            _tokenIn,
            _amountIn,
            _tokenOut,
            _amountOut,
            msg.sender,
            false
        );
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
    function getSwappedAssetAmount(
        address _tokenIn,
        uint256 _amount,
        uint256 _poolIndex,
        uint256 _stableCoinIndex,
        bool _isInverse
    ) external view returns (uint256 collateralAmount, uint256[2] memory fees, uint256 leftOverAmount) {
        IVolmexProtocol _protocol = protocols[_poolIndex][_stableCoinIndex];
        IVolmexAMM _pool = IVolmexAMM(pools[_poolIndex]);

        uint256 swapAmount;
        uint256 tokenAmountOut;
        uint256 aMMFee;
        uint256 protocolFee;
        (swapAmount, tokenAmountOut, aMMFee) = _getSwappedAssetAmount(
            _tokenIn,
            _amount,
            _pool,
            _isInverse
        );

        (collateralAmount, protocolFee) = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );

        leftOverAmount = _amount - swapAmount - tokenAmountOut;
        fees = [aMMFee, protocolFee];
    }

    /**
     * @notice Used to get the token out amount of swap in between multiple pools
     *
     * @param _tokens Addresses of token in and out
     * @param _amountIn Value of amount in or change
     * @param _indices Array of indices of poolOut, poolIn and stable coin
     *
     * returns amountOut, and fees array {0: aMMFee, 1: protocolFee}
     */
    function getSwapAmountBetweenPools(
        address[] calldata _tokens,
        uint256 _amountIn,
        uint256[] calldata _indices
    ) external view returns (uint256 amountOut, uint256[2] memory fees) {
        IVolmexAMM _pool = IVolmexAMM(pools[_indices[0]]);

        uint256 tokenAmountOut;
        uint256 fee;
        (, tokenAmountOut, fee) = _getSwappedAssetAmount(
            _tokens[0],
            _amountIn,
            _pool,
            _pool.getComplementDerivativeAddress() == _tokens[0]
        );
        fees[0] += fee;

        IVolmexProtocol _protocol = protocols[_indices[0]][_indices[2]];
        uint256[] memory protocolAmount = new uint256[](2);
        (protocolAmount[0], fee) = calculateAssetQuantity(
            tokenAmountOut * _volatilityCapRatio,
            _protocol.redeemFees(),
            false
        );
        fees[1] += fee;

        _protocol = protocols[_indices[1]][_indices[2]];

        (protocolAmount[1], fee) = calculateAssetQuantity(
            protocolAmount[0],
            _protocol.issuanceFees(),
            true
        );
        fees[1] += fee;

        _pool = IVolmexAMM(pools[_indices[1]]);

        (tokenAmountOut, fee) = _pool.getTokenAmountOut(
            _pool.getPrimaryDerivativeAddress() != _tokens[1]
                ? _pool.getPrimaryDerivativeAddress()
                : _pool.getComplementDerivativeAddress(),
            protocolAmount[1],
            _tokens[1]);
        fees[0] += fee;

        amountOut = protocolAmount[1] + tokenAmountOut;
    }

    //solium-disable-next-line security/no-assign-params
    function calculateAssetQuantity(
        uint256 _amount,
        uint256 _feePercent,
        bool _isVolatility
    ) internal view returns (uint256 amount, uint256 protocolFee) {
        protocolFee = (_amount * _feePercent) / 10000;
        _amount = _amount - protocolFee;

        amount = _isVolatility ? _amount / _volatilityCapRatio : _amount;
    }

    function transferAsset(IERC20Modified _token, uint256 _amount, address receiver) internal {
        _token.transfer(receiver, _amount);
    }

    function _approveAssets(
        IERC20Modified _token,
        uint256 _amount,
        address _owner,
        address _spender
    ) internal {
        uint256 _allowance = _token.allowance(_owner, _spender);

        if (_amount <= _allowance) return;

        _token.approve(_spender, _amount);
    }

    function transferAssetToPool(
        IERC20Modified _token,
        address _account,
        uint256 _amount
    ) external {
        require(isPool[msg.sender], 'VolmexController: Caller is not pool');
        _token.transferFrom(_account, msg.sender, _amount);
    }

    function _volatilityAmountToSwap(
        uint256 _amount,
        IVolmexAMM _pool,
        bool _isInverse,
        uint256 _fee
    ) internal view returns (uint256 volatilityAmount) {
        uint256 price = oracle.volatilityTokenPriceByIndex(_pool.volatilityIndex());
        uint256 iPrice = (_volatilityCapRatio * 10000) - price;

        uint256 leverage = _pool.getLeverage(_pool.getPrimaryDerivativeAddress());
        uint256 iLeverage = _pool.getLeverage(_pool.getComplementDerivativeAddress());

        volatilityAmount = !_isInverse ?
            ((_amount * iPrice * iLeverage) * BONE) / (price * leverage * (BONE - _fee) + iPrice * iLeverage * BONE) :
            ((_amount * price * leverage) * BONE) / (iPrice * iLeverage * (BONE - _fee) + price * leverage * BONE);
    }

    function _getSwappedAssetAmount(
        address _tokenIn,
        uint256 _amount,
        IVolmexAMM _pool,
        bool _isInverse
    ) internal view returns (uint256 swapAmount, uint256 amountOut, uint256 fee) {
        swapAmount = _volatilityAmountToSwap(_amount, _pool, _isInverse, 0);

        (, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount,
            _pool.getPrimaryDerivativeAddress() == _tokenIn ?
                _pool.getComplementDerivativeAddress() : _pool.getPrimaryDerivativeAddress()
        );

        swapAmount = _volatilityAmountToSwap(_amount, _pool, _isInverse, fee);

        (amountOut, fee) = _pool.getTokenAmountOut(
            _tokenIn,
            swapAmount,
            _pool.getPrimaryDerivativeAddress() == _tokenIn ?
                _pool.getComplementDerivativeAddress() : _pool.getPrimaryDerivativeAddress()
        );
    }
}
