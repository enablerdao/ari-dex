import { ChainId } from "./types";

/** Base URL for the ARI gateway API. */
export const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:8080";

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

/** Placeholder contract addresses. */
export const CONTRACTS = {
  /** ARI Settlement contract. */
  settlement: "0x0000000000000000000000000000000000000000" as const,
  /** ARI Intent mempool. */
  intentPool: "0x0000000000000000000000000000000000000000" as const,
} as const;

/** Default slippage tolerance (0.5%). */
export const DEFAULT_SLIPPAGE_BPS = 50;

/** Intent expiry duration in seconds (5 minutes). */
export const INTENT_EXPIRY_SECONDS = 300;
