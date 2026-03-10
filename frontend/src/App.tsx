import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { WagmiProvider, createConfig, http } from "wagmi";
import { mainnet, arbitrum, base } from "wagmi/chains";
import { Header } from "./components/Header";
import { SwapPanel } from "./components/SwapPanel";

const queryClient = new QueryClient();

const wagmiConfig = createConfig({
  chains: [mainnet, arbitrum, base],
  transports: {
    [mainnet.id]: http(),
    [arbitrum.id]: http(),
    [base.id]: http(),
  },
});

export function App() {
  return (
    <WagmiProvider config={wagmiConfig}>
      <QueryClientProvider client={queryClient}>
        <div className="app">
          <Header />
          <main className="main">
            <SwapPanel />
          </main>
        </div>
      </QueryClientProvider>
    </WagmiProvider>
  );
}
