🏦 ETH Lending Pool (Mini DeFi Protocol)

📌 Overview

A simplified decentralized lending protocol built in Solidity that allows users to deposit ETH into a liquidity pool and borrow against it.

This project models the core mechanics of DeFi lending platforms such as Aave and Compound in a simplified architecture.

---

🚀 Features

- Deposit ETH into pool
- Borrow from available liquidity
- Repay borrowed amount
- Track user balances
- Track outstanding debt
- Maintain pool liquidity accounting
- Interest calculation mechanism

---

🏗 Architecture

The contract maintains:

- Liquidity pool balance
- User deposit balances
- User borrow balances
- Total liquidity tracking
- Collateral requirement logic

---

🔐 Security Considerations

- Solidity ^0.8.x (overflow protected)
- Checks-Effects-Interactions pattern
- State updates before transfers
- Liquidity validation before borrowing
- No external token dependency (ETH only)

---

⚠️ Limitations

- ETH-only support
- No liquidation mechanism
- No dynamic interest rate model
- No oracle price feeds

---

🛠 Built With

- Solidity ^0.8.x
- Remix IDE (VM Testing)

---

📈 Future Improvements

- ERC20 token support
- Liquidation logic
- Dynamic interest rate model
- Oracle price integration
- Frontend dashboard
- Sepolia deployment
