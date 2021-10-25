import { ethers, waffle } from 'hardhat';
import { BigNumberish } from '@ethersproject/bignumber';

const { BigNumber, constants } = ethers;
const bn = (value: any) => BigNumber.from(value);

const { deployMockContract } = waffle;
const provider = waffle.provider; //MockProvider
const [wallet, otherWallet] = provider.getWallets();

import chai from 'chai';

import Vault from '../Abi/Vault.json';
import Oracle from '../Abi/Oracle.json';
import DerivativeSpecification from '../Abi/DerivativeSpecification.json';

import { X5Repricer } from '../../typechain/X5Repricer';

const { expect } = chai;

const mockVault = async (
    currentTime: any,
    liveUnderlingValue: any,
    currentUnderlingValue: any,
    settledTime: any
) => {
    const mockDerivativeSpecification = await deployMockContract(
        wallet,
        DerivativeSpecification.abi
    );

    await mockDerivativeSpecification.mock.primaryNominalValue.returns(1);
    await mockDerivativeSpecification.mock.complementNominalValue.returns(1);

    const mockOracle = await deployMockContract(wallet, Oracle.abi);
    await mockOracle.mock.latestRoundData.returns(
        1,
        currentUnderlingValue,
        0,
        currentTime - 1 * 60,
        0
    );

    const mockVault = await deployMockContract(wallet, Vault.abi);
    await mockVault.mock.derivativeSpecification.returns(mockDerivativeSpecification.address);
    await mockVault.mock.oracles.withArgs(0).returns(mockOracle.address);
    await mockVault.mock.settleTime.returns(settledTime);
    await mockVault.mock.underlyingStarts.withArgs(0).returns(liveUnderlingValue);

    return mockVault.address;
};

const createPoolPair = (balance: any, leverage: any): [BigNumberish, BigNumberish] => {
    const BONE = Math.pow(10, 18).toString();
    const collateralTokenDecimals = 6;

    return [
        bn(balance).mul(10 ** collateralTokenDecimals),
        bn(leverage * 10)
            .mul(BONE)
            .div(10),
    ];
};

const getBlockTime = async (provider: any) => {
    const block = await provider.getBlock();
    return block.timestamp;
};

describe('x5Repricer', () => {
    let repricer: X5Repricer;

    beforeEach(async () => {
        const signers = await ethers.getSigners();
        const x5RepricerFactory = await ethers.getContractFactory('x5Repricer', signers[0]);
        repricer = (await x5RepricerFactory.deploy()) as X5Repricer;
        await repricer.deployed();
        expect(repricer.address).to.properAddress;
    });

    it('check read params', async () => {
        await expect(await repricer.isRepricer()).to.be.true;
        await expect(await repricer.symbol()).to.be.equal('x5Repricer');
    });

    it('reprice with 1% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;

        const liveUnderlingValue = 1000;
        const change = 0.01;
        const currentUnderlingValue = change * liveUnderlingValue + liveUnderlingValue;

        const vault = await mockVault(
            currentTime,
            liveUnderlingValue,
            currentUnderlingValue,
            settledTime
        );

        const result = await repricer.reprice(
            vault,
            (pMin * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString()
        );

        await expect(result['estPrice']).to.be.equal('1136157922950685594');
        await expect(result['estPricePrimary']).to.be.equal('936260366573174526');
        await expect(result['estPriceComplement']).to.be.equal('1063739633426825474');
    });

    it('reprice with 10% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;

        const liveUnderlingValue = 1000;
        const change = 0.1;
        const currentUnderlingValue = change * liveUnderlingValue + liveUnderlingValue;

        const vault = await mockVault(
            currentTime,
            liveUnderlingValue,
            currentUnderlingValue,
            settledTime
        );

        const result = await repricer.reprice(
            vault,
            (pMin * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString()
        );

        await expect(result['estPrice']).to.be.equal('732222960096940403');
    });

    it('reprice with 20% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;

        const liveUnderlingValue = 1000;
        const change = 0.2;
        const currentUnderlingValue = change * liveUnderlingValue + liveUnderlingValue;

        const vault = await mockVault(
            currentTime,
            liveUnderlingValue,
            currentUnderlingValue,
            settledTime
        );

        const result = await repricer.reprice(
            vault,
            (pMin * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString()
        );

        await expect(result['estPrice']).to.be.equal('464512169127514537');
    });

    it('reprice with 100% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;

        const liveUnderlingValue = 1000;
        const change = 1;
        const currentUnderlingValue = change * liveUnderlingValue + liveUnderlingValue;

        const vault = await mockVault(
            currentTime,
            liveUnderlingValue,
            currentUnderlingValue,
            settledTime
        );

        const result = await repricer.reprice(
            vault,
            (pMin * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString()
        );

        await expect(result['estPrice']).to.be.equal('16563347022067024');
    });

    it('reprice with -10% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;

        const liveUnderlingValue = 1000;
        const change = -0.1;
        const currentUnderlingValue = change * liveUnderlingValue + liveUnderlingValue;

        const vault = await mockVault(
            currentTime,
            liveUnderlingValue,
            currentUnderlingValue,
            settledTime
        );

        const result = await repricer.reprice(
            vault,
            (pMin * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString(),
            (volatility * Math.pow(10, 18)).toString()
        );

        await expect(result['estPrice']).to.be.equal('2067895498755300202');
    });
});
