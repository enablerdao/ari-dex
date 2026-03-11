import { useEffect, useState } from "react";
import { API_URL } from "../config";

interface Solver {
  id: string;
  address: string;
  name: string;
  fill_rate: number;
  avg_improvement: number;
  total_volume: string;
  total_fills: number;
  score: number;
  active: boolean;
}

export function SolversPage() {
  const [solvers, setSolvers] = useState<Solver[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch(`${API_URL}/v1/solvers`)
      .then((r) => r.json())
      .then((d) => { setSolvers(d.solvers || []); setLoading(false); })
      .catch(() => setLoading(false));
  }, []);

  return (
    <div className="page-panel">
      <h2 className="page-title">Solver Network</h2>
      <p className="page-sub">Competitive solvers competing to fill your intents with optimal execution</p>

      {loading ? (
        <div className="page-loading">Loading solvers...</div>
      ) : (
        <>
          <div className="page-stat-row">
            <div className="page-stat">
              <span className="page-stat-label">Active Solvers</span>
              <span className="page-stat-value">{solvers.filter((s) => s.active).length}</span>
            </div>
            <div className="page-stat">
              <span className="page-stat-label">Total Fills</span>
              <span className="page-stat-value">{solvers.reduce((s, v) => s + v.total_fills, 0).toLocaleString()}</span>
            </div>
            <div className="page-stat">
              <span className="page-stat-label">Avg Fill Rate</span>
              <span className="page-stat-value">
                {(solvers.reduce((s, v) => s + v.fill_rate, 0) / (solvers.length || 1) * 100).toFixed(1)}%
              </span>
            </div>
          </div>

          <div className="page-table-wrap">
            <table className="page-table">
              <thead>
                <tr>
                  <th>Rank</th>
                  <th>Solver</th>
                  <th>Score</th>
                  <th>Fill Rate</th>
                  <th>Avg Improvement</th>
                  <th>Total Fills</th>
                  <th>Status</th>
                </tr>
              </thead>
              <tbody>
                {solvers
                  .sort((a, b) => b.score - a.score)
                  .map((s, i) => (
                    <tr key={s.id}>
                      <td>#{i + 1}</td>
                      <td>
                        <div style={{ fontWeight: 600 }}>{s.name}</div>
                        <div style={{ fontSize: "0.75rem", opacity: 0.5 }}>
                          {s.address.slice(0, 8)}...{s.address.slice(-4)}
                        </div>
                      </td>
                      <td style={{ color: "var(--accent)", fontWeight: 600 }}>{s.score.toFixed(1)}</td>
                      <td>{(s.fill_rate * 100).toFixed(1)}%</td>
                      <td style={{ color: s.avg_improvement > 0 ? "var(--green, #06d6a0)" : "var(--text-dim)" }}>
                        {s.avg_improvement > 0 ? "+" : ""}{(s.avg_improvement * 100).toFixed(2)}%
                      </td>
                      <td>{s.total_fills.toLocaleString()}</td>
                      <td>
                        <span className={`page-status page-status--${s.active ? "active" : "inactive"}`}>
                          {s.active ? "Active" : "Inactive"}
                        </span>
                      </td>
                    </tr>
                  ))}
              </tbody>
            </table>
          </div>

          <div style={{ marginTop: 20, padding: 14, background: "rgba(124,92,252,0.05)", borderRadius: 10, fontSize: "0.82rem", color: "var(--text-dim)" }}>
            Solvers stake 100,000 $ARI to participate. They compete in Dutch auctions to fill intents,
            scored on price improvement, gas efficiency, fill rate, and reliability.
          </div>
        </>
      )}
    </div>
  );
}
