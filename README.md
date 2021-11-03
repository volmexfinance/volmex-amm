# Volmex Leveraged AMM

Volmex Protocol - Decentralised Derivatives That Do Not Default. No counterparty risk, no margin
calls, no liquidations.

Volmex Leveraged AMM white paper https://compli.fi/files/Leveraging%20Uniswap.pdf

## Setup

Requirements:

- Node >= v12

## Linting and Formatting

To check code for problems:

```
$ npm run typecheck      # Type-check TypeScript code
$ npm run lint           # Check JavaScript and TypeScript code
$ npm run lint --fix     # Fix problems where possible
$ npm run solhint        # Check Solidity code
$ npm run slither        # Run Slither
```

To auto-format code:

```
$ npm run fmt
```

## Testing

First, make sure Ganache is running.

```
$ ganache-cli
```

Run all tests:

```
$ npm run test
```

To run tests in a specific file, run:

```
$ npm run test [path/to/file]
```

To run tests and generate test coverage, run:

```
$ npm run coverage
```

## Deployment

Create a copy of the file `.env.template`, and name it `.env`. Enter the BIP39
mnemonic phrase, the INFURA API key to use for deployment, and the gas price in
gwei in `.env`. This file must not be checked into the repository.

Run `npm run migrate --network NETWORK`, where NETWORK is either `mainnet` or
`rinkeby`.
