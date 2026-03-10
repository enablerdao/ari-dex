import { useState, useCallback, useEffect } from "react";
import { useAccount } from "wagmi";
import { useQuote } from "../hooks/useQuote";
import { useSubmitIntent } from "../hooks/useSubmitIntent";
import { useSignIntent } from "../hooks/useSignIntent";
import type { Token } from "../types";
import { ChainId } from "../types";
import { API_URL } from "../config";

const TOKENS: Token[] = [
  { chain: ChainId.Ethereum, address: "0x0000000000000000000000000000000000000000", symbol: "ETH", decimals: 18 },
  { chain: ChainId.Ethereum, address: "0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48", symbol: "USDC", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0xdAC17F958D2ee523a2206206994597C13D831ec7", symbol: "USDT", decimals: 6 },
  { chain: ChainId.Ethereum, address: "0x6B175474E89094C44Da98b954EedeAC495271d0F", symbol: "DAI", decimals: 18 },
  { chain: ChainId.Ethereum, address: "0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599", symbol: "WBTC", decimals: 8 },
];

const TOKEN_ICONS: Record<string, string> = {
  ETH: "\u039E",
  USDC: "$",
  USDT: "\u20AE",
  DAI: "\u25C8",
  WBTC: "\u20BF",
};

export function SwapPanel() {
  const { address, isConnected } = useAccount();

  const [sellToken, setSellToken] = useState<Token>(TOKENS[0]);
  const [buyToken, setBuyToken] = useState<Token>(TOKENS[1]);
  const [sellAmount, setSellAmount] = useState("");
  const [submitted, setSubmitted] = useState<string | null>(null);
  const [livePrice, setLivePrice] = useState<Record<string, number>>({});

  // Fetch live prices via WS
  useEffect(() => {
    let ws: WebSocket | null = null;
    try {
      const wsUrl = API_URL
        ? API_URL.replace(/^http/, "ws") + "/ws"
        : `${window.location.protocol === "https:" ? "wss:" : "ws:"}//${window.location.host}/ws`;
      ws = new WebSocket(wsUrl);
      ws.onopen = () => {
        ws?.send(JSON.stringify({ subscribe: "prices" }));
      };
      ws.onmessage = (e) => {
        try {
          const data = JSON.parse(e.data);
          if (data.pair && data.price) {
            setLivePrice((prev) => ({ ...prev, [data.pair]: data.price }));
          }
        } catch { /* ignore */ }
      };
    } catch { /* ignore */ }
    return () => ws?.close();
  }, []);

  const { data: quote, isLoading: quoteLoading } = useQuote(sellToken, buyToken, sellAmount);
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

  const formatBuyAmount = () => {
    if (!quote) return "";
    const raw = parseFloat(quote.buy_amount);
    const decimals = buyToken.decimals;
    return (raw / 10 ** decimals).toLocaleString("en-US", {
      minimumFractionDigits: 2,
      maximumFractionDigits: decimals > 8 ? 6 : 2,
    });
  };

  const formatUsdValue = () => {
    if (!quote) return "";
    const amt = parseFloat(sellAmount || "0");
    if (sellToken.symbol === "ETH" && livePrice["ETH/USDC"]) {
      return `$${(amt * livePrice["ETH/USDC"]).toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
    }
    if (sellToken.symbol === "USDC" || sellToken.symbol === "USDT" || sellToken.symbol === "DAI") {
      return `$${amt.toLocaleString("en-US", { maximumFractionDigits: 2 })}`;
    }
    return "";
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
      <div className="swap-panel-header">
        <h2 className="swap-panel-title">Swap</h2>
        <div className="swap-panel-settings">
          <button className="swap-panel-setting-btn">0.5% slippage</button>
        </div>
      </div>

      {/* Sell */}
      <div className="swap-panel-section">
        <div className="swap-panel-section-header">
          <label className="swap-panel-label">You pay</label>
          <span className="swap-panel-balance" />
        </div>
        <div className="swap-panel-row">
          <input
            className="swap-panel-input"
            type="text"
            inputMode="decimal"
            placeholder="0"
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
                {TOKEN_ICONS[t.symbol] || ""} {t.symbol}
              </option>
            ))}
          </select>
        </div>
        {sellAmount && (
          <div className="swap-panel-usd">{formatUsdValue()}</div>
        )}
      </div>

      {/* Flip */}
      <button className="swap-panel-flip" onClick={handleSwapTokens} aria-label="Swap tokens">
        &#8595;
      </button>

      {/* Buy */}
      <div className="swap-panel-section">
        <div className="swap-panel-section-header">
          <label className="swap-panel-label">You receive</label>
        </div>
        <div className="swap-panel-row">
          <input
            className={`swap-panel-input ${quoteLoading ? "loading" : ""}`}
            type="text"
            inputMode="decimal"
            placeholder="0"
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
                {TOKEN_ICONS[t.symbol] || ""} {t.symbol}
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
            <span>Rate</span>
            <span>
              1 {sellToken.symbol} = {parseFloat(quote.price).toLocaleString("en-US", { maximumFractionDigits: 2 })}{" "}
              {buyToken.symbol}
            </span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Price Impact</span>
            <span style={{ color: parseFloat(quote.price_impact) > 1 ? "var(--red)" : "var(--green)" }}>
              {quote.price_impact}%
            </span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Route</span>
            <span className="swap-panel-route">
              {quote.route.map((token, i) => (
                <span key={i}>
                  {i > 0 && <span className="swap-panel-route-arrow"> → </span>}
                  <span className="swap-panel-route-token">{token}</span>
                </span>
              ))}
            </span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Fee</span>
            <span>0.05%</span>
          </div>
          <div className="swap-panel-detail-row">
            <span>Settlement</span>
            <span style={{ color: "var(--accent)" }}>Intent-based</span>
          </div>
        </div>
      )}

      {/* Submit */}
      <button
        className={`swap-panel-submit ${!isConnected && sellAmount ? "swap-panel-submit--connect" : ""}`}
        disabled={buttonDisabled}
        onClick={handleSubmit}
      >
        {buttonLabel}
      </button>

      {/* Success */}
      {submitted && (
        <div className="swap-panel-success">
          <span>&#10003;</span>
          Intent submitted: {submitted.slice(0, 10)}...{submitted.slice(-6)}
        </div>
      )}
    </div>
  );
}
