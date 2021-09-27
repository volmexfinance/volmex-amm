const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');
import { Signer } from 'ethers';
const { expectRevert } = require('@openzeppelin/test-helpers');

describe('Volmex Oracle', function () {
  let accounts: Signer[];
  let volmexOracleFactory: any;
  let volmexOracle: any;

  this.beforeAll(async function () {
    accounts = await ethers.getSigners();

    volmexOracleFactory = await ethers.getContractFactory('VolmexOracle');
  });

  this.beforeEach(async function () {
    volmexOracle = await upgrades.deployProxy(volmexOracleFactory);

    await volmexOracle.deployed();
  });

  it('Should deploy volmex oracle', async () => {
    const receipt = await volmexOracle.deployed();
    expect(receipt.confirmations).not.equal(0);
  });

  it('Should update the volatility price', async () => {
    const receipt = await volmexOracle.updateVolatilityTokenPrice('0', '105');

    expect((await receipt.wait()).confirmations).not.equal(0);

    expect(await volmexOracle.volatilityTokenPriceByIndex('0')).equal('1050000');
  });

  it('Should revert when volatility price is not in range', async () => {
    await expectRevert(
      volmexOracle.updateVolatilityTokenPrice('0', '250'),
      'VolmexOracle: _volatilityTokenPrice should be greater than 0'
    );

    await expectRevert(
      volmexOracle.updateVolatilityTokenPrice('1', '0'),
      'VolmexOracle: _volatilityTokenPrice should be greater than 0'
    );
  });

  it('Should add volatility token price', async () => {
    await expectRevert(
      volmexOracle.addVolatilityTokenPrice('0', 'LTCV'),
      'VolmexOracle: _volatilityTokenPrice should be greater than 0'
    );

    const receipt = await volmexOracle.addVolatilityTokenPrice('120', 'LTCV');
    expect((await receipt.wait()).confirmations).not.equal(0);

    expect(await volmexOracle.volatilityTokenPriceByIndex(await volmexOracle.indexCount())).equal('1200000');
  });
});
