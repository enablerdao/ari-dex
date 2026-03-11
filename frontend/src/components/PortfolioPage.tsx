import { useEffect, useState } from "react";
import { useAccount } from "wagmi";
import { API_URL } from "../config";

interface Holding {
  token: string;
  balance: string;
  value_usd: number;
  allocation_pct: number;
}

interface Trade {
  intent_id: string;
  sell_token: string;
  buy_token: string;
  sell_amount: string;
  timestamp: number;
  status: string;
}

export function PortfolioPage() {
  const { address, isConnected } = useAccount();
  const [holdings, setHoldings] = useState<Holding[]>([]);
  const [trades, setTrades] = useState<Trade[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!address) { setLoading(false); return; }

    Promise.all([
      fetch(`${API_URL}/v1/portfolio/${address}`).then((r) => r.json()).catch(() => null),
      fetch(`${API_URL}/v1/history/${address}`).then((r) => r.json()).catch(() => null),
    ]).then(([portfolio, history]) => {
      if (portfolio?.holdings) setHoldings(portfolio.holdings);
      if (history?.trades) setTrades(history.trades);
      setLoading(false);
    });
  }, [address]);

  if (!isConnected) {
    return (
      <div className="page-panel">
        <h2 className="page-title">Portfolio</h2>
        <div className="page-empty">Connect your wallet to view portfolio</div>
      </div>
    );
  }

  const totalValue = holdings.reduce((sum, h) => sum + h.value_usd, 0);

  return (
    <div className="page-panel">
      <h2 className="page-title">Portfolio</h2>
      <p className="page-sub">{address?.slice(0, 8)}...{address?.slice(-4)}</p>

      {loading ? (
        <div className="page-loading">Loading portfolio...</div>
      ) : (
        <>
          <div className="page-stat-row">
            <div className="page-stat">
              <span className="page-stat-label">Total Value</span>
              <span className="page-stat-value">${totalValue.toLocaleString("en-US", { maximumFractionDigits: 2 })}</span>
            </div>
            <div className="page-stat">
              <span className="page-stat-label">Assets</span>
              <span className="page-stat-value">{holdings.length}</span>
            </div>
            <div className="page-stat">
              <span className="page-stat-label">Trades</span>
              <span className="page-stat-value">{trades.length}</span>
            </div>
          </div>

          {holdings.length > 0 && (
            <>
              <h3 className="page-section-title">Holdings</h3>
              <div className="page-table-wrap">
                <table className="page-table">
                  <thead>
                    <tr><th>Token</th><th>Balance</th><th>Value</th><th>%</th></tr>
                  </thead>
                  <tbody>
                    {holdings.map((h) => (
                      <tr key={h.token}>
                        <td className="page-pair-token">{h.token}</td>
                        <td>{parseFloat(h.balance).toLocaleString("en-US", { maximumFractionDigits: 6 })}</td>
                        <td>${h.value_usd.toLocaleString("en-US", { maximumFractionDigits: 2 })}</td>
                        <td>{h.allocation_pct.toFixed(1)}%</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          {trades.length > 0 && (
            <>
              <h3 className="page-section-title">Recent Trades</h3>
              <div className="page-table-wrap">
                <table className="page-table">
                  <thead>
                    <tr><th>Pair</th><th>Amount</th><th>Status</th><th>Time</th></tr>
                  </thead>
                  <tbody>
                    {trades.slice(0, 20).map((t) => (
                      <tr key={t.intent_id}>
                        <td>{t.sell_token} &rarr; {t.buy_token}</td>
                        <td>{t.sell_amount}</td>
                        <td><span className={`page-status page-status--${t.status}`}>{t.status}</span></td>
                        <td>{new Date(t.timestamp * 1000).toLocaleString()}</td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              </div>
            </>
          )}

          {holdings.length === 0 && trades.length === 0 && (
            <div className="page-empty">No holdings or trade history yet. Start swapping!</div>
          )}
        </>
      )}
    </div>
  );
}
