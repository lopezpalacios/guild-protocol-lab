// Shared client config and helpers. Imported by every page.
import { defineChain, createPublicClient, http, parseAbi, formatUnits } from "https://esm.sh/viem@2.21.45";

export { formatUnits, parseAbi };

import { CONFIG } from "./config.js";
export { CONFIG };

export const CHAIN = defineChain({
  id: CONFIG.chainId,
  name: CONFIG.chainName,
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  rpcUrls: { default: { http: [CONFIG.rpcUrl] } },
  blockExplorers: { default: { name: "Explorer", url: CONFIG.explorer } },
  testnet: true,
});

export const publicClient = createPublicClient({
  chain: CHAIN,
  transport: http(CONFIG.rpcUrl, { timeout: 10_000 }),
});

export const ABI = {
  ballot: parseAbi([
    "function castVotes(bytes32 pollId, address[] signers, uint8[] choices, bytes[] sigs)",
    "function tallyOf(bytes32 pollId) view returns (uint256[])",
    "function nonce(address) view returns (uint256)",
    "function hasVoted(bytes32 pollId, address) view returns (bool)",
    "function winner(bytes32 pollId) view returns (uint8)",
    "function polls(bytes32) view returns (string label, uint8 optionCount, uint8 mode, uint64 opensAt, uint64 closesAt, bool exists, bool finalized)",
    "function ballotDigest(bytes32 pollId, uint8 choice, address signer) view returns (bytes32)",
  ]),
  badge: parseAbi([
    "function claim(uint8 guildId, bytes route) returns (uint256)",
    "function claimFor(address to, uint8 guildId, bytes route) returns (uint256)",
    "function nextId() view returns (uint256)",
    "function hasClaimed(address) view returns (bool)",
    "function tokenURI(uint256) view returns (string)",
  ]),
  distributor: parseAbi([
    "function claim(uint256 index, address account, uint256 amount, bytes32[] proof)",
    "function claimed(address) view returns (bool)",
  ]),
  loot: parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function symbol() view returns (string)",
    "function decimals() view returns (uint8)",
  ]),
  pair: parseAbi([
    "function spotPrice() view returns (uint256)",
    "function getReserves() view returns (uint256, uint256)",
    "function getAmountOut(address tokenIn, uint256 amountIn) view returns (uint256)",
    "function priceImpactBps(address tokenIn, uint256 amountIn) view returns (uint256)",
    "function swapCount() view returns (uint256)",
    "function token0() view returns (address)",
    "function token1() view returns (address)",
    "function swap(address tokenIn, uint256 amountIn, uint256 minOut) returns (uint256)",
    "function maxTrade() view returns (uint256)",
  ]),
  erc20: parseAbi([
    "function balanceOf(address) view returns (uint256)",
    "function approve(address, uint256) returns (bool)",
    "function allowance(address, address) view returns (uint256)",
  ]),
};

/** Encounter route for this run, encoded as bytes. Set at deploy time. */
export const ROUTE = "0x0102050709";

/** Format a big number to 2dp for the projector. */
export function fmt(n, dp = 2) {
  return Number(formatUnits(n, 18)).toLocaleString("en-CH", {
    minimumFractionDigits: dp,
    maximumFractionDigits: dp,
  });
}

export function short(addr) {
  return addr ? `${addr.slice(0, 6)}…${addr.slice(-4)}` : "—";
}

export function pollFromQuery() {
  const p = new URLSearchParams(location.search).get("poll");
  return p === "2" ? { id: CONFIG.poll2, label: "POLL 2" } : { id: CONFIG.poll1, label: "POLL 1" };
}

export async function pollState(pollId) {
  const [meta, tally] = await Promise.all([
    publicClient.readContract({ address: CONFIG.ballot, abi: ABI.ballot, functionName: "polls", args: [pollId] }),
    publicClient.readContract({ address: CONFIG.ballot, abi: ABI.ballot, functionName: "tallyOf", args: [pollId] }),
  ]);
  const [label, optionCount, mode, opensAt, closesAt, exists, finalized] = meta;
  return { label, optionCount, mode, opensAt, closesAt, exists, finalized, tally };
}
