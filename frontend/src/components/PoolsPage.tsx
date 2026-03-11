import { useEffect, useState } from "react";
import { API_URL } from "../config";

interface Pool {
  address: string;
  token0: string;
  token1: string;
  fee_tier: number;
  liquidity: string;
}

export function PoolsPage() {
  const [pools, setPools] = useState<Pool[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`${API_URL}/v1/pools`)
      .then((r) => r.json())
      .then((d) => { setPools(d.pools || []); setLoading(false); })
      .catch(() => setLoading(false));
  }, []);

  return (
    <div className="page-panel">
      <h2 className="page-title">Liquidity Pools</h2>
      <p className="page-sub">Active Uniswap V3 pools routed by ARI solvers</p>

      {loading ? (
        <div className="page-loading">Loading pools...</div>
      ) : (
        <div className="page-table-wrap">
          <table className="page-table">
            <thead>
              <tr>
                <th>Pair</th>
                <th>Fee Tier</th>
                <th>Liquidity</th>
                <th>Contract</th>
              </tr>
            </thead>
            <tbody>
              {pools.map((p) => (
                <tr key={p.address}>
                  <td className="page-pair">
                    <span className="page-pair-token">{p.token0}</span>
                    <span className="page-pair-sep">/</span>
                    <span className="page-pair-token">{p.token1}</span>
                  </td>
                  <td>{(p.fee_tier / 10000).toFixed(2)}%</td>
                  <td>{formatLiquidity(p.liquidity)}</td>
                  <td>
                    <a
                      href={`https://etherscan.io/address/${p.address}`}
                      target="_blank"
                      rel="noopener noreferrer"
                      className="page-link"
                    >
                      {p.address.slice(0, 8)}...{p.address.slice(-4)}
                    </a>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}

function formatLiquidity(raw: string): string {
  const n = parseFloat(raw);
  if (n >= 1e18) return `${(n / 1e18).toFixed(1)} ETH`;
  if (n >= 1e12) return `${(n / 1e6).toFixed(0)} USDC`;
  return raw;
}
