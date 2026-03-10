# ARI DEX Contracts — Makefile
# Usage: make test | make deploy-sepolia | make deploy-base-sepolia

-include .env

.PHONY: test deploy-sepolia deploy-base-sepolia

test:
	forge test -v

deploy-sepolia:
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url https://eth-sepolia.g.alchemy.com/v2/$(ALCHEMY_KEY) \
		--broadcast --verify -vvvv

deploy-base-sepolia:
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url https://sepolia.base.org \
		--broadcast --verify -vvvv
