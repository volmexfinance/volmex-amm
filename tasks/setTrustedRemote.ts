const CHAIN_ID = require("../constants/chainIds.json");
// TODO: write script
// const { getDeploymentAddresses } = require('../utils/readStatic')

module.exports = async function (taskArgs, hre) {
  let localContract;
  let remoteContract;

  if (taskArgs.contract) {
    localContract = taskArgs.contract;
    remoteContract = taskArgs.contract;
  } else {
    localContract = taskArgs.localContract;
    remoteContract = taskArgs.remoteContract;
  }

  if (!localContract || !remoteContract) {
    console.log(
      "Must pass in contract name OR pass in both localContract name and remoteContract name"
    );
    return;
  }

  console.log(localContract);

  // get local contract
  const localContractInstance = await hre.ethers.getContractAt(
    localContract,
    "0x492216cDD729C142916EB565574bdCBc3843924f"
  );

  console.log("Owner local: ", await localContractInstance.owner());

  // get deployed remote contract address
  const remoteAddress = "0x7e7c38b1434391E44367D39333ed6084A3d76538";
  // getDeploymentAddresses(taskArgs.targetNetwork)[remoteContract];

  console.log("Remote address: ", remoteAddress);
  console.log("localContractInstance.address: ", localContractInstance.address);

  // get remote chain id
  const remoteChainId = CHAIN_ID[taskArgs.targetNetwork];

  // concat remote and local address
  const remoteAndLocal = hre.ethers.utils.solidityPack(
    ["address", "address"],
    [remoteAddress, localContractInstance.address]
  );

  const [owner] = await hre.ethers.getSigners();
  console.log("Deployer: ", owner.address);

  console.log(localContractInstance);

  // check if pathway is already set
  const isTrustedRemoteSet = await localContractInstance.isTrustedRemote(
    remoteChainId,
    remoteAndLocal
  );
  console.log("isTrustedRemoteSet: ", isTrustedRemoteSet);

  if (!isTrustedRemoteSet) {
    try {
      const tx = await (
        await localContractInstance.connect(owner).setTrustedRemote(remoteChainId, remoteAndLocal)
      ).wait();
      console.log(
        `✅ [${hre.network.name}] setTrustedRemote(${remoteChainId}, ${remoteAndLocal})`
      );
      console.log(` tx: ${tx.transactionHash}`);
    } catch (e) {
      if (e.error.message.includes("The chainId + address is already trusted")) {
        console.log("*source already set*");
      } else {
        console.log(
          `❌ [${hre.network.name}] setTrustedRemote(${remoteChainId}, ${remoteAndLocal})`
        );
      }
      console.log(e.error.message);
    }
  } else {
    console.log("*source already set*");
  }
};
