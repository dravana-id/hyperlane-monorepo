/**
 * After `pnpm hardhat-esm compile`, reports deployed bytecode size vs EIP-170 (24576 bytes).
 * Appends one NDJSON line to workspace debug log when DEBUG_LOG_PATH is set (debug sessions).
 */
import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const EIP170_MAX = 24576;
const SESSION = '75765a';

const artifactRelPaths = [
  'artifacts/contracts/token/DravanaSynthetic.sol/DravanaSynthetic.json',
  'artifacts/contracts/token/HypERC20Collateral.sol/HypERC20Collateral.json',
];

function byteSize(hex) {
  if (!hex || hex === '0x') return 0;
  const h = hex.startsWith('0x') ? hex.slice(2) : hex;
  return h.length / 2;
}

function main() {
  const solidityRoot = path.join(__dirname, '..');
  const rows = [];
  for (const rel of artifactRelPaths) {
    const full = path.join(solidityRoot, rel);
    if (!fs.existsSync(full)) {
      rows.push({ contract: rel, error: 'artifact missing', runCompile: true });
      continue;
    }
    const j = JSON.parse(fs.readFileSync(full, 'utf8'));
    const deployed = j.deployedBytecode;
    const n = byteSize(deployed);
    rows.push({
      contract: path.basename(path.dirname(rel)),
      bytes: n,
      eip170Ok: n <= EIP170_MAX,
      limit: EIP170_MAX,
    });
  }

  console.log(JSON.stringify({ eip170Max: EIP170_MAX, artifacts: rows }, null, 2));

  const debugLog =
    process.env.DEBUG_LOG_PATH ||
    path.join(solidityRoot, '..', '..', 'debug-75765a.log');
  try {
    const line = JSON.stringify({
      sessionId: SESSION,
      hypothesisId: 'EIP170',
      location: 'solidity/scripts/check-eip170-bytecode.mjs',
      message: 'deployed bytecode size vs EIP-170',
      data: { rows },
      timestamp: Date.now(),
    });
    fs.appendFileSync(debugLog, line + '\n', 'utf8');
    console.error(`[check-eip170] appended: ${debugLog}`);
  } catch (e) {
    console.error('[check-eip170] skip debug log:', e.message);
  }
}

main();
