
💊 Pharmaceutical Drug Authenticity Tracker

📌 Overview

A blockchain-based pharmaceutical supply chain tracking system built in Solidity.

This smart contract enables secure tracking of drug batches from manufacturer → distributor → pharmacy, ensuring authenticity and preventing counterfeit medicines from entering the supply chain.

According to the WHO, approximately 10% of medicines in low-income countries are counterfeit. This system enables transparent, tamper-proof verification of drug journey history.

---

🎯 Problem Statement

Counterfeit medicines pose serious global health risks. Traditional supply chain systems rely on centralized databases that can be altered or compromised.

This smart contract ensures:
- Immutable tracking
- Transparent verification
- Role-based controlled updates
- Public auditability

---

🏗 System Architecture

Roles:
- Manufacturer
- Distributor
- Pharmacy
- Regulator (Admin)

Each drug batch:
- Is registered by manufacturer
- Updated during transfer stages
- Verified before dispensing
- Can be publicly validated

---

🔐 Security Features

✅ Role-Based Access Control (RBAC)
Only authorized stakeholders can perform specific actions.

✅ Immutable Audit Trail
Each update to a drug batch is permanently stored on-chain.

✅ No Financial Logic
Pure data integrity contract — no ETH handling.

✅ Access-Restricted State Transitions
Prevents unauthorized supply chain updates.

---

📦 Features

- Register drug batch
- Transfer between supply chain actors
- Track batch history
- Verify authenticity
- Prevent unauthorized modifications

---

🛠 Built With

- Solidity ^0.8.x
- Remix IDE (VM testing)

---

🚀 Future Improvements

- QR code integration for batch scanning
- IPFS metadata storage for detailed documents
- Frontend dashboard for regulators
- Sepolia deployment
- Event indexing for analytics
- Integration with IoT temperature sensors
