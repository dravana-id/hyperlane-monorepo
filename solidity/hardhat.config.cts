process.env.HARDHAT_USE_WASM = "true";
process.env.HARDHAT_SOLC_USE_NODE_MODULE = "true";
import '@nomicfoundation/hardhat-foundry';
import '@nomiclabs/hardhat-ethers';
import '@nomiclabs/hardhat-waffle';
import '@typechain/hardhat';
import 'hardhat-gas-reporter';
import 'hardhat-ignore-warnings';
import 'solidity-coverage';
import 'hardhat-preprocessor';
import fs from "fs";
import { rootHardhatConfig } from './rootHardhatConfig.cjs';

/**
 * @type import('hardhat/config').HardhatUserConfig
 */

function getRemappings() {
  return fs
    .readFileSync("remappings.txt", "utf8")
    .split("\n")
    .filter(Boolean)
    .map((line) => line.trim().split("="));
}

const remappings = getRemappings();

module.exports = {
  ...rootHardhatConfig,

  preprocess: {
    eachLine: (hre) => ({
      transform: (line: string) => {
        for (const [from, to] of remappings) {
          if (line.includes(from)) {
            return line.replace(from, to);
          }
        }
        return line;
      },
    }),
  },

  solidity: {
    compilers: [
      {
        version: "0.8.22",
        settings: {},
      },
    ],
  },

  gasReporter: {
    currency: 'USD',
  },

  typechain: {
    outDir: './core-utils/typechain',
    target: 'ethers-v5',
    alwaysGenerateOverloads: true,
    node16Modules: true,
  },
};
