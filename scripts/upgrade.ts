import { ethers, upgrades, run } from 'hardhat';

const createPool = async () => {
  const [owner] = await ethers.getSigners();
  console.log("Balance: ", (await owner.getBalance()).toString());
  const contract = await ethers.getContractFactory(`${process.env.CONTRACT_NAME}`);

  console.log("Upgrading contract ...");
  const instance = await upgrades.upgradeProxy(`${process.env.CONTRACT_ADDRESS}`, contract);
  await instance.deployed();

  const proxyAdmin = await upgrades.admin.getInstance();

  await run("verify:verify", {
    address: await proxyAdmin.getProxyImplementation(instance.address),
  });
};

createPool()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error('Error: ', error);
    process.exit(1);
  });