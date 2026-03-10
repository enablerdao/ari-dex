import { useState, useCallback } from "react";
import { useAccount } from "wagmi";
import { useQuote } from "../hooks/useQuote";
import { useSubmitIntent } from "../hooks/useSubmitIntent";
import { useSignIntent } from "../hooks/useSignIntent";
import type { Token } from "../types";
import { ChainId } from "../types";

/** Token list matching the API's hardcoded tokens. */
const TOKENS: Token[] = [
  { chain: ChainId.Ethereum, address: "0x0000000000000000000000000000000000000000", symbol: "ETH", decimals: 18 },
  { chain: ChainId.Ethereum, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0x6B175474E89094C44Da98b954EedeAC495271d0F", symbol: "DAI", decimals: 18 },
  { chain: ChainId.Ethereum, address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", symbol: "WBTC", decimals: 8 },
];

export function SwapPanel() {
  const { address, isConnected } = useAccount();

  const [sellToken, setSellToken] = useState<Token>(TOKENS[0]);
  const [buyToken, setBuyToken] = useState<Token>(TOKENS[1]);
  const [sellAmount, setSellAmount] = useState("");
  const [submitted, setSubmitted] = useState<string | null>(null);

  const { data: quote, isLoading: quoteLoading } = useQuote(
    sellToken,
    buyToken,
    sellAmount,
  );

  const { submit, isPending: submitPending } = useSubmitIntent();
  const { signIntent, isSigning } = useSignIntent();

  const isSameToken = sellToken.symbol === buyToken.symbol;

  const handleSwapTokens = useCallback(() => {
    setSellToken(buyToken);
    setBuyToken(sellToken);
    setSellAmount("");
    setSubmitted(null);
  }, [sellToken, buyToken]);

  const handleSubmit = useCallback(async () => {
    if (!sellAmount || !quote || isSameToken) return;

    let signature: string | undefined;
    let deadline: string | undefined;
    let nonce: string | undefined;

    if (isConnected && address) {
      try {
        const result = await signIntent({
          sender: address,
          sellToken,
          buyToken,
          sellAmount,
          minBuyAmount: quote.buy_amount,
        });
        signature = result.signature;
        deadline = result.deadline;
        nonce = result.nonce;
      } catch {
        // User rejected signing or wallet error — abort
        return;
      }
    }

    submit(
      {
        sellToken,
        buyToken,
        sellAmount,
        minBuyAmount: quote.buy_amount,
        sender: address,
        signature,
        deadline,
        nonce,
      },
      {
        onSuccess: (data) => setSubmitted(data.intent_id),
      },
    );
  }, [sellToken, buyToken, sellAmount, quote, submit, address, isConnected, signIntent, isSameToken]);

  // Format buy amount from raw to human-readable
  const formatBuyAmount = () => {
    if (!quote) return "";
    const raw = parseFloat(quote.buy_amount);
    const decimals = buyToken.decimals;
    return (raw / 10 ** decimals).toFixed(decimals > 8 ? 6 : 2);
  };

  const buttonLabel = isSameToken
    ? "Select Different Tokens"
    : !sellAmount
      ? "Enter Amount"
      : quoteLoading
        ? "Fetching Quote..."
        : isSigning
          ? "Signing..."
          : submitPending
            ? "Submitting Intent..."
            : isConnected
              ? "Sign & Swap"
              : "Connect Wallet to Swap";

  const buttonDisabled = !sellAmount || quoteLoading || submitPending || isSigning || isSameToken || !isConnected;

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
            onChange={(e) => {
              const val = e.target.value;
              if (val === "" || /^\d*\.?\d*$/.test(val)) {
                setSellAmount(val);
                setSubmitted(null);
              }
            }}
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
        &darr;
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
            value={formatBuyAmount()}
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

      {/* Same-token warning */}
      {isSameToken && (
        <div className="swap-panel-warning">
          Cannot swap a token for itself. Please select different tokens.
        </div>
      )}

      {/* Quote details */}
      {quote && !isSameToken && (
        <div className="swap-panel-details">
          <div className="swap-panel-detail-row">
            <span>Price</span>
            <span>
              1 {sellToken.symbol} = {parseFloat(quote.price).toFixed(2)}{" "}
              {buyToken.symbol}
            </span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Price Impact</span>
            <span>{quote.price_impact}%</span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Route</span>
            <span>{quote.route.join(" -> ")}</span>
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

      {/* Success message */}
      {submitted && (
        <div className="swap-panel-success">
          Intent submitted! ID: {submitted.slice(0, 10)}...{submitted.slice(-6)}
        </div>
      )}
    </div>
  );
}
