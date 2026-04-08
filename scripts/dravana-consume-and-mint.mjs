/**
 * Call DravanaHypERC20.consumeAndMint(messageId) on the warp **proxy** (state lives here).
 *
 * Do NOT send txs to the implementation address — pending `messages` mapping is on the proxy.
 *
 * One-time: npm install in scripts/dravana-consume-pkg (small ethers dependency).
 *
 * Usage (from hyperlane-monorepo root):
 *   DRAVANA_RPC=https://chain.dravana.id/rpc \
 *   DRAVANA_CHAIN_ID=170845 \
 *   WARP_TOKEN=0xB2590Ff2eB0A5BcCA812ce8eA73ab18541740b3e \
 *   EXPECTED_IMPLEMENTATION=0x254424C6759a1f452078b40757782065545DCc68 \
 *   MESSAGE_ID=0x... \
 *   PRIVATE_KEY=0x... \
 *   node ./scripts/dravana-consume-and-mint.mjs
 *
 * Optional: DRY_RUN=1 — only read chain id, implementation slot, and messages(messageId); no tx.
 */
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const requireEthers = createRequire(join(__dirname, 'dravana-consume-pkg', 'package.json'));
const { ethers } = requireEthers('ethers');

const EIP1967_IMPL_SLOT =
  '0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc';

const ABI = [
  'function consumeAndMint(bytes32 messageId) external',
  'function messages(bytes32) view returns (address recipient, uint256 amount, uint32 origin, bytes32 sender, uint256 expiry, bool consumed)',
];

function reqEnv(name, fallback) {
  const v = process.env[name];
  if (v !== undefined && v !== '') return v;
  if (fallback !== undefined) return fallback;
  console.error(`Missing env: ${name}`);
  process.exit(1);
}

async function main() {
  const rpc = reqEnv('DRAVANA_RPC', 'https://chain.dravana.id/rpc');
  const chainId = parseInt(reqEnv('DRAVANA_CHAIN_ID', '170845'), 10);
  const warpProxy = reqEnv(
    'WARP_TOKEN',
    '0xB2590Ff2eB0A5BcCA812ce8eA73ab18541740b3e',
  );
  const expectedImpl =
    process.env.EXPECTED_IMPLEMENTATION ||
    '0x254424C6759a1f452078b40757782065545DCc68';
  const messageId = reqEnv('MESSAGE_ID');
  const dryRun = process.env.DRY_RUN === '1' || process.env.DRY_RUN === 'true';
  const pk = process.env.PRIVATE_KEY;

  if (!dryRun && (!pk || pk === '')) {
    console.error('Set PRIVATE_KEY or use DRY_RUN=1');
    process.exit(1);
  }

  if (!/^0x[0-9a-fA-F]{64}$/.test(messageId)) {
    console.error('MESSAGE_ID must be 32-byte hex, e.g. 0x...64 hex chars');
    process.exit(1);
  }

  const provider = new ethers.providers.JsonRpcProvider(rpc, {
    chainId,
    name: 'dravana',
  });

  const net = await provider.getNetwork();
  if (net.chainId !== chainId) {
    console.warn(
      `[warn] RPC reported chainId ${net.chainId}, expected ${chainId}`,
    );
  }

  const implSlot = await provider.getStorageAt(warpProxy, EIP1967_IMPL_SLOT);
  const implAddr = ethers.utils.getAddress('0x' + implSlot.slice(-40));
  console.log('[info] Warp proxy:          ', warpProxy);
  console.log('[info] EIP-1967 implementation:', implAddr);
  if (expectedImpl && implAddr.toLowerCase() !== expectedImpl.toLowerCase()) {
    console.warn(
      `[warn] Implementation !== EXPECTED_IMPLEMENTATION (${expectedImpl})`,
    );
  }

  const reader = new ethers.Contract(warpProxy, ABI, provider);
  const pending = await reader.messages(messageId);
  console.log('[info] messages(messageId) recipient:', pending.recipient);
  console.log('[info] amount:', pending.amount.toString());
  console.log('[info] consumed:', pending.consumed);
  console.log('[info] expiry (unix):', pending.expiry.toString());

  if (dryRun) {
    console.log('[dry-run] Skipping consumeAndMint');
    return;
  }

  const wallet = new ethers.Wallet(pk, provider);
  if (wallet.address.toLowerCase() !== pending.recipient.toLowerCase()) {
    console.error(
      `[err] Wallet ${wallet.address} is not pending.recipient ${pending.recipient}`,
    );
    process.exit(1);
  }
  if (pending.recipient === ethers.constants.AddressZero) {
    console.error('[err] No pending message for this messageId');
    process.exit(1);
  }
  if (pending.consumed) {
    console.error('[err] Already consumed');
    process.exit(1);
  }

  const tx = await reader.connect(wallet).consumeAndMint(messageId);
  console.log('[info] Sent tx:', tx.hash);
  const receipt = await tx.wait();
  console.log('[ok] Mined in block', receipt.blockNumber);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
