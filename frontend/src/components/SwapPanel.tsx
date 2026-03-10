import { useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useQuote } from "../hooks/useQuote";
import { useSubmitIntent } from "../hooks/useSubmitIntent";
import type { Token } from "../types";
import { ChainId } from "../types";

/** Placeholder token list. */
const TOKENS: Token[] = [
  { chain: ChainId.Ethereum, address: "0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE", symbol: "ETH", decimals: 18 },
  { chain: ChainId.Ethereum, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0x6B175474E89094C44Da98b954EedeAC495271d0F", symbol: "DAI", decimals: 18 },
];

export function SwapPanel() {
  const { isConnected } = useAccount();

  const [sellToken, setSellToken] = useState<Token>(TOKENS[0]);
  const [buyToken, setBuyToken] = useState<Token>(TOKENS[1]);
  const [sellAmount, setSellAmount] = useState("");

  const { data: quote, isLoading: quoteLoading } = useQuote(
    sellToken,
    buyToken,
    sellAmount,
  );

  const { submit, isPending: submitPending } = useSubmitIntent();

  const handleSwapTokens = useCallback(() => {
    setSellToken(buyToken);
    setBuyToken(sellToken);
    setSellAmount("");
  }, [sellToken, buyToken]);

  const handleSubmit = useCallback(() => {
    if (!sellAmount || !quote) return;
    submit({
      sellToken,
      buyToken,
      sellAmount,
      minBuyAmount: quote.buyAmount,
    });
  }, [sellToken, buyToken, sellAmount, quote, submit]);

  const buttonLabel = !isConnected
    ? "Connect Wallet"
    : !sellAmount
      ? "Enter Amount"
      : quoteLoading
        ? "Fetching Quote..."
        : submitPending
          ? "Submitting..."
          : "Swap";

  const buttonDisabled =
    !isConnected || !sellAmount || quoteLoading || submitPending;

  return (
    <div className="swap-panel">
      <h2 className="swap-panel-title">Swap</h2>

      {/* Sell section */}
      <div className="swap-panel-section">
        <label className="swap-panel-label">Sell</label>
        <div className="swap-panel-row">
          <input
            className="swap-panel-input"
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={sellAmount}
            onChange={(e) => setSellAmount(e.target.value)}
          />
          <select
            className="swap-panel-token-select"
            value={sellToken.symbol}
            onChange={(e) => {
              const t = TOKENS.find((tk) => tk.symbol === e.target.value);
              if (t) setSellToken(t);
            }}
          >
            {TOKENS.map((t) => (
              <option key={t.address} value={t.symbol}>
                {t.symbol}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Swap direction button */}
      <button className="swap-panel-flip" onClick={handleSwapTokens}>
        ↕
      </button>

      {/* Buy section */}
      <div className="swap-panel-section">
        <label className="swap-panel-label">Buy</label>
        <div className="swap-panel-row">
          <input
            className="swap-panel-input"
            type="text"
            inputMode="decimal"
            placeholder="0.0"
            value={quote?.buyAmount ?? ""}
            readOnly
          />
          <select
            className="swap-panel-token-select"
            value={buyToken.symbol}
            onChange={(e) => {
              const t = TOKENS.find((tk) => tk.symbol === e.target.value);
              if (t) setBuyToken(t);
            }}
          >
            {TOKENS.map((t) => (
              <option key={t.address} value={t.symbol}>
                {t.symbol}
              </option>
            ))}
          </select>
        </div>
      </div>

      {/* Quote details */}
      {quote && (
        <div className="swap-panel-details">
          <div className="swap-panel-detail-row">
            <span>Price Impact</span>
            <span>{quote.priceImpact}%</span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Route</span>
            <span>
              {quote.route.map((h) => h.tokenOut.symbol).join(" → ")}
            </span>
          </div>
        </div>
      )}

      {/* Submit button */}
      <button
        className="swap-panel-submit"
        disabled={buttonDisabled}
        onClick={handleSubmit}
      >
        {buttonLabel}
      </button>
    </div>
  );
}
