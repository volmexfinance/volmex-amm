// @ts-nocheck
const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
import { Signer } from "ethers";

describe("Layer2VolmexPositionToken", function () {
    beforeEach(async function () {
        console.log("Start");
        // use this chainId
        this.chainId = 123
        console.log("chainId set");

        // create a LayerZero Endpoint mock for testing
        const LayerZeroEndpointMock = await ethers.getContractFactory("LZEndpointMock")
        console.log("layerZero End point mock");
        this.lzEndpointMock = await LayerZeroEndpointMock.deploy(this.chainId)
        console.log("layerZero End point mock deployed....");

        // create two Layer2VolmexPositionToken instances
        const Layer2VolmexPositionToken = await ethers.getContractFactory("Layer2VolmexPositionToken")
        console.log("token fetched....");
        this.omniCounterA = await Layer2VolmexPositionToken.deploy(this.lzEndpointMock.address, ["VPT1", "VPT1", lzEndpointMock.address])
        console.log("deploying 1....");
        this.omniCounterB = await Layer2VolmexPositionToken.deploy(this.lzEndpointMock.address, ["VPT2", "VPT2", lzEndpointMock.address])
        console.log("deploying 2....");

        this.lzEndpointMock.setDestLzEndpoint(this.omniCounterA.address, this.lzEndpointMock.address)
        this.lzEndpointMock.setDestLzEndpoint(this.omniCounterB.address, this.lzEndpointMock.address)

        // set each contracts source address so it can send to each other
        this.omniCounterA.setTrustedRemote(
            this.chainId,
            ethers.utils.solidityPack(["address", "address"], [this.omniCounterB.address, this.omniCounterA.address])
        )
        this.omniCounterB.setTrustedRemote(
            this.chainId,
            ethers.utils.solidityPack(["address", "address"], [this.omniCounterA.address, this.omniCounterB.address])
        )
    })

    it("increment the counter of the destination Layer2VolmexPositionToken", async function () {
        console.log("Hello");
        // ensure theyre both starting from 0
        // expect(await this.omniCounterA.counter()).to.be.equal(0) // initial value
        // expect(await this.omniCounterB.counter()).to.be.equal(0) // initial value

        // // instruct each Layer2VolmexPositionToken to increment the other Layer2VolmexPositionToken
        // // counter A increments counter B
        // await this.omniCounterA.incrementCounter(this.chainId, { value: ethers.utils.parseEther("0.5") })
        // expect(await this.omniCounterA.counter()).to.be.equal(0) // still 0
        // expect(await this.omniCounterB.counter()).to.be.equal(1) // now its 1

        // // counter B increments counter A
        // await this.omniCounterB.incrementCounter(this.chainId, { value: ethers.utils.parseEther("0.5") })
        // expect(await this.omniCounterA.counter()).to.be.equal(1) // now its 1
        // expect(await this.omniCounterB.counter()).to.be.equal(1) // still 1
    })
})
