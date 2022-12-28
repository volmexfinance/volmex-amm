/* eslint-disable no-undef */
task('sendTokens', 'Send tokens from one chain to another', require('./sendTokens.ts'))
    .addParam('targetNetwork', 'the target network to set as a trusted remote')
    .addParam('amount', 'Amount of tokens to send in ETH')
    .addParam('contract', 'Name of local contract (from chain)')
    .addParam('contractAddress', 'Address of local contract (from chain)')
    .addParam('fromAddress', 'Address of account from which tokens have to be transferred')
    .addParam('toAddress', 'Address of account to which tokens have to be transferred');

task(
    'setTrustedRemote',
    'setTrustedRemote(chainId, sourceAddr) to enable inbound/outbound messages with your other contracts',
    require('./setTrustedRemote.ts'),
)
    .addParam('targetNetwork', 'the target network to set as a trusted remote')
    .addOptionalParam('localContract', 'Name of local contract if the names are different')
    .addOptionalParam('remoteContract', 'Name of remote contract if the names are different')
    .addOptionalParam('localContractAddress', 'Address of the local contract')
    .addOptionalParam('remoteContractAddress', 'Address of the remote contract')
    .addOptionalParam('contract', 'If both contracts are the same name');
