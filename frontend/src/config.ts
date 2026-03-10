import { ChainId } from "./types";

/** Base URL for the ARI gateway API. */
const rawUrl = import.meta.env.VITE_API_URL ?? "http://localhost:3000";
if (import.meta.env.PROD && !rawUrl.startsWith("https://")) {
  console.error("API_URL must use HTTPS in production");
}
export const API_URL = rawUrl;

/** Supported chains and their RPC endpoints. */
export const SUPPORTED_CHAINS = [
  {
    chainId: ChainId.Ethereum,
    name: "Ethereum",
    rpcUrl: "https://eth.llamarpc.com",
    blockExplorer: "https://etherscan.io",
  },
  {
    chainId: ChainId.Arbitrum,
    name: "Arbitrum",
    rpcUrl: "https://arb1.arbitrum.io/rpc",
    blockExplorer: "https://arbiscan.io",
  },
  {
    chainId: ChainId.Base,
    name: "Base",
    rpcUrl: "https://mainnet.base.org",
    blockExplorer: "https://basescan.org",
  },
] as const;

/** Contract addresses — set via env vars; zero-address fallback is a placeholder for local dev only. */
export const CONTRACTS = {
  /** ARI Settlement contract. */
  settlement: (import.meta.env.VITE_SETTLEMENT_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
  /** ARI Intent mempool. */
  intentPool: (import.meta.env.VITE_INTENT_POOL_ADDRESS ?? "0x0000000000000000000000000000000000000000") as `0x${string}`,
} as const;

/** Default slippage tolerance (0.5%). */
export const DEFAULT_SLIPPAGE_BPS = 50;

/** Intent expiry duration in seconds (5 minutes). */
export const INTENT_EXPIRY_SECONDS = 300;
