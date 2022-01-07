// @ts-nocheck
const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';

interface IProtocols {
    ETHV2xDAI: string | any;
    ETHV2xUSDC: string | any;
    BTCV2xDAI: string | any;
    BTCV2xUSDC: string | any;
}

interface IVolatility {
    ETH2x: string | any;
    BTC2x: string | any;
}

interface IProtocols2 {
    ETHV5xDAI: string | any;
    ETHV5xUSDC: string | any;
    BTCV5xDAI: string | any;
    BTCV5xUSDC: string | any;
}

interface IVolatility2 {
    ETH5x: string | any;
    BTC5x: string | any;
}

interface ICollaterals {
    DAI: string | any;
    USDC: string | any;
}

describe('VolmexController', function () {
    let accounts: Signer[];
    let owner: string;
    let volmexOracleFactory: any;
    let volmexOracle: any;
    let repricerFactory: any;
    let repricer: any;
    let poolFactory: any;
    let pools: IVolatility;
    let pools2: IVolatility2;
    let protocolFactory: any;
    let protocolFactoryPrecision: any;
    let protocols: IProtocols;
    let protocols2: IProtocols2
    let collateralFactory: any;
    let collateral: ICollaterals;
    let volatilityFactory: any;
    let volatilities: IVolatility;
    let volatilities2: IVolatility2;
    let inverseVolatilities: IVolatility;
    let inverseVolatilities2: IVolatility2;
    let controllerFactory: any;
    let controller: any;
    let controller2: any;
    let poolViewFactory: any;
    let poolView: any;

    const collaterals = ['DAI', 'USDC'];
    const volatilitys = ['ETH2x', 'BTC2x'];
    const volatilitys2 = ['ETH5x', 'BTC5x'];

    this.beforeAll(async function () {
        accounts = await ethers.getSigners();

        repricerFactory = await ethers.getContractFactory('VolmexRepricer');

        volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');

        poolFactory = await ethers.getContractFactory('VolmexPoolMock');

        collateralFactory = await ethers.getContractFactory('TestCollateralToken');

        volatilityFactory = await ethers.getContractFactory('VolmexPositionToken');

        protocolFactory = await ethers.getContractFactory('VolmexProtocol');

        protocolFactoryPrecision = await ethers.getContractFactory('VolmexProtocolWithPrecision');

        controllerFactory = await ethers.getContractFactory('VolmexController');

        poolViewFactory = await ethers.getContractFactory('VolmexPoolView');
    });

    describe('2x and 5x leverage', () => {
        this.beforeEach(async () => {
            await upgrades.silenceWarnings();
            protocols = {
                ETH2xVDAI: '',
                ETH2xVUSDC: '',
                BTC2xVDAI: '',
                BTC2xVUSDC: '',
            };
            collateral = {
                DAI: '',
                USDC: '',
            };
            volatilities = {
                ETH2x: '',
                BTC2x: '',
            };

            inverseVolatilities = {
                ETH2x: '',
                BTC2x: '',
            };

            pools = {
                ETH2x: '',
                BTC2x: '',
            };
            protocols2 = {
                ETH5xVDAI: '',
                ETH5xVUSDC: '',
                BTC5xVDAI: '',
                BTC5xVUSDC: '',
            };
            volatilities2 = {
                ETH5x: '',
                BTC5x: '',
            };

            inverseVolatilities2 = {
                ETH5x: '',
                BTC5x: '',
            };

            pools2 = {
                ETH5x: '',
                BTC5x: '',
            };
            for (let col of collaterals) {
                const initSupply =
                    col == 'DAI' ? '100000000000000000000000000000000' : '100000000000000000000';
                const decimals = col == 'DAI' ? 18 : 6;
                collateral[col] = await collateralFactory.deploy(col, initSupply, decimals);
                await collateral[col].deployed();
            }

            for (let vol of volatilitys) {
                volatilities[vol] = await volatilityFactory.deploy();
                await volatilities[vol].deployed();
                await (await volatilities[vol].initialize(`${vol} Volatility Index`, `${vol}V`)).wait();
                inverseVolatilities[vol] = await volatilityFactory.deploy();
                await inverseVolatilities[vol].deployed();
                await (
                    await inverseVolatilities[vol].initialize(`Inverse ${vol} Volatility Index`, `i${vol}V`)
                ).wait();

                const type = `${vol}V${collaterals[0]}`;
                protocols[type] = await upgrades.deployProxy(protocolFactory, [
                    `${collateral[collaterals[0]].address}`,
                    `${volatilities[vol].address}`,
                    `${inverseVolatilities[vol].address}`,
                    '25000000000000000000',
                    '125',
                ]);
                await protocols[type].deployed();
                await (await protocols[type].updateFees('10', '30')).wait();

                const VOLMEX_PROTOCOL_ROLE =
                    '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

                await (
                    await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)
                ).wait();
                await (
                    await inverseVolatilities[vol].grantRole(
                        VOLMEX_PROTOCOL_ROLE,
                        `${protocols[type].address}`
                    )
                ).wait();
            }
            for (let vol of volatilitys2) {
                volatilities2[vol] = await volatilityFactory.deploy();
                await volatilities2[vol].deployed();
                await (await volatilities2[vol].initialize(`${vol} Volatility Index`, `${vol}V`)).wait();
                inverseVolatilities2[vol] = await volatilityFactory.deploy();
                await inverseVolatilities2[vol].deployed();
                await (
                    await inverseVolatilities2[vol].initialize(`Inverse ${vol} Volatility Index`, `i${vol}V`)
                ).wait();

                const type = `${vol}V${collaterals[0]}`;
                protocols2[type] = await upgrades.deployProxy(protocolFactory, [
                    `${collateral[collaterals[0]].address}`,
                    `${volatilities2[vol].address}`,
                    `${inverseVolatilities2[vol].address}`,
                    '25000000000000000000',
                    '50',
                ]);
                await protocols2[type].deployed();
                await (await protocols2[type].updateFees('10', '30')).wait();

                const VOLMEX_PROTOCOL_ROLE =
                    '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

                await (
                    await volatilities2[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols2[type].address}`)
                ).wait();
                await (
                    await inverseVolatilities2[vol].grantRole(
                        VOLMEX_PROTOCOL_ROLE,
                        `${protocols2[type].address}`
                    )
                ).wait();
            }

            for (let vol of volatilitys) {
                const type = `${vol}V${collaterals[1]}`;

                protocols[type] = await upgrades.deployProxy(
                    protocolFactoryPrecision,
                    [
                        `${collateral[collaterals[1]].address}`,
                        `${volatilities[vol].address}`,
                        `${inverseVolatilities[vol].address}`,
                        '25000000',
                        '125',
                        '1000000000000',
                    ],
                    {
                        initializer: 'initializePrecision',
                    }
                );
                await protocols[type].deployed();
                await (await protocols[type].updateFees('10', '30')).wait();
                const VOLMEX_PROTOCOL_ROLE =
                    '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

                await (
                    await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)
                ).wait();
                await (
                    await inverseVolatilities[vol].grantRole(
                        VOLMEX_PROTOCOL_ROLE,
                        `${protocols[type].address}`
                    )
                ).wait();
            }
            for (let vol of volatilitys2) {
                const type = `${vol}V${collaterals[1]}`;

                protocols2[type] = await upgrades.deployProxy(
                    protocolFactoryPrecision,
                    [
                        `${collateral[collaterals[1]].address}`,
                        `${volatilities2[vol].address}`,
                        `${inverseVolatilities2[vol].address}`,
                        '25000000',
                        '50',
                        '1000000000000',
                    ],
                    {
                        initializer: 'initializePrecision',
                    }
                );
                await protocols2[type].deployed();
                await (await protocols2[type].updateFees('10', '30')).wait();
                const VOLMEX_PROTOCOL_ROLE =
                    '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

                await (
                    await volatilities2[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols2[type].address}`)
                ).wait();
                await (
                    await inverseVolatilities2[vol].grantRole(
                        VOLMEX_PROTOCOL_ROLE,
                        `${protocols2[type].address}`
                    )
                ).wait();
            }


            volmexOracle = await upgrades.deployProxy(volmexOracleFactory, []);
            await volmexOracle.deployed();

            repricer = await upgrades.deployProxy(repricerFactory, [volmexOracle.address]);
            await repricer.deployed();

            const baseFee = (0.02 * Math.pow(10, 18)).toString();
            const maxFee = (0.4 * Math.pow(10, 18)).toString();
            const feeAmpPrimary = 10;
            const feeAmpComplement = 10;
            owner = await accounts[0].getAddress();

            const qMin = (1 * Math.pow(10, 6)).toString();
            const pMin = (0.01 * Math.pow(10, 18)).toString();
            const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
            const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
            const leveragePrimary = '999996478162223000';
            const leverageComplement = '1000003521850180000';
            const MAX = '100000000000000000000000000000000';

            for (let vol of volatilitys) {
                const type = `${vol}V${collaterals[0]}`;

                pools[vol] = await upgrades.deployProxy(
                    poolFactory,
                    [
                        repricer.address,
                        protocols[type].address,
                        volatilitys.indexOf(vol),
                        baseFee,
                        maxFee,
                        feeAmpPrimary,
                        feeAmpComplement,
                    ],
                    {
                        initializer: 'initialize',
                    }
                );
                await pools[vol].deployed();

                await (await pools[vol].setControllerWithoutCheck(owner)).wait();

                await (await collateral['DAI'].mint(owner, MAX)).wait();
                await (await collateral['DAI'].approve(protocols[type].address, MAX)).wait();
                await (await protocols[type].collateralize(MAX)).wait();

                await (await volatilities[vol].approve(pools[vol].address, '1000000000000000000')).wait();
                await (
                    await inverseVolatilities[vol].approve(pools[vol].address, '1000000000000000000')
                ).wait();

                await (
                    await pools[vol].finalize(
                        '1000000000000000000',
                        leveragePrimary,
                        '1000000000000000000',
                        leverageComplement,
                        exposureLimitPrimary,
                        exposureLimitComplement,
                        pMin,
                        qMin
                    )
                ).wait();
            }
            for (let vol of volatilitys2) {
                const type = `${vol}V${collaterals[0]}`;

                pools2[vol] = await upgrades.deployProxy(
                    poolFactory,
                    [
                        repricer.address,
                        protocols2[type].address,
                        volatilitys2.indexOf(vol),
                        baseFee,
                        maxFee,
                        feeAmpPrimary,
                        feeAmpComplement,
                    ],
                    {
                        initializer: 'initialize',
                    }
                );
                await pools2[vol].deployed();

                await (await pools2[vol].setControllerWithoutCheck(owner)).wait();

                await (await collateral['DAI'].mint(owner, MAX)).wait();
                await (await collateral['DAI'].approve(protocols2[type].address, MAX)).wait();
                await (await protocols2[type].collateralize(MAX)).wait();

                await (await volatilities2[vol].approve(pools2[vol].address, '1000000000000000000')).wait();
                await (
                    await inverseVolatilities2[vol].approve(pools2[vol].address, '1000000000000000000')
                ).wait();

                await (
                    await pools2[vol].finalize(
                        '1000000000000000000',
                        leveragePrimary,
                        '1000000000000000000',
                        leverageComplement,
                        exposureLimitPrimary,
                        exposureLimitComplement,
                        pMin,
                        qMin
                    )
                ).wait();
            }

            let controllerParam = {
                collaterals: [],
                pools: [],
                protocols: [],
            };
            Object.values(collateral).forEach((coll) => {
                controllerParam.collaterals.push(coll.address);
            });
            Object.values(pools).forEach((pool) => {
                controllerParam.pools.push(pool.address);
            });
            Object.values(protocols).forEach((protocol) => {
                controllerParam.protocols.push(protocol.address);
            });

            controller = await upgrades.deployProxy(controllerFactory, [
                controllerParam.collaterals,
                controllerParam.pools,
                controllerParam.protocols,
                volmexOracle.address,
            ]);
            await controller.deployed();
            await (await pools['ETH2x'].setController(controller.address)).wait();
            await (await pools['BTC2x'].setController(controller.address)).wait();
            let controllerParam = {
                collaterals: [],
                pools2: [],
                protocols2: [],
            };
            Object.values(collateral).forEach((coll) => {
                controllerParam.collaterals.push(coll.address);
            });
            Object.values(pools2).forEach((pool) => {
                controllerParam.pools2.push(pool.address);
            });
            Object.values(protocols2).forEach((protocol) => {
                controllerParam.protocols2.push(protocol.address);
            });

            controller2 = await upgrades.deployProxy(controllerFactory, [
                controllerParam.collaterals,
                controllerParam.pools2,
                controllerParam.protocols2,
                volmexOracle.address,
            ]);
            await controller2.deployed();
            await (await pools2['ETH5x'].setController(controller2.address)).wait();
            await (await pools2['BTC5x'].setController(controller2.address)).wait();

            poolView = await upgrades.deployProxy(poolViewFactory, []);
            await poolView.deployed();
        });
        it('Should swap volatility tokens (2x)', async () => {
            await (
                await volatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            const add = await controller.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();
            const amountOut = await pools['ETH2x'].getTokenAmountOut(
                volatilities['ETH2x'].address,
                '20000000000000000000'
            );
            await (await volatilities['ETH2x'].approve(controller.address, '20000000000000000000')).wait();

            const balanceBefore = await inverseVolatilities['ETH2x'].balanceOf(owner);
            const swap = await controller.swap(
                0,
                volatilities['ETH2x'].address,
                '20000000000000000000',
                inverseVolatilities['ETH2x'].address,
                amountOut[0].toString()
            );
            await swap.wait();

            const balanceAfter = await inverseVolatilities['ETH2x'].balanceOf(owner);

            const changedBalance = balanceAfter.sub(balanceBefore);

            expect(Number(changedBalance.toString())).to.equal(Number(amountOut[0].toString()));
        });

        it('Should swap collateral to volatility (2x)', async () => {
            await (
                await volatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();

            const add = await controller.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();

            const volAmount = await controller.getCollateralToVolatility(
                '1500000000000000000000',
                volatilities['ETH2x'].address,
                [0, 0]
            );

            await (await collateral['DAI'].approve(controller.address, '1500000000000000000000')).wait();
            const balanceBefore = await volatilities['ETH2x'].balanceOf(owner);

            const swap = await controller.swapCollateralToVolatility(
                ['1500000000000000000000', volAmount[0].toString()],
                volatilities['ETH2x'].address,
                [0, 0]
            );
            const { events } = await swap.wait();
            const balanceAfter = await volatilities['ETH2x'].balanceOf(owner);

            const logData = getEventLog(events, 'CollateralSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
            ]);

            const changedAmount = balanceAfter.sub(balanceBefore);

            expect(Number(changedAmount.toString())).to.equal(Number(logData[1].toString()));
        });

        it('Should swap volatility to collateral (2x)', async () => {
            await (
                await volatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();

            const add = await controller.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();

            await (await pools['ETH2x'].reprice()).wait();
            const colAmount = await controller.getVolatilityToCollateral(
                volatilities['ETH2x'].address,
                '20000000000000000000',
                [0, 0],
                false
            );

            await (await volatilities['ETH2x'].approve(controller.address, '20000000000000000000')).wait();
            const collateralBefore = await collateral['DAI'].balanceOf(owner);

            const swap = await controller.swapVolatilityToCollateral(
                ['20000000000000000000', colAmount[0].toString()],
                ['0', '0'],
                volatilities['ETH2x'].address
            );
            const { events } = await swap.wait();
            const collateralAfter = await collateral['DAI'].balanceOf(owner);

            const changedBalance = collateralAfter.sub(collateralBefore);

            const logData = getEventLog(events, 'CollateralSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
            ]);

            expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
        });

        it('Should swap between multiple pools (2x)', async () => {
            await (
                await volatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities['ETH2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();

            const addEth = await controller.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await addEth.wait();

            await (
                await volatilities['BTC2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities['BTC2x'].approve(controller.address, '599999999000000000000000000')
            ).wait();

            const addBtc = await controller.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '1'
            );
            await addBtc.wait();

            await (await pools['ETH2x'].reprice()).wait();
            await (await pools['BTC2x'].reprice()).wait();
            const volAmountOut = await controller.getSwapAmountBetweenPools(
                [volatilities['ETH2x'].address, volatilities['BTC2x'].address],
                '20000000000000000000',
                [0, 1, 0]
            );

            await (await volatilities['ETH2x'].approve(controller.address, '20000000000000000000')).wait();

            const balanceBefore = await volatilities['BTC2x'].balanceOf(owner);
            const swap = await controller.swapBetweenPools(
                [volatilities['ETH2x'].address, volatilities['BTC2x'].address],
                ['20000000000000000000', volAmountOut[0].toString()],
                [0, 1, 0]
            );
            const { events } = await swap.wait();
            const logData = getEventLog(events, 'PoolSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
                'address',
            ]);
            const balanceAfter = await volatilities['BTC2x'].balanceOf(owner);

            const changedBalance = balanceAfter.sub(balanceBefore);

            expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
        });
        it('Should swap volatility tokens (5x)', async () => {
            await (
                await volatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            const add = await controller2.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();
            const amountOut = await pools2['ETH5x'].getTokenAmountOut(
                volatilities2['ETH5x'].address,
                '20000000000000000000'
            );
            await (await volatilities2['ETH5x'].approve(controller2.address, '20000000000000000000')).wait();

            const balanceBefore = await inverseVolatilities2['ETH5x'].balanceOf(owner);
            const swap = await controller2.swap(
                0,
                volatilities2['ETH5x'].address,
                '20000000000000000000',
                inverseVolatilities2['ETH5x'].address,
                amountOut[0].toString()
            );
            await swap.wait();

            const balanceAfter = await inverseVolatilities2['ETH5x'].balanceOf(owner);

            const changedBalance = balanceAfter.sub(balanceBefore);

            expect(Number(changedBalance.toString())).to.equal(Number(amountOut[0].toString()));
        });

        it('Should swap collateral to volatility (5x)', async () => {
            await (
                await volatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();

            const add = await controller2.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();

            const volAmount = await controller2.getCollateralToVolatility(
                '1500000000000000000000',
                volatilities2['ETH5x'].address,
                [0, 0]
            );

            await (await collateral['DAI'].approve(controller2.address, '1500000000000000000000')).wait();
            const balanceBefore = await volatilities2['ETH5x'].balanceOf(owner);

            const swap = await controller2.swapCollateralToVolatility(
                ['1500000000000000000000', volAmount[0].toString()],
                volatilities2['ETH5x'].address,
                [0, 0]
            );
            const { events } = await swap.wait();
            const balanceAfter = await volatilities2['ETH5x'].balanceOf(owner);

            const logData = getEventLog(events, 'CollateralSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
            ]);

            const changedAmount = balanceAfter.sub(balanceBefore);

            expect(Number(changedAmount.toString())).to.equal(Number(logData[1].toString()));
        });

        it('Should swap volatility to collateral (5x)', async () => {
            await (
                await volatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();

            const add = await controller2.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await add.wait();

            await (await pools2['ETH5x'].reprice()).wait();
            const colAmount = await controller2.getVolatilityToCollateral(
                volatilities2['ETH5x'].address,
                '20000000000000000000',
                [0, 0],
                false
            );

            await (await volatilities2['ETH5x'].approve(controller2.address, '20000000000000000000')).wait();
            const collateralBefore = await collateral['DAI'].balanceOf(owner);

            const swap = await controller2.swapVolatilityToCollateral(
                ['20000000000000000000', colAmount[0].toString()],
                ['0', '0'],
                volatilities2['ETH5x'].address
            );
            const { events } = await swap.wait();
            const collateralAfter = await collateral['DAI'].balanceOf(owner);

            const changedBalance = collateralAfter.sub(collateralBefore);

            const logData = getEventLog(events, 'CollateralSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
            ]);

            expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
        });

        it('Should swap between multiple pools (5x)', async () => {
            await (
                await volatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities2['ETH5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();

            const addEth = await controller2.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '0'
            );
            await addEth.wait();

            await (
                await volatilities2['BTC5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();
            await (
                await inverseVolatilities2['BTC5x'].approve(controller2.address, '599999999000000000000000000')
            ).wait();

            const addBtc = await controller2.addLiquidity(
                '250000000000000000000000000',
                ['599999999000000000000000000', '599999999000000000000000000'],
                '1'
            );
            await addBtc.wait();

            await (await pools2['ETH5x'].reprice()).wait();
            await (await pools2['BTC5x'].reprice()).wait();
            const volAmountOut = await controller2.getSwapAmountBetweenPools(
                [volatilities2['ETH5x'].address, volatilities2['BTC5x'].address],
                '20000000000000000000',
                [0, 1, 0]
            );

            await (await volatilities2['ETH5x'].approve(controller2.address, '20000000000000000000')).wait();

            const balanceBefore = await volatilities2['BTC5x'].balanceOf(owner);
            const swap = await controller2.swapBetweenPools(
                [volatilities2['ETH5x'].address, volatilities2['BTC5x'].address],
                ['20000000000000000000', volAmountOut[0].toString()],
                [0, 1, 0]
            );
            const { events } = await swap.wait();
            const logData = getEventLog(events, 'PoolSwapped', [
                'uint256',
                'uint256',
                'uint256',
                'uint256',
                'address',
            ]);
            const balanceAfter = await volatilities2['BTC5x'].balanceOf(owner);

            const changedBalance = balanceAfter.sub(balanceBefore);

            expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
        });
    });
})
const getEventLog = (events: any[], eventName: string, params: string[]): any => {
    let data;
    events.forEach((log: any) => {
        if (log['event'] == eventName) {
            data = log['data'];
        }
    });
    const logData = ethers.utils.defaultAbiCoder.decode(params, data);
    return logData;
};
