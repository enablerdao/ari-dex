/** Supported blockchain network identifiers, matching Rust ChainId enum. */
export enum ChainId {
  Solana = 0,
  Ethereum = 1,
  Arbitrum = 42161,
  Base = 8453,
}

/** A fungible token on a specific chain. */
export interface Token {
  chain: ChainId;
  /** Contract address as hex string (0x-prefixed, 20 bytes). */
  address: string;
  /** Human-readable ticker symbol (e.g. "USDC"). */
  symbol: string;
  /** Number of decimal places (e.g. 18 for ETH, 6 for USDC). */
  decimals: number;
}

/** An ordered pair of tokens identifying a market. */
export interface TokenPair {
  base: Token;
  quote: Token;
}

/** Lifecycle status of an intent. */
export type IntentStatus =
  | "Pending"
  | "Encrypted"
  | "Batched"
  | "Matched"
  | "Settled"
  | "Expired"
  | "Cancelled";

/** A trade intent submitted by a user. */
export interface Intent {
  /** Unique intent ID (hex-encoded 32-byte hash). */
  id?: string;
  /** Sender address (0x-prefixed). */
  sender: string;
  sellToken: Token;
  buyToken: Token;
  /** Sell amount as decimal string (raw units). */
  sellAmount: string;
  /** Desired buy amount as decimal string. */
  buyAmount: string;
  /** Minimum acceptable buy amount after slippage. */
  minBuy: string;
  /** Unix timestamp after which the intent expires. */
  deadline: number;
  srcChain: ChainId;
  /** Destination chain (undefined if same-chain swap). */
  dstChain?: ChainId;
  partialFill: boolean;
  nonce: number;
  /** ECDSA signature hex string. */
  signature: string;
  status?: IntentStatus;
}

/** A single routing hop within a solution. */
export interface Hop {
  /** Pool or venue address. */
  pool: string;
  tokenIn: Token;
  tokenOut: Token;
  /** Amount in, decimal string. */
  amountIn: string;
  /** Amount out, decimal string. */
  amountOut: string;
}

/** A solver's proposed execution plan for one or more intents. */
export interface Solution {
  /** Intent ID this solution fulfills. */
  intentId: string;
  /** Solver address. */
  solver: string;
  /** Ordered list of hops forming the execution route. */
  hops: Hop[];
  /** Total output amount (decimal string). */
  totalOutput: string;
  /** Gas estimate in native token units. */
  gasEstimate: string;
  /** Score assigned by the auction (higher is better). */
  score?: number;
}

/** A liquidity pool. */
export interface Pool {
  /** Pool contract address. */
  address: string;
  chain: ChainId;
  pair: TokenPair;
  feeTier: number;
  /** Total value locked, decimal string. */
  tvl: string;
  /** Current sqrt price (Q64.96 encoded as string). */
  sqrtPrice: string;
  /** Current tick index. */
  tick: number;
}

/** Quote response from GET /v1/quote. */
export interface QuoteResponse {
  sellToken: Token;
  buyToken: Token;
  sellAmount: string;
  buyAmount: string;
  /** Price impact as a percentage string (e.g. "0.05"). */
  priceImpact: string;
  /** Estimated route. */
  route: Hop[];
  /** Quote validity deadline (unix timestamp). */
  validUntil: number;
}
