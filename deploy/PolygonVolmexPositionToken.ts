import { ethers, upgrades, run, network } from "hardhat";
const LZ_ENDPOINTS = require("../constants/layerzeroEndpoints.json")

module.exports = async function () {
    const [owner] = await ethers.getSigners();
    const erc20Modified = await ethers.getContractAt("IERC20Modified", `${process.env.POLYGON_TOKEN_ADDRESS}`, owner);
    console.log("Deployer: ", owner.address);
    console.log("Balance: ", (await owner.getBalance()).toString());
    const contract = await ethers.getContractFactory("PolygonVolmexPositionTokenWrapper");
  
    console.log("Deploying upgradeable contract ...");
    
    const endpointAddr = LZ_ENDPOINTS[network.name]
    console.log(`[${network.name}] Endpoint address: ${endpointAddr}`)

    
    const instance = await upgrades.deployProxy(
        contract, 
        [`${process.env.POLYGON_TOKEN_ADDRESS}`, endpointAddr],
        {
            initializer: "initialize",
        },
    );

    await instance.deployed();
    console.log("Deployed to PolygonVolmexPositionTokenWrapper: ", (instance.address));

    console.log("Granting VOLMEX_PROTOCOL_ROLE");
    const VOLMEX_PROTOCOL_ROLE = "0x33ba6006595f7ad5c59211bde33456cab351f47602fc04f644c8690bc73c4e16";
    try {
        await erc20Modified.grantRole(VOLMEX_PROTOCOL_ROLE, instance.address);
        console.log("Role granted successfully...");
    } catch (e) {
        console.log("Error while granting role.", e);
    }
    
    const proxyAdmin = await upgrades.admin.getInstance();
    console.log("Proxy Implementation address: ", (await proxyAdmin.getProxyImplementation(instance.address)));
  
    // await run("verify:verify", {
    //   address: await proxyAdmin.getProxyImplementation(instance.address),
    // });
}

module.exports.tags = ["PolygonVolmexPositionTokenWrapper"]
