import { ethers, upgrades, run } from "hardhat";

const Protocols = [
  "0x149f21e2861121E217c2CFb4895EA05fF13B5bB0", // ETH DAI
  "0xcD5CE7cf09DCC15F95b6Cc096Ff247eA46c3E54C", // ETH USDC
  "0x6eaA3E716D732c39Df41A42516B61ec514c61B3b", // BTC DAI
  "0x1aDdc97A55905D067EF9c1C103562BF27b51A3d2", // BTC USDC
];

const Volatility = [
  "0xFdf8D2eCB6FD720D43884CE50BA9aAd1926B5396", // ETHV
  "0xeE21b34885054368446504730b6EdAf45186C989",
  "0x095CD8883f38534B1bD543cB7a7910b8023d19b0", //BTCV
  "0xEed375c6FCf7ee7Fd8Dd19b75FbBe0a7fd36E4d1",
];

const StableCoins = [
  "0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063", // DAI
  "0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174", // USDC
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

  const oracle = await upgrades.deployProxy(VolmexOracle, ["0x99f4588F53DdC0B0197D82bfeFc620dE0c485eD0"]);
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

  const joinAmount = "100000000000000000";

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

  console.log("\nDeployment History\n");
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
