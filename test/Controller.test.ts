
// @ts-nocheck
const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';
const { expectRevert, time } = require('@openzeppelin/test-helpers');

interface IProtocols {
  ETHVDAI: string | any;
  ETHVUSDC: string | any;
  BTCVDAI: string | any;
  BTCVUSDC: string | any;
}

interface IVolatility {
  ETH: string | any;
  BTC: string | any;
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
  let protocolFactory: any;
  let protocolFactoryPrecision: any;
  let protocols: IProtocols;
  let collateralFactory: any;
  let collateral: ICollaterals;
  let volatilityFactory: any;
  let volatilities: IVolatility;
  let inverseVolatilities: IVolatility;
  let controllerFactory: any;
  let controller: any;

  const collaterals = ['DAI', 'USDC'];
  const volatilitys = ['ETH', 'BTC'];

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = await ethers.getContractFactory('VolmexRepricer');

    volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');

    poolFactory = await ethers.getContractFactory('VolmexPool');

    collateralFactory = await ethers.getContractFactory('TestCollateralToken');

    volatilityFactory = await ethers.getContractFactory('VolmexPositionToken');

    protocolFactory = await ethers.getContractFactory('VolmexProtocol');

    protocolFactoryPrecision = await ethers.getContractFactory('VolmexProtocolWithPrecision');

    controllerFactory = await ethers.getContractFactory('VolmexController');
  });

  this.beforeEach(async function () {
    await upgrades.silenceWarnings();
    protocols = {
      ETHVDAI: '',
      ETHVUSDC: '',
      BTCVDAI: '',
      BTCVUSDC: '',
    };

    collateral = {
      DAI: '',
      USDC: '',
    };

    volatilities = {
      ETH: '',
      BTC: '',
    };

    inverseVolatilities = {
      ETH: '',
      BTC: '',
    };

    pools = {
      ETH: '',
      BTC: '',
    };

    for (let col of collaterals) {
      collateral[col] = await collateralFactory.deploy(col);
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
        '250',
      ]);
      await protocols[type].deployed();
      await (await protocols[type].updateFees('10', '30')).wait();

      const VOLMEX_PROTOCOL_ROLE =
        '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

      await (await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)).wait();
      await (await inverseVolatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)).wait();
    }

    for (let vol of volatilitys) {
      const type = `${vol}V${collaterals[1]}`;

      protocols[type] = await upgrades.deployProxy(protocolFactoryPrecision, [
        `${collateral[collaterals[1]].address}`,
        `${volatilities[vol].address}`,
        `${inverseVolatilities[vol].address}`,
        '25000000000000000000',
        '250',
        '1000000000000'
      ],
      {
        initializer: "initializePrecision"
      }
      );
      await protocols[type].deployed();
      await (await protocols[type].updateFees('10', '30')).wait();
      const VOLMEX_PROTOCOL_ROLE =
        '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

      await (await volatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)).wait();
      await (await inverseVolatilities[vol].grantRole(VOLMEX_PROTOCOL_ROLE, `${protocols[type].address}`)).wait();
    }

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, []);
    await volmexOracle.deployed();

    repricer = await upgrades.deployProxy(repricerFactory, [
      volmexOracle.address
    ]);
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

      pools[vol] = await upgrades.deployProxy(poolFactory, [
        repricer.address,
        protocols[type].address,
        volatilitys.indexOf(vol),
        baseFee,
        maxFee,
        feeAmpPrimary,
        feeAmpComplement
      ]);
      await pools[vol].deployed();

      await (await collateral['DAI'].mint(owner, MAX)).wait();
      await (await collateral['DAI'].approve(protocols[type].address, MAX)).wait();
      await (await protocols[type].collateralize(MAX)).wait();
      await (await pools[vol].setController(owner)).wait();

      await (await volatilities[vol].approve(pools[vol].address, "1000000000000000000")).wait();
      await (await inverseVolatilities[vol].approve(pools[vol].address, "1000000000000000000")).wait();

      await (await pools[vol].finalize(
        '1000000000000000000',
        leveragePrimary,
        '1000000000000000000',
        leverageComplement,
        exposureLimitPrimary,
        exposureLimitComplement,
        pMin,
        qMin
      )).wait();
    }

    let controllerParam = {
      collaterals: [],
      pools: [],
      protocols: []
    }
    Object.values(collateral).forEach(coll => {
      controllerParam.collaterals.push(coll.address);
    });
    Object.values(pools).forEach(pool => {
      controllerParam.pools.push(pool.address);
    });
    Object.values(protocols).forEach(protocol => {
      controllerParam.protocols.push(protocol.address);
    });

    controller = await upgrades.deployProxy(controllerFactory, [
      controllerParam.collaterals,
      controllerParam.pools,
      controllerParam.protocols,
      volmexOracle.address
    ]);
    await controller.deployed();

    await (await pools['ETH'].setController(controller.address)).wait();
    await (await pools['BTC'].setController(controller.address)).wait();
  });

  it('should deploy controller', async () => {
    const controllerReceipt = await controller.deployed();
    expect(controllerReceipt.confirmations).not.equal(0);
  });

  it('Should swap collateral to volatility', async () => {
    await (await volatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();
    await (await inverseVolatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();

    const add = await controller.addLiquidity(
      '250000000000000000000000000',
      ['599999999000000000000000000','599999999000000000000000000'],
      '0'
    );
    await add.wait();

    const volAmount = await controller.getCollateralToVolatility(
      '1500000000000000000000',
      volatilities['ETH'].address,
      [0,0]
    );

    await (await collateral['DAI'].approve(controller.address, "1500000000000000000000")).wait();
    const balanceBefore = await volatilities['ETH'].balanceOf(owner);

    const swap = await controller.swapCollateralToVolatility(
      ['1500000000000000000000', volAmount[0].toString()],
      volatilities['ETH'].address,
      [0,0]
    );
    const {events} = await swap.wait();
    const balanceAfter = await volatilities['ETH'].balanceOf(owner);

    const logData = getEventLog(events, 'AssetSwaped', ['uint256', 'uint256', 'uint256', 'uint256']);

    const changedAmount = balanceAfter.sub(balanceBefore)

    expect(Number(changedAmount.toString())).to.equal(Number(logData[1].toString()));
  });

  it('Should swap volatility to collateral', async () => {
    await (await volatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();
    await (await inverseVolatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();

    const add = await controller.addLiquidity(
      '250000000000000000000000000',
      ['599999999000000000000000000','599999999000000000000000000'],
      '0'
    );
    await add.wait();

    const colAmount = await controller.getVolatilityToCollateral(
      volatilities['ETH'].address,
      "20000000000000000000",
      0, 0,
      false
    );

    await (await volatilities['ETH'].approve(controller.address, "20000000000000000000")).wait();
    const collateralBefore = await collateral['DAI'].balanceOf(owner);

    const swap = await controller.swapVolatilityToCollateral(
      ["20000000000000000000", colAmount[0].toString()],
      ["0", "0"],
      volatilities['ETH'].address
    );
    const {events} = await swap.wait();
    const collateralAfter = await collateral['DAI'].balanceOf(owner);

    const changedBalance = collateralAfter.sub(collateralBefore);

    const logData = getEventLog(events, 'AssetSwaped', ['uint256', 'uint256', 'uint256', 'uint256']);

    expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
  });

  it('Should swap between multiple pools', async () => {
    await (await volatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();
    await (await inverseVolatilities['ETH'].approve(controller.address, "599999999000000000000000000")).wait();

    const addEth = await controller.addLiquidity(
      '250000000000000000000000000',
      ['599999999000000000000000000','599999999000000000000000000'],
      '0'
    );
    await addEth.wait();

    await (await volatilities['BTC'].approve(controller.address, "599999999000000000000000000")).wait();
    await (await inverseVolatilities['BTC'].approve(controller.address, "599999999000000000000000000")).wait();

    const addBtc = await controller.addLiquidity(
      '250000000000000000000000000',
      ['599999999000000000000000000','599999999000000000000000000'],
      '1'
    );
    await addBtc.wait();

    const volAmountOut = await controller.getSwapAmountBetweenPools(
      [volatilities['ETH'].address, volatilities['BTC'].address],
      '20000000000000000000',
      [0, 1, 0]
    );

    await (await volatilities['ETH'].approve(controller.address, "20000000000000000000")).wait();

    const balanceBefore = await volatilities['BTC'].balanceOf(owner);
    const swap = await controller.swapBetweenPools(
      [volatilities['ETH'].address, volatilities['BTC'].address],
      ['20000000000000000000', volAmountOut[0].toString()],
      [0, 1, 0]
    );
    const {events} = await swap.wait();
    const logData = getEventLog(events, 'AssetSwappedBetweenPool', ['uint256', 'uint256', 'uint256', 'uint256', 'address']);
    const balanceAfter = await volatilities['BTC'].balanceOf(owner);

    const changedBalance = balanceAfter.sub(balanceBefore);

    expect(Number(changedBalance.toString())).to.equal(Number(logData[1].toString()));
  });
});

const getEventLog = (events: any[], eventName: string, params: string[]): any => {
  let data;
  events.forEach((log: any) => {
    if (log['event'] == eventName) {
      data = log['data'];
    }
  })
  const logData = ethers.utils.defaultAbiCoder.decode(
    params,
    data
  );
  return logData;
}
