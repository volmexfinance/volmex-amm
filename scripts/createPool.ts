import { ethers, upgrades, run } from "hardhat";

const Protocols = [
  "0x52833271fC7Aae6D0451De8D387ca8e248c90e7B", // ETH DAI
  "0x6995C08611826Af0FE02B6F1a199848F5Db2b477", // ETH USDC
  "0x08a9eA97042d70b33CbEf217fBB368E0FfDb38d8", // BTC DAI
  "0x674d9e4493991b984ceB5a179853Bd76f815fc87", // BTC USDC
];

const Volatility = [
  "0x6b670Cb9490fc96C9dc56f7F06c54B8C0105b75E", // ETHV
  "0xe71bbC40443C7708040Ac752Cd86F617473F9B5a",
  "0x570df55Df6CA6b5b3485FC46209940729b813719", //BTCV
  "0x4069de818471a08cdDB758177db48a2a25526245",
];

const StableCoins = [
  "0xeabf1b4f19439af69302d6701a00e3c34d0ad20b", // DAI
  "0xaFD38467Ef8b9048Ddb853221dE79f993a103f21", // USDC
];

const createPool = async () => {
  const accounts = await ethers.getSigners();
  console.log("Deployer: ", await accounts[0].getAddress());
  console.log("balance: ", await accounts[0].getBalance());

  const Pool = await ethers.getContractFactory("VolmexPool");
  const VolmexRepricer = await ethers.getContractFactory("VolmexRepricer");
  const VolmexOracle = await ethers.getContractFactory("VolmexOracle");
  const ControllerFactory = await ethers.getContractFactory("VolmexController");
  const VolmexPoolView = await ethers.getContractFactory("VolmexPoolView");
  let governor = await accounts[0].getAddress();
  if (process.env.GOVERNOR) {
    governor = `${process.env.GOVERNOR}`;
  }

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

  console.log("Deploying Oracle...");

  const oracle = await upgrades.deployProxy(VolmexOracle, [governor]);
  await oracle.deployed();
  console.log("VolmexOracle deployed ", oracle.address);

  console.log("Deploying Repricer...");
  const repricer = await upgrades.deployProxy(VolmexRepricer, [oracle.address, governor]);
  await repricer.deployed();
  console.log("VolmexRepricer deployed ", repricer.address);

  console.log("Creating pool... ");
  const poolETH = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[0],
    "0",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor,
  ]);
  await poolETH.deployed();
  console.log("ETH Pool deployed ", poolETH.address);

  const poolBTC = await upgrades.deployProxy(Pool, [
    repricer.address,
    Protocols[2],
    "1",
    baseFee,
    maxFee,
    feeAmpPrimary,
    feeAmpComplement,
    governor,
  ]);
  await poolBTC.deployed();
  console.log("BTC Pool deployed ", poolBTC.address);

  const ethv = await ethers.getContractAt("IERC20Modified", Volatility[0]);
  const iethv = await ethers.getContractAt("IERC20Modified", Volatility[1]);

  const btcv = await ethers.getContractAt("IERC20Modified", Volatility[2]);
  const ibtcv = await ethers.getContractAt("IERC20Modified", Volatility[3]);

  console.log("Deploying controller ...");
  const controller = await upgrades.deployProxy(ControllerFactory, [
    StableCoins,
    [poolETH.address, poolBTC.address],
    Protocols,
    governor,
  ]);
  await controller.deployed();
  console.log("VolmexController deployed :", controller.address);

  console.log("Setting pools controller ...");
  await (await poolETH.setController(controller.address)).wait();
  await (await poolBTC.setController(controller.address)).wait();
  console.log("Set pools controller");

  const joinAmount = "1000000000000000000";

  console.log("Approve volatility to pool ETH");
  await ethv.approve(controller.address, joinAmount);
  await iethv.approve(controller.address, joinAmount);

  console.log("Approve volatility to pool BTC");
  await btcv.approve(controller.address, joinAmount);
  await ibtcv.approve(controller.address, joinAmount);

  console.log("Finalize Pools");
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
  console.log("Pools finalized!");

  console.log("Deploying Pool view ...");
  const poolView = await upgrades.deployProxy(VolmexPoolView, [controller.address]);
  await poolView.deployed();
  console.log("VolmexPoolView deployed", poolView.address);

  console.log("\nDeployment History");
  console.log("VolmexPool ETH: ", poolETH.address);
  console.log("VolmexPool BTC: ", poolBTC.address);
  console.log("VolmexRepricer: ", repricer.address);
  console.log("VolmexOracle: ", oracle.address);
  console.log("Controller: ", controller.address);
  console.log("VolmexAMMView: ", poolView.address);

  const proxyAdmin = await upgrades.admin.getInstance();

  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolETH.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(repricer.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(oracle.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(controller.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolView.address),
    });
  } catch (error: any) {}
  try {
    await run("verify:verify", {
      address: await proxyAdmin.getProxyImplementation(poolBTC.address),
    });
  } catch (error: any) {}
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error("Error: ", error);
    process.exit(1);
  });
