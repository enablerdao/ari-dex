import { useSignTypedData, useChainId } from "wagmi";
import { useCallback } from "react";
import { parseUnits } from "viem";
import { CONTRACTS, INTENT_EXPIRY_SECONDS } from "../config";
import type { Token } from "../types";

/** EIP-712 domain for ARI Exchange intent signing. */
function getDomain(chainId: number) {
  return {
    name: "ARI Exchange",
    version: "1",
    chainId: BigInt(chainId),
    verifyingContract: CONTRACTS.settlement,
  } as const;
}

/** EIP-712 type definition for Intent struct. */
const INTENT_TYPES = {
  Intent: [
    { name: "sender", type: "address" },
    { name: "sellToken", type: "address" },
    { name: "buyToken", type: "address" },
    { name: "sellAmount", type: "uint256" },
    { name: "minBuyAmount", type: "uint256" },
    { name: "deadline", type: "uint256" },
    { name: "nonce", type: "uint256" },
  ],
} as const;

export interface SignIntentParams {
  sender: string;
  sellToken: Token;
  buyToken: Token;
  sellAmount: string;
  minBuyAmount: string;
  nonce?: number;
}

export interface SignIntentResult {
  signature: string;
  deadline: string;
  nonce: string;
}

export function useSignIntent() {
  const chainId = useChainId();
  const { signTypedDataAsync, isPending } = useSignTypedData();

  const signIntent = useCallback(
    async (params: SignIntentParams): Promise<SignIntentResult> => {
      if (CONTRACTS.settlement === "0x0000000000000000000000000000000000000000") {
        console.warn("Settlement contract is zero address — signature may be invalid on-chain");
      }

      const deadline = BigInt(Math.floor(Date.now() / 1000) + INTENT_EXPIRY_SECONDS);
      const nonce = BigInt(params.nonce ?? Date.now());

      const rawSellAmount = parseUnits(params.sellAmount || "0", params.sellToken.decimals);

      const signature = await signTypedDataAsync({
        domain: getDomain(chainId),
        types: INTENT_TYPES,
        primaryType: "Intent",
        message: {
          sender: params.sender as `0x${string}`,
          sellToken: params.sellToken.address as `0x${string}`,
          buyToken: params.buyToken.address as `0x${string}`,
          sellAmount: rawSellAmount,
          minBuyAmount: BigInt(params.minBuyAmount),
          deadline,
          nonce,
        },
      });

      return {
        signature,
        deadline: deadline.toString(),
        nonce: nonce.toString(),
      };
    },
    [chainId, signTypedDataAsync],
  );

  return { signIntent, isSigning: isPending };
}
