import { ethers, upgrades, run } from 'hardhat';

const createPool = async () => {
  const accounts = await ethers.getSigners();
  const childChainManager = "0x2e5e27d50EFa501D90Ad3638ff8441a0C0C0d75e";
  const CONTROLLER = accounts[0];

  const Pool = await ethers.getContractFactory('VolmexAMM');
  const VolmexRepricer = await ethers.getContractFactory('VolmexRepricer');
  const VolmexOracle = await ethers.getContractFactory('VolmexOracle');
  const VolmexAMMRegistry = await ethers.getContractFactory('VolmexAMMRegistry');
  const ControllerFactory = await ethers.getContractFactory('VolmexController');
  const VolmexAMMView = await ethers.getContractFactory('VolmexAMMView');

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
    '0xbc280baafc91798adbeeb3042d33e592ed6709e6'
  );

  console.log('Deploying Oracle...');

  const oracle = await upgrades.deployProxy(
    VolmexOracle, []
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

  const pool = await upgrades.deployProxy(Pool, [
    repricer.address,
    protocolAddress.address,
    childChainManager,
    false,
    "0",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement
  ]);
  await pool.deployed();

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

  console.log('Deploying controller ...');
  const controller = await upgrades.deployProxy(ControllerFactory, [
    collateralToken.address,
    pool.address,
    protocolAddress.address
  ]);
  await controller.deployed();
  console.log('Deployed controller :', controller.address);

  const setController = await pool.setController(controller.address);
  await setController.wait();

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

  const volmexAMMView = await upgrades.deployProxy(VolmexAMMView, []);
  await volmexAMMView.deployed();

  console.log('Registered AMM');

  console.log('VolmexAMM: ', pool.address);
  console.log('VolmexRepricer: ', repricer.address);
  console.log('VolmexOracle: ', oracle.address);
  console.log('Controller: ', controller.address);
  console.log('Registry: ', registry.address);
  console.log('VolmexAMMView: ', volmexAMMView.address);

  const poolProxyAdmin = await upgrades.admin.getInstance();
  const repricerProxyAdmin = await upgrades.admin.getInstance();
  const oracleProxyAdmin = await upgrades.admin.getInstance();
  const controllerProxyAdmin = await upgrades.admin.getInstance();
  const registryProxyAdmin = await upgrades.admin.getInstance();
  const ammViewProxyAdmin = await upgrades.admin.getInstance();

  await run("verify:verify", {
    address: await poolProxyAdmin.getProxyImplementation(pool.address),
  });

  await run("verify:verify", {
    address: await repricerProxyAdmin.getProxyImplementation(repricer.address),
  });

  await run("verify:verify", {
    address: await oracleProxyAdmin.getProxyImplementation(oracle.address),
  });

  await run("verify:verify", {
    address: await controllerProxyAdmin.getProxyImplementation(controller.address),
  });

  await run("verify:verify", {
    address: await registryProxyAdmin.getProxyImplementation(registry.address),
  });

  await run("verify:verify", {
    address: await ammViewProxyAdmin.getProxyImplementation(volmexAMMView.address),
  });
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });
