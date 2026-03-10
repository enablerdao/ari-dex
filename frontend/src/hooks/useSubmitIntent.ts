import { useMutation } from "@tanstack/react-query";
import { API_URL } from "../config";
import type { Token } from "../types";

interface SubmitIntentParams {
  sellToken: Token;
  buyToken: Token;
  sellAmount: string;
  minBuyAmount: string;
  sender?: string;
}

interface SubmitIntentResult {
  intent_id: string;
  status: string;
}

/**
 * Submits a trade intent via POST /v1/intents.
 * Matches the Rust API's expected JSON body shape.
 */
export function useSubmitIntent() {
  const mutation = useMutation<SubmitIntentResult, Error, SubmitIntentParams>({
    mutationFn: async (params) => {
      const rawSellAmount = BigInt(
        Math.floor(
          parseFloat(params.sellAmount || "0") *
            10 ** params.sellToken.decimals,
        ),
      ).toString();

      const payload = {
        sender: params.sender ?? "0x0000000000000000000000000000000000000000",
        sell_token: params.sellToken.symbol,
        buy_token: params.buyToken.symbol,
        sell_amount: rawSellAmount,
        min_buy_amount: params.minBuyAmount,
      };

      const res = await fetch(`${API_URL}/v1/intents`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) {
        throw new Error(`Intent submission failed: ${res.status}`);
      }

      return res.json() as Promise<SubmitIntentResult>;
    },
  });

  return {
    submit: mutation.mutate,
    submitAsync: mutation.mutateAsync,
    isPending: mutation.isPending,
    error: mutation.error,
    data: mutation.data,
  };
}
