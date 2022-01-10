import { ethers, upgrades, run } from 'hardhat';

const StableCoins = [
  '0xeabf1b4f19439af69302d6701a00e3c34d0ad20b', // DAI
  '0xaFD38467Ef8b9048Ddb853221dE79f993a103f21', // USDC
];

const Volatilitys = [
  '0x817970E6E2d9c6574dD66b0581bfD41caAcD5695', // ETHV2x
  '0xb6D338faf257E519DB571D50593ddF2Ff5Ce926A'  // iETHV2x
];

const Protocols = [
  '0xd23CA0D93FFfd5aD62A23736BCdf13729e6a6Ece', // ETH DAI
  '0xC2C1d6001535D157c18DE05d37c550C9B849a726', // ETH USDC
];

const pool2x = async () => {
  const accounts = await ethers.getSigners();
  console.log('Deployer: ', await accounts[0].getAddress());
  console.log('balance: ', await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory('VolmexPool');
  const Controller = await ethers.getContractFactory('VolmexController');

  const repricer = process.env.REPRICER;
  const controller = Controller.attach(`${process.env.CONTROLLER}`);

  const ethv = await ethers.getContractAt('IERC20Modified', Volatilitys[0]);
  const iethv = await ethers.getContractAt('IERC20Modified', Volatilitys[1]);

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

  console.log('Creating pool... ');
  const poolETH = await upgrades.deployProxy(Pool, [
    repricer,
    Protocols[0],
    '0',
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
  ]);
  await poolETH.deployed();
  console.log('ETH Pool deployed ', poolETH.address);

  const {events} = await (await controller.addPool(poolETH.address)).wait();
  let data;
  events.forEach((log: any) => {
    if (log['event'] == 'PoolAdded') {
      data = log['topics'];
    }
  });
  // @ts-ignore
  const poolIndex = ethers.utils.defaultAbiCoder.decode(['uint256'], data[1]);
  console.log('Pool set on index', poolIndex);
  await (await controller.addProtocol(poolIndex, 0, Protocols[0])).wait();
  console.log('Set ETH DAI');
  await (await controller.addProtocol(poolIndex, 1, Protocols[1])).wait();
  console.log('Set ETH USDC');

  console.log('Setting pools controller ...');
  await (await poolETH.setController(controller.address)).wait();
  console.log('Set pools controller');

  const joinAmount = '1000000000000000000';

  console.log('Approve volatility to pool ETH');
  await ethv.approve(controller.address, joinAmount);
  await iethv.approve(controller.address, joinAmount);

  console.log('Finalize Pools');
  await (
    await controller.finalizePool(
      2,
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

  console.log('Pools finalized!');

  const proxyAdmin = await upgrades.admin.getInstance();

  await run('verify:verify', {
    address: await proxyAdmin.getProxyImplementation(poolETH.address),
  });
};

pool2x()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });
