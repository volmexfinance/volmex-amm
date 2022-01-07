import { ethers, upgrades, run } from 'hardhat';

const Protocols = [
  '0xA480cb2928da9b3dCA7154D3cD8D955455B90ef0', // ETH DAI
  '0x41b866fD8f50B1A9461877005eE942DAd51C037B', // ETH USDC
  '0x60248bA0104EB51D91877Ee2302c0C5affB5f2aa', // BTC DAI
  '0xd3081eba5728E6853005DB9f4A19Ea2DBFdf5A6D', // BTC USDC
];

const Volatility = [
  '0xd214d87Cb51ce5a434426e6066E666cA1394dc88', // ETHV
  '0x429E89202a75652dd96c7E80AfB904eBF5403a17',
  '0xE94ee63927bee73Cf4e62adA3E06b4C84431C912', //BTCV
  '0xcd3Ed7BFf2678e018d637451B449A76ed9584398',
];

const StableCoins = [
  '0xeabf1b4f19439af69302d6701a00e3c34d0ad20b', // DAI
  '0xaFD38467Ef8b9048Ddb853221dE79f993a103f21', // USDC
];

const createPool = async () => {
  const accounts = await ethers.getSigners();
  console.log('Deployer: ', await accounts[0].getAddress());
  console.log('balance: ', await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory('VolmexPool');
  const VolmexRepricer = await ethers.getContractFactory('VolmexRepricer');
  const VolmexOracle = await ethers.getContractFactory('VolmexOracle');
  const ControllerFactory = await ethers.getContractFactory('VolmexController');
  const VolmexPoolView = await ethers.getContractFactory('VolmexPoolView');

  const BigNumber = require('bignumber.js');
  const bn = (num: number) => new BigNumber(num);

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

  console.log('Deploying Oracle...');

  const oracle = await upgrades.deployProxy(VolmexOracle, []);
  await oracle.deployed();
  console.log('VolmexOracle deployed ', oracle.address);

  console.log('Deploying Repricer...');
  const repricer = await upgrades.deployProxy(VolmexRepricer, [oracle.address]);
  await repricer.deployed();
  console.log('VolmexRepricer deployed ', repricer.address);

  console.log('Creating pool... ');
  const poolETH = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[0],
    '0',
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
  ]);
  await poolETH.deployed();
  console.log('ETH Pool deployed ', poolETH.address);

  const poolBTC = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[2],
    '1',
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
  ]);
  await poolBTC.deployed();
  console.log('BTC Pool deployed ', poolBTC.address);

  const ethv = await ethers.getContractAt('IERC20Modified', Volatility[0]);
  const iethv = await ethers.getContractAt('IERC20Modified', Volatility[1]);

  const btcv = await ethers.getContractAt('IERC20Modified', Volatility[2]);
  const ibtcv = await ethers.getContractAt('IERC20Modified', Volatility[3]);

  console.log('Deploying controller ...');
  const controller = await upgrades.deployProxy(ControllerFactory, [
    StableCoins,
    [poolETH.address, poolBTC.address],
    Protocols,
  ]);
  await controller.deployed();
  console.log('VolmexController deployed :', controller.address);

  console.log('Setting pools controller ...');
  await (await poolETH.setController(controller.address)).wait();
  await (await poolBTC.setController(controller.address)).wait();
  console.log('Set pools controller');

  const joinAmount = '1000000000000000000';

  console.log('Approve volatility to pool ETH');
  await ethv.approve(poolETH.address, joinAmount);
  await iethv.approve(poolETH.address, joinAmount);

  console.log('Approve volatility to pool BTC');
  await btcv.approve(poolBTC.address, joinAmount);
  await ibtcv.approve(poolBTC.address, joinAmount);

  console.log('Finalize Pools');
  await (
    await controller.finalizePool(
      0,
      joinAmount,
      leveragePrimary,
      joinAmount,
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin
    )
  ).wait();
  await (
    await controller.finalizePool(
      1,
      joinAmount,
      leveragePrimary,
      joinAmount,
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin
    )
  ).wait();
  console.log('Pools finalised!');

  console.log('Deploying Pool view ...');
  const poolView = await upgrades.deployProxy(VolmexPoolView, []);
  await poolView.deployed();
  console.log('VolmexPoolView deployed', poolView.address);

  console.log('\n Deployment History');
  console.log('VolmexPool ETH: ', poolETH.address);
  console.log('VolmexPool BTC: ', poolBTC.address);
  console.log('VolmexRepricer: ', repricer.address);
  console.log('VolmexOracle: ', oracle.address);
  console.log('Controller: ', controller.address);
  console.log('VolmexAMMView: ', poolView.address);

  const proxyAdmin = await upgrades.admin.getInstance();

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(poolETH.address),
  });

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(poolBTC.address),
  });

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(repricer.address),
  });

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(oracle.address),
  });

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(controller.address),
  });

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(poolView.address),
  });
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });
