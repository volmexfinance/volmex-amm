// SPDX-License-Identifier: BUSL-1.1

pragma solidity =0.8.11;
pragma abicoder v2;

import '@openzeppelin/contracts-upgradeable/utils/introspection/ERC165StorageUpgradeable.sol';

import './maths/Math.sol';
import './interfaces/IVolmexPool.sol';
import './interfaces/IERC20Modified.sol';
import './interfaces/IVolmexPoolView.sol';
import './interfaces/IPausablePool.sol';

/**
 * @title Reading key data from specified derivative trading Pool
 */
contract VolmexPoolView is ERC165StorageUpgradeable, Math, IVolmexPoolView {
    // Interface ID of VolmexPoolView contract, hashId = 0x45ea1e36
    bytes4 private constant _IVOLMEX_POOLVIEW_ID = type(IVolmexPoolView).interfaceId;

    function initialize() external initializer {
        __ERC165Storage_init();
        _registerInterface(_IVOLMEX_POOLVIEW_ID);
    }

    /**
     * @notice Getting information about Pool configuration, it's derivative and pool(LP) tokens
     * @param _pool the vault address
     * @return primary pool's primary token metadata
     * @return complement pool' complement token metadata
     * @return poolToken pool's own token metadata
     * @return config pool configuration
     */
    function getPoolInfo(address _pool, address _sender)
        external
        view
        returns (
            TokenRecord memory primary,
            TokenRecord memory complement,
            TokenData memory poolToken,
            Config memory config
        )
    {
        IVolmexPool pool = IVolmexPool(_pool);

        address _primaryAddress = address(pool.protocol().volatilityToken());
        primary = TokenRecord(
            _primaryAddress,
            pool.getBalance(_primaryAddress),
            pool.getLeverage(_primaryAddress),
            IERC20Modified(_primaryAddress).decimals(),
            _sender == address(0) ? 0 : IERC20(_primaryAddress).balanceOf(_sender)
        );

        address _complementAddress = address(pool.protocol().inverseVolatilityToken());
        complement = TokenRecord(
            _complementAddress,
            pool.getBalance(_complementAddress),
            pool.getLeverage(_complementAddress),
            IERC20Modified(_complementAddress).decimals(),
            _sender == address(0) ? 0 : IERC20(_complementAddress).balanceOf(_sender)
        );

        poolToken = TokenData(
            _pool,
            pool.totalSupply(),
            IERC20Modified(_pool).decimals(),
            _sender == address(0) ? 0 : IERC20(_pool).balanceOf(_sender)
        );

        config = Config(
            address(pool.protocol()),
            address(pool.repricer()),
            IPausablePool(address(pool)).paused(),
            IERC20Modified(_primaryAddress).decimals(),
            IERC20Modified(_pool).decimals(),
            pool.exposureLimitPrimary(),
            pool.exposureLimitComplement(),
            pool.pMin(),
            pool.qMin(),
            pool.baseFee(),
            pool.maxFee(),
            pool.feeAmpPrimary(),
            pool.feeAmpComplement()
        );
    }

    /**
     * @notice Getting current state of Pool, token balances and leverages, LP token supply
     * @param _pool vault address
     * @return primary pool's primary token address
     * @return primaryBalance pool's primary token balance
     * @return primaryLeverage pool's primary token leverage
     * @return primaryDecimals pool's primary token decimals
     * @return complement pool's complement token address
     * @return complementBalance pool's complement token balance
     * @return complementLeverage pool's complement token leverage
     * @return complementDecimals pool's complement token decimals
     * @return lpTotalSupply pool's LP token total supply
     * @return lpDecimals pool's LP token decimals
     */
    function getPoolTokenData(address _pool)
        external
        view
        returns (
            address primary,
            uint256 primaryBalance,
            uint256 primaryLeverage,
            uint8 primaryDecimals,
            address complement,
            uint256 complementBalance,
            uint256 complementLeverage,
            uint8 complementDecimals,
            uint256 lpTotalSupply,
            uint8 lpDecimals
        )
    {
        IVolmexPool pool = IVolmexPool(_pool);

        primary = address(pool.protocol().volatilityToken());
        complement = address(pool.protocol().inverseVolatilityToken());

        primaryBalance = pool.getBalance(primary);
        primaryLeverage = pool.getLeverage(primary);
        primaryDecimals = IERC20Modified(primary).decimals();

        complementBalance = pool.getBalance(complement);
        complementLeverage = pool.getLeverage(complement);
        complementDecimals = IERC20Modified(complement).decimals();

        lpTotalSupply = pool.totalSupply();
        lpDecimals = IERC20Modified(_pool).decimals();
    }

    /**
     * @notice Getting Pool configuration only to reduce data loading time
     */
    function getPoolConfig(address _pool)
        external
        view
        returns (
            address protocol,
            address repricer,
            uint256 exposureLimitPrimary,
            uint256 exposureLimitComplement,
            uint256 pMin,
            uint256 qMin,
            uint256 baseFee,
            uint256 maxFee,
            uint256 feeAmpPrimary,
            uint256 feeAmpComplement
        )
    {
        IVolmexPool pool = IVolmexPool(_pool);
        protocol = address(pool.protocol());
        repricer = address(pool.repricer());
        pMin = pool.pMin();
        qMin = pool.qMin();
        exposureLimitPrimary = pool.exposureLimitPrimary();
        exposureLimitComplement = pool.exposureLimitComplement();
        baseFee = pool.baseFee();
        feeAmpPrimary = pool.feeAmpPrimary();
        feeAmpComplement = pool.feeAmpComplement();
        maxFee = pool.maxFee();
    }

    function getTokensToJoin(IVolmexPool _pool, uint256 _poolAmountOut)
        external
        view
        returns (uint256[2] memory _maxAmountsIn)
    {
        uint256 ratio = _div(_poolAmountOut, _pool.totalSupply());
        require(ratio != 0, 'VolmexPoolView: Invalid math approximation in join');

        for (uint256 i = 0; i < 2; i++) {
            uint256 bal = _pool.getBalance(_pool.tokens(i));
            _maxAmountsIn[i] = _mul(ratio, bal);
        }
    }

    function getTokensToExit(IVolmexPool _pool, uint256 _poolAmountIn)
        external
        view
        returns (uint256[2] memory _minAmountsOut)
    {
        uint256 ratio = _div(_poolAmountIn, _pool.totalSupply());
        require(ratio != 0, 'VolmexPoolView: Invalid math approximation in exit');

        uint256 upperBoundary = _pool.upperBoundary();
        uint256 adminFee = _pool.adminFee();
        for (uint256 i = 0; i < 2; i++) {
            uint256 bal = _pool.getBalance(_pool.tokens(i));
            _minAmountsOut[i] = _calculateAmountOut(
                _poolAmountIn,
                ratio,
                bal,
                upperBoundary,
                adminFee
            );
        }
    }

    uint256[10] private __gap;
}
