import { ethers, upgrades, run } from "hardhat";

const StableCoins = [
  "0xeabf1b4f19439af69302d6701a00e3c34d0ad20b", // DAI
  "0xaFD38467Ef8b9048Ddb853221dE79f993a103f21", // USDC
];

const Volatilitys = [
  "0x817970E6E2d9c6574dD66b0581bfD41caAcD5695", // ETHV2x
  "0xb6D338faf257E519DB571D50593ddF2Ff5Ce926A", // iETHV2x
  "0x803a5073B51339dDe1E28b2c96E0AA8385cFd3f0", // BTCV2X
  "0x0Aa19fc19C9F88068F8808954Ca1157cC96B3Af2"  // iBTCV2X
];

const Protocols = [
  "0xd23CA0D93FFfd5aD62A23736BCdf13729e6a6Ece", // ETH DAI
  "0xC2C1d6001535D157c18DE05d37c550C9B849a726", // ETH USDC
  "0xd846DD0c616a81DD05f82A4b749451e60e340f4B", // BTC DAI
  "0x1d2B038eB5d982A6c01ECe12E0F5529FC12A93C8"  // BTC USDC
];

const pool2x = async () => {
  const accounts = await ethers.getSigners();
  console.log("Deployer: ", await accounts[0].getAddress());
  console.log("balance: ", await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory("VolmexPool");
  const Controller = await ethers.getContractFactory("VolmexController");
  const Oracle = await ethers.getContractFactory("VolmexOracle");
  let governor = await accounts[0].getAddress();
  if (process.env.GOVERNOR) {
    governor = `${process.env.GOVERNOR}`;
  }

  const repricer = process.env.REPRICER;
  const oracle = Oracle.attach(`${process.env.ORACLE}`);
  const controller = Controller.attach(`${process.env.CONTROLLER}`);

  const ethv = await ethers.getContractAt("IERC20Modified", Volatilitys[0]);
  const iethv = await ethers.getContractAt("IERC20Modified", Volatilitys[1]);
  const btcv = await ethers.getContractAt("IERC20Modified", Volatilitys[2]);
  const ibtcv = await ethers.getContractAt("IERC20Modified", Volatilitys[3]);

  const BigNumber = require("bignumber.js");
  const bn = (num: number) => new BigNumber(num);

  const baseFee = (0.02 * Math.pow(10, 18)).toString();
  const maxFee = (0.4 * Math.pow(10, 18)).toString();
  const feeAmpPrimary = 10;
  const feeAmpComplement = 10;
  const qMin = (1 * Math.pow(10, 6)).toString();
  const pMin = (0.01 * Math.pow(10, 18)).toString();
  const exposureLimitPrimary = (0.25 * Math.pow(10, 18)).toString();
  const exposureLimitComplement = (0.25 * Math.pow(10, 18)).toString();
  const leveragePrimary = "999996478162223000";
  const leverageComplement = "1000003521850180000";

  console.log("Creating pool... ");
  const poolETH = await upgrades.deployProxy(Pool, [
    repricer,
    Protocols[0],
    "2",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor
  ]);
  await poolETH.deployed();
  console.log("ETH Pool deployed ", poolETH.address);

  const poolBTC = await upgrades.deployProxy(Pool, [
    repricer,
    Protocols[2],
    "3",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor
  ]);
  await poolBTC.deployed();
  console.log("BTC Pool deployed ", poolBTC.address);

  console.log("Add pools ETH");
  await (await controller.addPool(poolETH.address)).wait();
  console.log("Add pools BTC");
  await (await controller.addPool(poolBTC.address)).wait();

  console.log("Add protocol");
  console.log("Set ETH DAI");
  await (await controller.addProtocol(2, 0, Protocols[0])).wait();
  console.log("Set ETH USDC");
  await (await controller.addProtocol(2, 1, Protocols[1])).wait();
  console.log("Set BTC DAI");
  await (await controller.addProtocol(3, 0, Protocols[2])).wait();
  console.log("Set BTC USDC");
  await (await controller.addProtocol(3, 1, Protocols[3])).wait();

  console.log("Set ETH controller");
  await (await poolETH.setController(controller.address)).wait();
  console.log("Set BTC controller");
  await (await poolBTC.setController(controller.address)).wait();

  const joinAmount = "1000000000000000000";

  console.log("Approve volatility to pool ETH");
  await ethv.approve(controller.address, joinAmount);
  await iethv.approve(controller.address, joinAmount);
  console.log("Approve volatility to pool BTC");
  await btcv.approve(controller.address, joinAmount);
  await ibtcv.approve(controller.address, joinAmount);

  console.log("Finalize Pools ETH");
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
  console.log("Finalize Pools BTC");
  await (
    await controller.finalizePool(
      3,
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

  console.log("Pools finalized!");

  console.log('Oracle update ETH');
  await (await oracle.addVolatilityIndex(
    "62500000",
    Protocols[0],
    "ETHV2X",
    "0x6c00000000000000000000000000000000000000000000000000000000000000"
  )).wait();

  console.log('Oracle update BTC');
  await (await oracle.addVolatilityIndex(
    "62500000",
    Protocols[2],
    "BTCV2X",
    "0x6c00000000000000000000000000000000000000000000000000000000000000"
  )).wait();

  const proxyAdmin = await upgrades.admin.getInstance();

  await run("verify:verify", {
    address: await proxyAdmin.getProxyImplementation(poolETH.address),
  });

  await run("verify:verify", {
    address: await proxyAdmin.getProxyImplementation(poolBTC.address),
  });
};

pool2x()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });
