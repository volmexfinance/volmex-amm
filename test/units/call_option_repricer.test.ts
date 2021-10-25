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

import { CallOptionRepricer } from '../../typechain/CallOptionRepricer';

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

describe('CallOptionRepricer', () => {
    let repricer: CallOptionRepricer;

    beforeEach(async () => {
        const signers = await ethers.getSigners();
        const CallOptionRepricerFactory = await ethers.getContractFactory(
            'CallOptionRepricer',
            signers[0]
        );
        repricer = (await CallOptionRepricerFactory.deploy()) as CallOptionRepricer;
        await repricer.deployed();
        expect(repricer.address).to.properAddress;
    });

    it('check read params', async () => {
        await expect(await repricer.isRepricer()).to.be.true;
        await expect(await repricer.symbol()).to.be.equal('CallOptionRepricer');
    });

    it('reprice with 1% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;
        const strike = 1000;

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
            strike.toString()
        );

        await expect(result['estPrice']).to.be.equal('7443338939939257256');
        await expect(result['estPricePrimary']).to.be.equal('119620923331933196450');
        await expect(result['estPriceComplement']).to.be.equal('890379076668066803550');
    });

    it('reprice with 10% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;
        const strike = 1000;

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
            strike.toString()
        );

        await expect(result['estPrice']).to.be.equal('5243464446571394093');
        await expect(result['estPricePrimary']).to.be.equal('176184233835761858900');
        await expect(result['estPriceComplement']).to.be.equal('923815766164238141100');
    });

    it('reprice with 20% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;
        const strike = 1000;

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
            strike.toString()
        );

        await expect(result['estPrice']).to.be.equal('3806489314337670194');
        await expect(result['estPricePrimary']).to.be.equal('249662471197100517400');
        await expect(result['estPriceComplement']).to.be.equal('950337528802899482600');
    });

    it('reprice with 100% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;
        const strike = 1000;

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
            strike.toString()
        );

        await expect(result['estPrice']).to.be.equal('997929031258871594');
        await expect(result['estPricePrimary']).to.be.equal('1001036557709871963000');
        await expect(result['estPriceComplement']).to.be.equal('998963442290128037000');
    });

    it('reprice with -10% change', async () => {
        const currentTime = await getBlockTime(provider);
        const settledTime = currentTime + 30 * 24 * 60 * 60;
        const pMin = 0.01;
        const volatility = 1;
        const strike = 1000;

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
            strike.toString()
        );

        await expect(result['estPrice']).to.be.equal('12749504647926405439');
        await expect(result['estPricePrimary']).to.be.equal('65456903579121381600');
        await expect(result['estPriceComplement']).to.be.equal('834543096420878618400');
    });
});
