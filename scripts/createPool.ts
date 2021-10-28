import { ethers, upgrades, run } from 'hardhat';

const createPool = async () => {
  const accounts = await ethers.getSigners();
  const CONTROLLER = accounts[0];

  const Pool = await ethers.getContractFactory('VolmexAMM');
  const VolmexRepricer = await ethers.getContractFactory('VolmexRepricer');
  const VolmexOracle = await ethers.getContractFactory('VolmexOracle');
  const VolmexAMMRegistry = await ethers.getContractFactory('VolmexAMMRegistry');

  const BigNumber = require('bignumber.js');
  const bn = (num: number) => new BigNumber(num);
  const BONE = bn(1).times(10 ** 18);

  const baseFee = (0.02 * Math.pow(10, 18)).toString();
  const maxFee = (0.4 * Math.pow(10, 18)).toString();
  const feeAmpPrimary = 10;
  const feeAmpComplement = 10;

  const qMin = (1 * Math.pow(10, 6)).toString();
  const pMin = (0.01 * Math.pow(10, 18)).toString();
  const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
  const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
  const repricerParam1 = (1.15 * Math.pow(10, 18)).toString();
  const repricerParam2 = (0.9 * Math.pow(10, 18)).toString();

  const leveragePrimary = '999996478162223000';
  const leverageComplement = '1000003521850180000';
  // const dynamicFeeAddress = '0x105aE5e940f157D93187082CafCCB27e1941B505';
  const protocolAddress = await ethers.getContractAt(
      'IVolmexProtocol',
      '0xdd3a1Ad3e7a2715231147D2F5e6f28F187CD6081'
  );

  console.log('Deploying Oracle...');

  const oracle = await upgrades.deployProxy(
    VolmexOracle, [
      '1250000'
    ]
  );
  await oracle.deployed();
  console.log('oracle deployed ', oracle.address);

  console.log('Deploying Repricer...');

  const repricer = await upgrades.deployProxy(VolmexRepricer, [
    oracle.address,
    protocolAddress.address
  ]);
  await repricer.deployed();

  console.log('repricer deployed ', repricer.address);

  console.log('Creating pool... ');

  const pool = await Pool.deploy(
      repricer.address,
      protocolAddress.address,
      CONTROLLER.address
  );

  await pool.deployed();

  console.log('Set Pool Fee');
  const feeReciept = await pool.setFeeParams(baseFee, maxFee, feeAmpPrimary, feeAmpComplement);
  await feeReciept.wait();

  const collateralToken = await ethers.getContractAt(
      'IERC20Modified',
      await protocolAddress.collateral()
  );
  console.log('collateralTokenAddress ', collateralToken.address);
  const primaryToken = await ethers.getContractAt(
      'IERC20Modified',
      await protocolAddress.volatilityToken()
  );
  console.log('primaryTokenAddress ', primaryToken.address);
  const complementToken = await ethers.getContractAt(
      'IERC20Modified',
      await protocolAddress.inverseVolatilityToken()
  );
  console.log('complementTokenAddress ', complementToken.address);

  // console.log('Mint collateral');
  // await collateralToken.mint(CONTROLLER.address, '10000000000000000000000');

  const MAX = '10000000000000000000000';

  console.log('Approve collateral to protocol');
  await collateralToken.approve(protocolAddress.address, MAX);

  // console.log('Mint derivatives');
  // await protocolAddress.collateralize('4000000000000000000000');

  console.log('Approve primary to pool');
  await primaryToken.approve(pool.address, MAX);

  console.log('Approve complement to pool');
  await complementToken.approve(pool.address, MAX);

  console.log('Finalize Pool');
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

  console.log('Pool finalised!');

  console.log('\nRegistering pool...');

  const registry = await upgrades.deployProxy(VolmexAMMRegistry, []);
  await registry.deployed();

  console.log('Registered AMM');

  // await run("verify:verify", {
  //   address: pool.address,
  // });
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });
