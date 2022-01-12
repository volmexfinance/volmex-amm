import { network } from "hardhat";

export const setMiningMode = async (active: boolean) => {
    await network.provider.send("evm_setAutomine", [active]);   
}

export const mineBlock = async () => {
    await network.provider.send("evm_mine");
}