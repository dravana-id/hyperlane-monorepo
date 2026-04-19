#!/usr/bin/env bash
# Verify Dravana warp contracts on Blockscout (chain 170845).
# Run from repo root: bash script/verify-blockscout-dravana.sh
#
# Defaults match USDC deploy (update addresses if your deployment differs).
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERIFIER_URL="${VERIFIER_URL:-https://chain.dravana.id/api}"
CHAIN_ID="${CHAIN_ID:-170845}"
API_KEY="${BLOCKSCOUT_API_KEY:-blockscout}"

# Creation txs from Blockscout API (contract/getcontractcreation)
IMPL_ADDR="${IMPL_ADDR:-0x8ba53b2f3ae71b3f11cbcd73801563aace94d593}"
IMPL_CREATION_TX="${IMPL_CREATION_TX:-0x3b27545851610175717540a7edb11cdbe38974a5696ebe0ed6d63f60a333b10c}"

PROXY_ADDR="${PROXY_ADDR:-0x39237Ed57Aa6671224047085E49f68b5a224CA76}"
PROXY_CREATION_TX="${PROXY_CREATION_TX:-0xd712399c5a28a2ebfd7378375b8230eb2fdd6b39bda050c12e1a4205256a87a3}"

SOLC_VERSION="${SOLC_VERSION:-0.8.22}"
OPT_RUNS="${OPT_RUNS:-200}"

echo "== Implementation: DravanaSynthetic @ $IMPL_ADDR =="
forge verify-contract "$IMPL_ADDR" \
  contracts/token/DravanaSynthetic.sol:DravanaSynthetic \
  --chain "$CHAIN_ID" \
  --verifier blockscout \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$API_KEY" \
  --compiler-version "$SOLC_VERSION" \
  --num-of-optimizations "$OPT_RUNS" \
  --creation-transaction-hash "$IMPL_CREATION_TX" \
  --watch || true

echo ""
echo "== Proxy: OpenZeppelin TransparentUpgradeableProxy @ $PROXY_ADDR =="
forge verify-contract "$PROXY_ADDR" \
  dependencies/@openzeppelin-contracts-4.9.3/contracts/proxy/transparent/TransparentUpgradeableProxy.sol:TransparentUpgradeableProxy \
  --chain "$CHAIN_ID" \
  --verifier blockscout \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$API_KEY" \
  --compiler-version "$SOLC_VERSION" \
  --num-of-optimizations "$OPT_RUNS" \
  --creation-transaction-hash "$PROXY_CREATION_TX" \
  --watch || true

echo ""
echo "== Example: direct-deploy DravanaSynthetic (no proxy) — verified with current monorepo source =="
DIRECT_ADDR="${DIRECT_ADDR:-0x3D8B9f4a70D004B1b6b8708C1bA71160aF03ce6c}"
DIRECT_CREATION_TX="${DIRECT_CREATION_TX:-0xc43c19f75ebd54c3f1e96506bb7c4fa035279ce5e6f15f08453afe110f504664}"
forge verify-contract "$DIRECT_ADDR" \
  contracts/token/DravanaSynthetic.sol:DravanaSynthetic \
  --chain "$CHAIN_ID" \
  --verifier blockscout \
  --verifier-url "$VERIFIER_URL" \
  --etherscan-api-key "$API_KEY" \
  --compiler-version "$SOLC_VERSION" \
  --num-of-optimizations "$OPT_RUNS" \
  --creation-transaction-hash "$DIRECT_CREATION_TX" \
  --watch || true

echo ""
echo "If verification fails with 'Unable to verify':"
echo "  - Implementation bytecode on-chain did not match contracts/token/DravanaSynthetic.sol"
echo "    at solc $SOLC_VERSION / optimizer $OPT_RUNS (deploy may have used different settings or source)."
echo "  - Proxy may need the exact OZ revision and settings used at deploy time."
echo "Use: forge verify-contract ... --show-standard-json-input  for manual Blockscout upload."
