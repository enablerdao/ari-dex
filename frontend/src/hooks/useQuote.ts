import { useQuery } from "@tanstack/react-query";
import { API_URL } from "../config";
import type { Token } from "../types";

/** Response shape from GET /v1/quote (matches Rust API). */
export interface ApiQuoteResponse {
  sell_token: string;
  buy_token: string;
  sell_amount: string;
  buy_amount: string;
  price: string;
  price_impact: string;
  route: string[];
}

/**
 * Fetches a swap quote from GET /v1/quote.
 * Sends token symbols and raw amount; returns estimated output.
 */
export function useQuote(
  sellToken: Token,
  buyToken: Token,
  sellAmount: string,
) {
  return useQuery<ApiQuoteResponse>({
    queryKey: ["quote", sellToken.symbol, buyToken.symbol, sellAmount],
    queryFn: async () => {
      // Convert human-readable amount to raw units
      const rawAmount = BigInt(
        Math.floor(parseFloat(sellAmount || "0") * 10 ** sellToken.decimals),
      ).toString();

      const params = new URLSearchParams({
        sell_token: sellToken.symbol,
        buy_token: buyToken.symbol,
        sell_amount: rawAmount,
      });

      const res = await fetch(`${API_URL}/v1/quote?${params}`);
      if (!res.ok) {
        throw new Error(`Quote request failed: ${res.status}`);
      }
      return res.json() as Promise<ApiQuoteResponse>;
    },
    enabled: Boolean(sellAmount) && parseFloat(sellAmount) > 0,
    staleTime: 10_000,
    refetchInterval: 15_000,
  });
}
