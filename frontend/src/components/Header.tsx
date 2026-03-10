import { useAccount, useConnect, useDisconnect } from "wagmi";
import { injected } from "wagmi/connectors";

export function Header() {
  const { address, isConnected, chain } = useAccount();
  const { connect } = useConnect();
  const { disconnect } = useDisconnect();

  const formatAddress = (addr: string) =>
    `${addr.slice(0, 6)}...${addr.slice(-4)}`;

  return (
    <header className="header">
      <div className="header-logo">
        <span className="header-logo-text">ARI</span>
        <span className="header-logo-badge">Mainnet</span>
      </div>

      <nav className="header-nav">
        <a className="header-nav-link header-nav-link--active" href="#">
          Swap
        </a>
        <a className="header-nav-link" href="#">
          Pools
        </a>
        <a className="header-nav-link" href="#">
          Portfolio
        </a>
        <a className="header-nav-link" href="#">
          Solvers
        </a>
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
