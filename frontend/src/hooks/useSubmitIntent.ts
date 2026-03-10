import { useMutation } from "@tanstack/react-query";
import { API_URL, INTENT_EXPIRY_SECONDS } from "../config";
import type { Token, Intent } from "../types";

interface SubmitIntentParams {
  sellToken: Token;
  buyToken: Token;
  sellAmount: string;
  minBuyAmount: string;
}

interface SubmitIntentResult {
  intentId: string;
  status: string;
}

/**
 * Submits a trade intent via POST /v1/intents.
 *
 * In production this would sign the intent with the user's wallet
 * before submitting. Currently sends an unsigned placeholder payload.
 */
export function useSubmitIntent() {
  const mutation = useMutation<SubmitIntentResult, Error, SubmitIntentParams>({
    mutationFn: async (params) => {
      const deadline = Math.floor(Date.now() / 1000) + INTENT_EXPIRY_SECONDS;

      // TODO: Sign intent with wallet (EIP-712 typed data)
      const payload: Partial<Intent> = {
        sender: "0x0000000000000000000000000000000000000000",
        sellToken: params.sellToken,
        buyToken: params.buyToken,
        sellAmount: params.sellAmount,
        buyAmount: params.minBuyAmount,
        minBuy: params.minBuyAmount,
        deadline,
        srcChain: params.sellToken.chain,
        partialFill: false,
        nonce: Date.now(),
        signature: "0x" + "00".repeat(65),
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
