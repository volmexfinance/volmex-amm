import {IVolatility} from '../Slippage.test';
import { ERC20 } from '../../typechain/ERC20'

export const approveToken = async (token: IVolatility & ERC20, amount: string, approveTo: string) => {
    return await token.approve(approveTo, amount);
}