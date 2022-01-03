const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';
const assert = require('assert');
const { expectRevert } = require('@openzeppelin/test-helpers');

describe('Repricer', function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;
  let repricerFactory: any;
  let repricer: any;
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

    volmexOracle = await upgrades.deployProxy(volmexOracleFactory, []);
    await volmexOracle.deployed();

    repricer = await upgrades.deployProxy(repricerFactory, [volmexOracle.address]);
  });

  it('Should deploy repricer', async () => {
    const receipt = await repricer.deployed();
    expect(receipt.confirmations).not.equal(0);
    assert.equal(await receipt.oracle(), volmexOracle.address);
  });

  it('Should call the reprice method', async () => {
    const reciept1 = await repricer.reprice('0');
    const reciept2 = await repricer.reprice('1');
    assert.equal(reciept1[0].toString(), '125000000');
    assert.equal(reciept1[1].toString(), '125000000');
    assert.equal(reciept1[2].toString(), '1000000000000000000');
    assert.equal(reciept2[0].toString(), '125000000');
    assert.equal(reciept2[1].toString(), '125000000');
    assert.equal(reciept2[2].toString(), '1000000000000000000');
    let reciept = await volmexOracle.updateBatchVolatilityTokenPrice(
      ['1'],
      ['105000000'],
      ['0x6c00000000000000000000000000000000000000000000000000000000000000']
    );
    await reciept.wait();
    reciept = await repricer.reprice('1');
    assert.equal(reciept[0].toString(), '105000000');
    assert.equal(reciept[1].toString(), '145000000');
  });

  it('Should revert on not contract', async () => {
    const [other] = accounts;

    await expectRevert(
      upgrades.deployProxy(repricerFactory, [await other.getAddress()]),
      'Repricer: Not an oracle contract'
    );
  });

  it('should calculate the correct square root', async () => {
    let output = await repricer.sqrtWrapped(4);
    assert.equal(output.toString(), '1999999999');
  });
});
