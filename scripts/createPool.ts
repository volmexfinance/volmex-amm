import { ethers } from 'hardhat';

const VAULT_FACTORY_PROXY = {
  '1': '0x3269DeB913363eE58E221808661CfDDa9d898127',
  '4': '0x0d2497c1eCB40F77BFcdD99f04AC049c9E9d83F7',
  '137': '0xE970b0B1a2789e3708eC7DfDE88FCDbA5dfF246a',
  '97': '0x42d002b519820b4656CcAe850B884aE355A4E349',
  '80001': '0x277Dc5711B3D3F2C57ab7d28c5A9430E599ba42C',
};

const POOL_FACTORY = {
  '1': '0xfD0BBD821aabC0D91c49fE245a579F220e5f59Ba',
  '4': '0xF8F148ca1F81854d04D301dAfe1092c53fcD9367',
  '137': '0xa7E039A7984834562F8a1CB19cB7fc5819417225',
  '97': '0x9bCd6E3646Bd80a050904032782E70fc8235923F',
  '80001': '0x0Dea8dAba1014b84a9017d5eB46404424A1978d6',
};

const createPool = async () => {
  const accounts = await ethers.getSigners();
  const CONTROLLER = accounts[0];

  const PoolFactory = ethers.getContractFactory('PoolFactory');
  const Pool = ethers.getContractFactory('Pool');
  const x5Repricer = ethers.getContractFactory('x5Repricer');

  const VaultFactory = ethers.getContractFactory('VaultFactory');
  const Vault = ethers.getContractFactory('Vault');
  const StubToken = ethers.getContractFactory('StubToken');

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

  const leveragePrimary = '999996478162223000'
  const leverageComplement = '1000003521850180000';
  const dynamicFeeAddress = '0x105aE5e940f157D93187082CafCCB27e1941B505';


  const poolFactoryAddress = POOL_FACTORY['4'];

  const factory = (await PoolFactory).attach(poolFactoryAddress);
  console.log('poolFactoryAddress ' + factory.address);

  const vaultFactoryAddress = VAULT_FACTORY_PROXY['4'];

  const vaultFactory = (await VaultFactory).attach(vaultFactoryAddress);
  console.log('vaultFactoryAddress ' + vaultFactory.address);

  const lastVaultIndex = await vaultFactory.getLastVaultIndex.call();
  console.log('Last vault created index ' + lastVaultIndex);
  const vaultAddress = await vaultFactory.getVault(lastVaultIndex);
  console.log('Last vault created ' + vaultAddress);

  console.log('Deploying x5Repricer...');

  const repricer = (await x5Repricer).deploy();
  (await repricer).deployed();

  console.log('Creating pool... for vault ' + vaultAddress);
  // const newPoolReceipt = await factory.newPool(vaultAddress, ethers.utils.formatBytes32String('x5Repricer'), 0, 0, 0);
  // await newPoolReceipt.wait();

  const pool = (await Pool).deploy(
    vaultAddress,
    dynamicFeeAddress,
    (await repricer).address,
    CONTROLLER.address
  );

  (await pool).deployed()

  const lastPoolIndex = await factory.getLastPoolIndex.call();
  console.log('Pool created index ' + lastPoolIndex);
  const poolAddress = (await pool).address;
  console.log('Pool created ' + poolAddress);

  const poolContract = (await Pool).attach(poolAddress);
  const vaultContract = (await Vault).attach(vaultAddress);

  console.log('Set Pool Fee');
  const feeReciept = await poolContract.setFeeParams(baseFee, maxFee, feeAmpPrimary, feeAmpComplement);
  await feeReciept.wait();

  const collateralTokenAddress = await vaultContract.collateralToken();
  const primaryTokenAddress = await vaultContract.primaryToken();
  const complementTokenAddress = await vaultContract.complementToken();

  const collateralToken = await (await StubToken).attach(collateralTokenAddress)
  console.log('collateralTokenAddress ', collateralTokenAddress);
  const primaryToken = await (await StubToken).attach(primaryTokenAddress);
  console.log('primaryTokenAddress ', primaryTokenAddress);
  const complementToken = await (await StubToken).attach(complementTokenAddress);
  console.log('complementTokenAddress ', complementTokenAddress);

  console.log('Mint collateral');
  await collateralToken.mint(CONTROLLER.address, '20000000000');

  const MAX = '0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff';

  console.log('Approve collateral to vault');
  await collateralToken.approve(vaultAddress, MAX);

  console.log('Mint derivatives');
  await vaultContract.mint('20000000000');

  console.log('Approve primary to pool');
  await primaryToken.approve(poolContract.address, MAX);

  console.log('Approve complement to pool');
  await complementToken.approve(poolContract.address, MAX);

  console.log('Finalize Pool');
  const finalizeReceipt = await poolContract.finalize(
      '10000000',
      leveragePrimary,
      '10000000',
      leverageComplement,
      exposureLimitPrimary,
      exposureLimitComplement,
      pMin,
      qMin,
      repricerParam1,
      repricerParam2,
  );
  await finalizeReceipt.wait();
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });

