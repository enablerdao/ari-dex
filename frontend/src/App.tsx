import { useState, useEffect } from "react";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import { mainnet, arbitrum, base } from "wagmi/chains";
import { Header } from "./components/Header";
import { SwapPanel } from "./components/SwapPanel";
import { PoolsPage } from "./components/PoolsPage";
import { PortfolioPage } from "./components/PortfolioPage";
import { SolversPage } from "./components/SolversPage";

const queryClient = new QueryClient();

const wagmiConfig = createConfig({
  chains: [mainnet, arbitrum, base],
  transports: {
    [mainnet.id]: http(),
    [arbitrum.id]: http(),
    [base.id]: http(),
  },
});

type Page = "swap" | "pools" | "portfolio" | "solvers";

function useHashRoute(): [Page, (p: Page) => void] {
  const [page, setPage] = useState<Page>(() => {
    const hash = window.location.hash.replace("#", "");
    if (["pools", "portfolio", "solvers"].includes(hash)) return hash as Page;
    return "swap";
  });

  useEffect(() => {
    const handler = () => {
      const hash = window.location.hash.replace("#", "");
      if (["pools", "portfolio", "solvers"].includes(hash)) setPage(hash as Page);
      else setPage("swap");
    };
    window.addEventListener("hashchange", handler);
    return () => window.removeEventListener("hashchange", handler);
  }, []);

  const navigate = (p: Page) => {
    window.location.hash = p === "swap" ? "" : p;
    setPage(p);
  };

  return [page, navigate];
}

function Stats() {
  return (
    <div className="stats">
      <div className="stats-item">
        <span className="stats-label">Contracts</span>
        <span className="stats-value">13</span>
      </div>
      <div className="stats-item">
        <span className="stats-label">Tests</span>
        <span className="stats-value">188</span>
      </div>
      <div className="stats-item">
        <span className="stats-label">Solvers</span>
        <span className="stats-value">5</span>
      </div>
      <div className="stats-item">
        <span className="stats-label">Chains</span>
        <span className="stats-value">3</span>
      </div>
    </div>
  );
}

function Powered() {
  return (
    <div className="powered">
      Powered by intent-based settlement on{" "}
      <a href="https://etherscan.io/address/0x536EeDA7d07cF7Af171fBeD8FAe7987a5c63B822" target="_blank" rel="noopener noreferrer">
        Ethereum
      </a>
    </div>
  );
}

export function App() {
  const [page, navigate] = useHashRoute();

  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <div className="app">
          <Header currentPage={page} onNavigate={navigate} />
          <main className="main">
            {page === "swap" && (
              <>
                <SwapPanel />
                <Stats />
              </>
            )}
            {page === "pools" && <PoolsPage />}
            {page === "portfolio" && <PortfolioPage />}
            {page === "solvers" && <SolversPage />}
            <Powered />
          </main>
        </div>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
