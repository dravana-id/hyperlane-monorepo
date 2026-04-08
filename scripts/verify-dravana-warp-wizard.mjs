/**
 * Verifies the Dravana fork is present in the *built* SDK + CLI artifacts.
 * Run from monorepo root after: pnpm --filter @hyperlane-xyz/sdk build && pnpm --filter @hyperlane-xyz/cli build
 *
 * If this fails but source in git has the fork, you are likely:
 * - Running `npx @hyperlane-xyz/cli` (upstream npm, not this repo), or
 * - Stale turbo/cache dist — rebuild CLI with --force (see README).
 */
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const root = join(__dirname, '..');

let failed = false;

const sdkEntry = join(root, 'typescript/sdk/dist/index.js');
if (!existsSync(sdkEntry)) {
  console.error('[verify] FAIL: missing', sdkEntry);
  console.error('        Build SDK: pnpm --filter @hyperlane-xyz/sdk build');
  failed = true;
} else {
  const { TokenType } = await import(pathToFileURL(sdkEntry).href);
  const vals = Object.values(TokenType);
  const has = vals.includes('dravanaSynthetic');
  console.log('[verify] SDK TokenType.dravanaSynthetic:', has, has ? 'OK' : 'MISSING');
  if (!has) {
    console.error('        Your @hyperlane-xyz/sdk dist is not the fork (or SDK not rebuilt).');
    failed = true;
  }
}

const warpDist = join(root, 'typescript/cli/dist/config/warp.js');
if (!existsSync(warpDist)) {
  console.error('[verify] FAIL: missing', warpDist);
  console.error('        Build CLI: pnpm --filter @hyperlane-xyz/cli build');
  failed = true;
} else {
  const src = readFileSync(warpDist, 'utf8');
  const hasFn = src.includes('buildWizardTokenTypeChoices');
  const hasTok = src.includes('dravanaSynthetic');
  console.log('[verify] CLI dist has buildWizardTokenTypeChoices:', hasFn, hasFn ? 'OK' : 'MISSING');
  console.log('[verify] CLI dist has dravanaSynthetic string:', hasTok, hasTok ? 'OK' : 'MISSING');
  if (!hasFn || !hasTok) {
    console.error('        Rebuild CLI without cache: pnpm exec turbo run build --filter=@hyperlane-xyz/cli --force');
    failed = true;
  }
}

if (failed) {
  console.error('\n[verify] Use local entrypoint only, e.g.:');
  console.error('  cd typescript/cli && node dist/cli.js warp init --help');
  console.error('Do NOT use: npx @hyperlane-xyz/cli (upstream npm package).\n');
  process.exit(1);
}
console.log('\n[verify] All checks passed. Run: cd typescript/cli && node dist/cli.js warp init ...\n');
