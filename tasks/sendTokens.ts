const CHAIN_ID = require("../constants/chainIds.json");

module.exports = async function (taskArgs, hre) {
  const signers = await hre.ethers.getSigners();
  const owner = signers[0];
  const fromAddress = taskArgs.fromAddress;
  const toAddress = taskArgs.toAddress;
  const qty = hre.ethers.utils.parseEther(taskArgs.amount);

  let localContract;

  localContract = taskArgs.localContract;

  // get remote chain id
  const remoteChainId = CHAIN_ID[taskArgs.targetNetwork];

  // get local contract
  const localContractInstance = await hre.ethers.getContractAt(localContract, taskArgs.localContractAddress);

  // quote fee with default adapterParams
  let adapterParams = hre.ethers.utils.solidityPack(["uint16", "uint256"], [1, 200000]); // default adapterParams example
  
  let fees = await localContractInstance.estimateSendFee(
    remoteChainId,
    toAddress,
    qty,
    false,
    adapterParams
  );
  console.log(`fees[0] (wei): ${fees[0]} / (eth): ${hre.ethers.utils.formatEther(fees[0])}`);

  let tx = await (
    await localContractInstance.sendFrom(
      fromAddress, // 'from' address to send tokens
      remoteChainId, // remote LayerZero chainId
      toAddress, // 'to' address to send tokens
      qty, // amount of tokens to send (in wei)
      fromAddress, // refund address (if too much message fee is sent, it gets refunded)
      hre.ethers.constants.AddressZero, // address(0x0) if not paying in ZRO (LayerZero Token)
      "0x", // flexible bytes array to indicate messaging adapter services
      { value: fees[0] }
    )
  ).wait();
  console.log(
    `✅ Message Sent [${hre.network.name}] sendTokens() to OFT @ LZ chainId[${remoteChainId}] token:[${toAddress}]`
  );
  console.log(` tx: ${tx.transactionHash}`);
  console.log(
    `* check your address [${fromAddress}] on the destination chain, in the ERC20 transaction tab !"`
  );
};
