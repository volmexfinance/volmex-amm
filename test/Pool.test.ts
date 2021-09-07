const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';

describe('Pool', function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let repricerFactory: any;
  let repricer: any;
  let poolFactory: any;
  let pool: any;
  let protocolFactory: any;
  let protocol: any;
  let collateralFactory: any;
  let collateral: any;
  let volatilityFactory: any;
  let volatility: any;
  let inverseVolatility: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    repricerFactory = await ethers.getContractFactory('VolmexRepricer');

    volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');

    poolFactory = await ethers.getContractFactory('Pool');

    collateralFactory = await ethers.getContractFactory('TestCollateralToken');

    volatilityFactory = await ethers.getContractFactory('VolmexPositionToken');

    protocolFactory = await ethers.getContractFactory('VolmexProtocol');
  });

  this.beforeEach(async function () {
    collateral = await collateralFactory.deploy();
    await collateral.deployed();

    volatility = await volatilityFactory.deploy();
    await volatility.deployed();
    let volReciept = await volatility.initialize('ETH Volatility Index', 'ETHV');
    await volReciept.wait();

    inverseVolatility = await volatilityFactory.deploy();
    await inverseVolatility.deployed();
    volReciept = await inverseVolatility.initialize('Inverse ETH Volatility Index', 'iETHV');
    await volReciept.wait();

    protocol = await upgrades.deployProxy(protocolFactory, [
      `${collateral.address}`,
      `${volatility.address}`,
      `${inverseVolatility.address}`,
      '25000000000000000000',
      '250',
    ]);
    await protocol.deployed();

    const VOLMEX_PROTOCOL_ROLE =
      '0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16';

    volReciept = await volatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volReciept.wait();

    volReciept = await inverseVolatility.grantRole(VOLMEX_PROTOCOL_ROLE, `${protocol.address}`);
    await volReciept.wait();

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory);
    await volmexOracle.deployed();

    repricer = await repricerFactory.deploy(volmexOracle.address, protocol.address);
    await repricer.deployed();

    const owner = await accounts[0].getAddress();
    pool = await poolFactory.deploy(repricer.address, protocol.address, owner);

    const baseFee = (0.02 * Math.pow(10, 18)).toString();
    const maxFee = (0.4 * Math.pow(10, 18)).toString();
    const feeAmpPrimary = 10;
    const feeAmpComplement = 10;

    const qMin = (1 * Math.pow(10, 6)).toString();
    const pMin = (0.01 * Math.pow(10, 18)).toString();
    const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
    const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
    const leveragePrimary = '999996478162223000';
    const leverageComplement = '1000003521850180000';
    const MAX = '10000000000000000000000';

    const feeReciept = await pool.setFeeParams(baseFee, maxFee, feeAmpPrimary, feeAmpComplement);
    await feeReciept.wait();

    await (await collateral.mint(owner, '10000000000000000000000')).wait();
    await (await collateral.approve(protocol.address, MAX)).wait();
    await (await protocol.collateralize('4000000000000000000000')).wait();
    await (await volatility.approve(pool.address, MAX)).wait();
    await (await inverseVolatility.approve(pool.address, MAX)).wait();

    const finalizeReceipt = await pool.finalize(
      '1000000000000000000',
      leveragePrimary,
      '1000000000000000000',
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin
    );
    await finalizeReceipt.wait();
  });

  it('should deploy pool', async () => {
    const poolReciept = await pool.deployed();
    expect(poolReciept.confirmations).not.equal(0);
  });

  it('should swap the assets', async () => {
    const joinReceipt = await pool.joinPool(
      '3000000000000000000000',
      ['20000000000000000000','20000000000000000000']
    );
    await joinReceipt.wait();

    const swap = await pool.swapExactAmountIn(
      volatility.address,
      '3000000000000000000',
      inverseVolatility.address,
      '1000000000000000000'
    );
    const swapReciept = await swap.wait();
  });
});
