import CHAIN_ID from "../constants/chainIds.json";
import ENDPOINTS from "../constants/layerzeroEndpoints.json";

module.exports = async function (taskArgs, hre) {
  console.log("In task");
  const remoteChainId = CHAIN_ID[taskArgs.targetNetwork]
  const layer2VolmexPositionToken = await hre.ethers.getContractAt("Layer2VolmexPositionToken", taskArgs.toAddress)

  // quote fee with default adapterParams
  let adapterParams = hre.ethers.utils.solidityPack(["uint16", "uint256"], [1, 200000]) // default adapterParams example

  const endpoint = await hre.ethers.getContractAt("ILayerZeroEndpointUpgradeable", ENDPOINTS[hre.network.name])
  let fees = await endpoint.estimateFees(remoteChainId, layer2VolmexPositionToken.address, "0x", false, adapterParams)
  console.log(`fees[0] (wei): ${fees[0]} / (eth): ${hre.ethers.utils.formatEther(fees[0])}`)

  const [owner] = await hre.ethers.getSigners();
  console.log("Deployer: ", owner.address);

  const toAddress = taskArgs.toAddress
  const amount = taskArgs.amount
  const refundAddress = taskArgs.fromAddress
  const zroPaymentAddress = taskArgs.fromAddress

  let tx = await (
      await layer2VolmexPositionToken.sendFrom(
          owner.address,
          remoteChainId,
          toAddress,
          amount,
          refundAddress,
          zroPaymentAddress,
          adapterParams,
          { value: fees[0] }
      )
  ).wait()
  console.log(`✅ Message Sent [${hre.network.name}] sendTokens on destination OmniCounter @ [${remoteChainId}]`)
  console.log(`tx: ${tx.transactionHash}`)

  console.log(``)
  console.log(`Note: to poll/wait for the message to arrive on the destination use the command:`)
  console.log(`       (it may take a minute to arrive, be patient!)`)
  console.log("")
  console.log(`    $ npx hardhat --network ${taskArgs.targetNetwork} ocPoll`)
}