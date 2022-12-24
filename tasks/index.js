/* eslint-disable no-undef */
task('sendTokens', 'Send tokens from one chain to another', require('./sendTokens.ts'))
    .addParam('targetNetwork', 'the target network to set as a trusted remote')
    .addParam('amount', '')
    .addOptionalParam('localContract', 'Name of local contract if the names are different')
    .addOptionalParam('remoteContract', 'Name of remote contract if the names are different')
    .addOptionalParam('contract', 'If both contracts are the same name');

task(
    'setTrustedRemote',
    'setTrustedRemote(chainId, sourceAddr) to enable inbound/outbound messages with your other contracts',
    require('./setTrustedRemote.ts'),
)
    .addParam('targetNetwork', 'the target network to set as a trusted remote')
    .addOptionalParam('localContract', 'Name of local contract if the names are different')
    .addOptionalParam('remoteContract', 'Name of remote contract if the names are different')
    .addOptionalParam('contract', 'If both contracts are the same name');
