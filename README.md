## Bloom Finance - Solidity Contracts v0.0.1

[![built-with openzeppelin](https://img.shields.io/badge/built%20with-OpenZeppelin-3677FF)](https://docs.openzeppelin.com/)

![GitHub last commit](https://img.shields.io/github/last-commit/robsecord/BloomEth)
![GitHub package.json version](https://img.shields.io/github/package-json/v/robsecord/BloomEth)
![GitHub code size in bytes](https://img.shields.io/github/languages/code-size/robsecord/BloomEth)
![GitHub repo size](https://img.shields.io/github/repo-size/robsecord/BloomEth)

---

**Coupons that Grow in Value!**

---

#### Production Site (Beta, Ropsten Only)
https://bloom-finance.eth.link/

---

#### Value Appreciation
Your Coupon is always earning Interest on the amount deposited, for as long as you hold the coupon!

#### Ownership
Bloom Coupons are non-custodial NFTs that are yours trade, transfer & sell!  They can even be "discarded" in order to reclaim the underlying value of the Coupon!

---

### Frameworks/Software used:
 - Main Repo:
    - OpenZeppelin CLI **v2.8.2**
    - OpenZeppelin Ethereum Contracts **v2.5.0**
    - OpenZeppelin Upgrades **v2.6.0**
    - Solidity  **v0.5.16**
    - NodeJS **v12.16.3**
    - Web3.js **v1.2.7**

### Prepare environment:
    
 Create a local .env file with the following (replace ... with your keys):
 
```bash
    INFURA_API_KEY="__api_key_only_no_url__"
    
    ROPSTEN_PROXY_ADDRESS="__public_address__"
    ROPSTEN_PROXY_MNEMONIC="__12-word_mnemonic__"
    
    ROPSTEN_OWNER_ADDRESS="__public_address__"
    ROPSTEN_OWNER_MNEMONIC="__12-word_mnemonic__"
    
    MAINNET_PROXY_ADDRESS="__public_address__"
    MAINNET_PROXY_MNEMONIC="__12-word_mnemonic__"
    
    MAINNET_OWNER_ADDRESS="__public_address__"
    MAINNET_OWNER_MNEMONIC="__12-word_mnemonic__"
```

### To run the Main Repo (Testnet or Mainnet only):
    
 1. yarn
 2. yarn deploy-ropsten

See package.json for more scripts

---

_MIT License_

Copyright (c) 2020 Rob Secord <robsecord.eth>

