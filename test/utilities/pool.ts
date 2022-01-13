import { BigNumberish, ContractReceipt, ContractTransaction, Event, utils } from 'ethers';
import { VolmexPoolView } from '../../typechain/VolmexPoolView';
import { JoinedEvent } from '../../typechain/VolmexPool';
import { VolmexController } from '../../typechain/VolmexController';
import { IVolatility } from '../Slippage.test';
import { decodeEvents } from './events';
import { expect } from './expects'

export type AddLiquidityContractParam = { controller: VolmexController, poolView: VolmexPoolView, pools: IVolatility }
export type AddLiquidityDetails = [
    [BigNumberish, BigNumberish], BigNumberish, ContractTransaction
]
export type ResolvedAddLiquidityDetails = [[BigNumberish, BigNumberish], BigNumberish, ContractTransaction, ContractReceipt]

export type ParsedAddLiquidityDetails = {
    amountIn: [BigNumberish, BigNumberish],
    amountOut: BigNumberish,
    tx: ContractTransaction,
    receipt: ContractReceipt,
    events: Array<JoinedEvent>
}

export const addLiquidity = async (contracts: AddLiquidityContractParam, asset: 'ETH' | 'BTC', amountOut: BigNumberish) => {

    const amountIn = await contracts.poolView.getTokensToJoin(contracts.pools[asset].address, amountOut)

    return await contracts.controller.addLiquidity(
        amountOut,
        amountIn,
        asset == 'ETH' ? '0' : '1'
    );
}

export const addLiquidityAndReport = async (contracts: AddLiquidityContractParam, asset: 'ETH' | 'BTC', amountOut: BigNumberish): Promise<AddLiquidityDetails> => {

    let maxAmountsIn = await contracts.poolView.getTokensToJoin(contracts.pools[asset].address, amountOut)
    maxAmountsIn = [(maxAmountsIn[0].mul(1005)).div(1000), (maxAmountsIn[1].mul(1005)).div(1000)];  // Providing 0.5% slippage
    const addLiquidityTransaction = await contracts.controller.addLiquidity(
        amountOut,
        maxAmountsIn,
        asset == 'ETH' ? '0' : '1'
    );

    return [maxAmountsIn, amountOut, addLiquidityTransaction]
}

export const addMultipleLiquidity = async (contracts: AddLiquidityContractParam, asset: 'ETH' | 'BTC', count: number, minMax: [number, number]): Promise<Array<AddLiquidityDetails>> => {
    const liquidityDetails: Array<AddLiquidityDetails> = []
    for (let i = 0; i < count; i++) {
        const addLiquidityDetails = await addLiquidityAndReport(contracts, asset, getRandomAmount(...minMax))
        liquidityDetails.push(addLiquidityDetails)
    }
    return liquidityDetails
}

export const retrieveLiquidityTransactionRecpeipt = async (addLiquidityTransactions: Array<AddLiquidityDetails>): Promise<Array<ResolvedAddLiquidityDetails>> => {
    const liquidityDetails: Array<ResolvedAddLiquidityDetails> = []
    for (const addLiquidityTransaction of addLiquidityTransactions) {
        console.log(`Parsing TX (${addLiquidityTransaction[2].hash}): Amount In: ${addLiquidityTransaction[0]}, Amount Out: ${addLiquidityTransaction[1]}`)
        const receipt = await addLiquidityTransaction[2].wait()
        const resolvedDetails: ResolvedAddLiquidityDetails = [...addLiquidityTransaction, receipt];
        liquidityDetails.push(resolvedDetails)
    }
    return liquidityDetails
}

export const formatToParsedAddLiquidityDetails = (contracts: AddLiquidityContractParam, addLiquidityReceipts: Array<ResolvedAddLiquidityDetails>, ) => {
    return addLiquidityReceipts.map((receipt: ResolvedAddLiquidityDetails): ParsedAddLiquidityDetails => {
        const events = decodeEvents(contracts.pools['ETH'], receipt[3].events as Event[], 'Joined') as unknown as Array<JoinedEvent>
        
        return {
            events: events,
            amountIn: receipt[0],
            amountOut: receipt[1],
            tx: receipt[2],
            receipt: receipt[3]
        }
    })
}

export const checkAddLiquidityRecievedLPTokens = (transactions: Array<ParsedAddLiquidityDetails>) => {
    for(const transaction of transactions) {
        expect(transaction.amountIn[0]).equals(transaction.amountIn[1])
        //@ts-ignore
        expect(transaction.amountOut).equals(transaction.events[0].lpAmountOut)
    }
}

const getRandomAmount = (min: number, max: number) => {
    min = Math.ceil(min);
    max = Math.floor(max);
    const amount = Math.floor(Math.random() * (max - min) + min).toFixed(0)
    return utils.parseEther(amount); //The maximum is exclusive and the minimum is inclusive
}

const getPoolIndex = (asset: 'ETH' | 'BTC') => {
    return asset == 'ETH' ? '0' : '1'
}