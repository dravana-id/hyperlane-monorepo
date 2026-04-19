/**
 * Owner-only: DravanaSynthetic.setPendingMintTtl(seconds) on the warp **proxy**.
 *
 * One-time: npm install in scripts/dravana-consume-pkg (same ethers bundle as consume script).
 *
 * Usage (from hyperlane-monorepo root):
 *   DRAVANA_RPC=https://chain.dravana.id/rpc \
 *   DRAVANA_CHAIN_ID=170845 \
 *   WARP_TOKEN=0xB2590Ff2eB0A5BcCA812ce8eA73ab18541740b3e \
 *   PRIVATE_KEY=0x... \
 *   PENDING_MINT_TTL=86400 \
 *   node ./scripts/dravana-set-pending-mint-ttl.mjs
 *
 * Optional: DRY_RUN=1 — print pendingMintTtl + owner only; no tx.
 */
import { createRequire } from 'node:module';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const requireEthers = createRequire(join(__dirname, 'dravana-consume-pkg', 'package.json'));
const { ethers } = requireEthers('ethers');

const ABI = [
  'function pendingMintTtl() view returns (uint256)',
  'function setPendingMintTtl(uint256 _ttl) external',
  'function owner() view returns (address)',
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
  const ttlStr = reqEnv('PENDING_MINT_TTL', '86400');
  const ttl = ethers.BigNumber.from(ttlStr);
  if (ttl.lte(0)) {
    console.error('PENDING_MINT_TTL must be > 0 (contract also reverts if 0)');
    process.exit(1);
  }

  const dryRun = process.env.DRY_RUN === '1' || process.env.DRY_RUN === 'true';
  const pk = process.env.PRIVATE_KEY;

  if (!dryRun && (!pk || pk === '')) {
    console.error('Set PRIVATE_KEY (owner) or use DRY_RUN=1');
    process.exit(1);
  }

  const provider = new ethers.providers.JsonRpcProvider(rpc, {
    chainId,
    name: 'dravana',
  });

  const c = new ethers.Contract(warpProxy, ABI, provider);
  const current = await c.pendingMintTtl();
  const ownerAddr = await c.owner();
  console.log('[info] WARP_TOKEN:         ', warpProxy);
  console.log('[info] owner():            ', ownerAddr);
  console.log('[info] pendingMintTtl now: ', current.toString(), 'seconds');

  if (dryRun) {
    console.log('[dry-run] Would set pendingMintTtl to', ttl.toString());
    return;
  }

  const wallet = new ethers.Wallet(pk, provider);
  if (wallet.address.toLowerCase() !== ownerAddr.toLowerCase()) {
    console.error(
      `[err] PRIVATE_KEY address ${wallet.address} is not owner ${ownerAddr}`,
    );
    process.exit(1);
  }

  const tx = await c.connect(wallet).setPendingMintTtl(ttl);
  console.log('[info] Sent tx:', tx.hash);
  const receipt = await tx.wait();
  console.log('[ok] Mined in block', receipt.blockNumber);
  const after = await c.pendingMintTtl();
  console.log('[ok] pendingMintTtl after:', after.toString(), 'seconds');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
