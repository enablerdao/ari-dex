import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi/connectors";

type Page = "swap" | "pools" | "portfolio" | "solvers";

interface HeaderProps {
  currentPage: Page;
  onNavigate: (page: Page) => void;
}

export function Header({ currentPage, onNavigate }: HeaderProps) {
  const { address, isConnected, chain } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();

  const formatAddress = (addr: string) =>
    `${addr.slice(0, 6)}...${addr.slice(-4)}`;

  const navItems: { page: Page; label: string }[] = [
    { page: "swap", label: "Swap" },
    { page: "pools", label: "Pools" },
    { page: "portfolio", label: "Portfolio" },
    { page: "solvers", label: "Solvers" },
  ];

  return (
    <header className="header">
      <div className="header-logo">
        <span className="header-logo-text" onClick={() => onNavigate("swap")} style={{ cursor: "pointer" }}>ARI</span>
        <span className="header-logo-badge">Mainnet</span>
      </div>

      <nav className="header-nav">
        {navItems.map((item) => (
          <a
            key={item.page}
            className={`header-nav-link ${currentPage === item.page ? "header-nav-link--active" : ""}`}
            href={`#${item.page === "swap" ? "" : item.page}`}
            onClick={(e) => {
              e.preventDefault();
              onNavigate(item.page);
            }}
          >
            {item.label}
          </a>
        ))}
      </nav>

      <div className="header-right">
        {isConnected && chain && (
          <div className="header-chain">
            <span className="header-chain-dot" />
            {chain.name}
          </div>
        )}
        {isConnected && address ? (
          <button
            className="header-wallet-btn header-wallet-btn--connected"
            onClick={() => disconnect()}
          >
            {formatAddress(address)}
          </button>
        ) : (
          <button
            className="header-wallet-btn"
            onClick={() => connect({ connector: injected() })}
          >
            Connect Wallet
          </button>
        )}
      </div>
    </header>
  );
}
