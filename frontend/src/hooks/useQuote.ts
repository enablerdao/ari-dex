import { useQuery } from "@tanstack/react-query";
import { API_URL } from "../config";
import type { Token, QuoteResponse } from "../types";

/**
 * Fetches a swap quote from GET /v1/quote.
 *
 * Returns estimated output amount and route for the given token pair and amount.
 * The query is disabled when sellAmount is empty or zero.
 */
export function useQuote(
  sellToken: Token,
  buyToken: Token,
  sellAmount: string,
) {
  return useQuery<QuoteResponse>({
    queryKey: ["quote", sellToken.address, buyToken.address, sellAmount],
    queryFn: async () => {
      const params = new URLSearchParams({
        sellToken: sellToken.address,
        buyToken: buyToken.address,
        sellAmount,
        srcChain: String(sellToken.chain),
      });

      const res = await fetch(`${API_URL}/v1/quote?${params}`);
      if (!res.ok) {
        throw new Error(`Quote request failed: ${res.status}`);
      }
      return res.json() as Promise<QuoteResponse>;
    },
    enabled: Boolean(sellAmount) && sellAmount !== "0",
    staleTime: 10_000,
    refetchInterval: 15_000,
  });
}
