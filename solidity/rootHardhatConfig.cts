/**
 * Shared configuration for hardhat projects
 * @type import('hardhat/config').HardhatUserConfig
 */
export const rootHardhatConfig = {
  solidity: {
    version: '0.8.22',
    settings: {
      optimizer: {
        enabled: true,
        // Low runs shrink deployed bytecode (EIP-170 24,576 byte cap). High runs (e.g. 25k)
        // optimize runtime gas but HypERC20Collateral / DravanaHypERC20 often exceed the limit.
        runs: 200,
      },
    },
  },
  mocha: {
    bail: true,
    import: 'tsx',
  },
};
