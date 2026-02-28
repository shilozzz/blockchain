🏦 MultiSignature Wallet

📌 Overview

A secure and configurable MultiSignature wallet smart contract built in Solidity.  
The contract requires multiple owners to approve transactions before execution and includes additional security protections against forced ETH attacks and reentrancy.

---

🚀 Features

- Supports **N number of owners**
- Owners can be added after deployment
- Configurable confirmation threshold (can be updated post-deployment)
- Submit, approve, revoke transactions
- Prevents double execution
- Reentrancy-safe execution logic
- Event logging for all major actions
- Sync function to handle forced ETH (selfdestruct attack)

---

🔐 Security Mechanisms

✅ Double Execution Protection
Ensures transactions cannot be executed more than once.
✅ Reentrancy Protection
Execution logic structured to prevent reentrancy vulnerabilities.
✅ Forced ETH Handling (Selfdestruct Attack Protection)
Includes a `syncUntrackedETH()` function to reconcile contract balance in case ETH is forcefully sent via `selfdestruct`.
This protects internal accounting integrity.

---

🛠 Built With

- Solidity ^0.8.x
- Remix IDE
- Ethereum Sepolia Testnet

---

🌐 Deployment

Test deployed on:
- Sepolia Testnet
- Remix VM

---

📂 Contract Architecture

- Owner Management
- Transaction Struct
- Confirmation Mapping
- Execution Logic
- Forced ETH Sync Logic
- Event Emission System

---

📈 Future Improvements

- ERC20 token support
- Frontend integration (Ethers.js)
- Hardhat migration
- Unit testing suite
