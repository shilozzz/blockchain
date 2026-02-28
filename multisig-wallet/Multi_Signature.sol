// SPDX-License-Identifier: MIT
pragma solidity ^0.8.31;

/**
 * MultiSignature Wallet - A multi-signature wallet requiring M-of-N owner approvals before executing transactions.
 * addOwner and removeOwner can be called directly by any existing owner.
 */
contract Multi_Signature {

    
    //Structure
    struct Transaction {
        uint256 txId;
        address to;
        uint256 value;
        bytes data;
        bool executed;
        uint256 approvalCount;
    }

    // State Variables
    address[] private owners;//array of owners
    uint256 public requiredApprovals;//no.of required approvals
    mapping(address => bool) public isOwner;// Maps each address to a boolean indicating whether they are an approved owner of this wallet

    // Maps each transaction ID to a nested mapping that tracks which owners have approved that transaction
    // hasApproved[txId][ownerAddress] => true if that owner has approved that transaction
    mapping(uint256 => mapping(address => bool)) public hasApproved;

    // Maps each transaction ID to its full Transaction struct containing all details of that transaction
    // Private — external users must call getTransaction() to read transaction data
    mapping(uint256 => Transaction) private transactions;

    // Counter that auto-increments with each new transaction submission
    // Used as the unique ID for each transaction — starts at 0 and never resets
    uint256 private nextTxId;

    // Running total of all ETH deposited through the deposit() function in wei
    // Used to detect forced ETH that bypassed deposit() via selfdestruct or coinbase
    uint256 public trackedDeposits;


    uint256 public forcedDepositCount;// Counts how many times forced ETH has been detected and synced via syncForcedDeposits()


    
    // Events
    
    event FundsDeposited(address indexed sender, uint256 amount);
    event ForcedDepositDetected(uint256 indexed count, uint256 amount);
    event TransactionSubmitted(
        uint256 indexed txId,
        address indexed submitter,
        address indexed to,
        uint256 value
    );
    event TransactionApproved(uint256 indexed txId, address indexed approver);
    event ApprovalRevoked(uint256 indexed txId, address indexed owner);
    event TransactionExecuted(uint256 indexed txId, address indexed executor);
    event TransactionFailed(uint256 indexed txId);
    event OwnerAdded(address indexed newOwner, address indexed addedBy);
    event OwnerRemoved(address indexed removedOwner, address indexed removedBy);

    
    // Modifiers
    
    modifier onlyOwner() {
        require(isOwner[msg.sender], "MultiSigWallet: caller is not an owner");
        _;
    }

    modifier txExists(uint256 txId) {
        require(txId < nextTxId, "MultiSigWallet: transaction does not exist");
        _;
    }

    modifier notExecuted(uint256 txId) {
        require(!transactions[txId].executed, "MultiSigWallet: transaction already executed");
        _;
    }

    
    // Constructor

    constructor(address[] memory _owners, uint256 _requiredApprovals) {
        require(_owners.length > 0, "MultiSigWallet: at least one owner required");
        require(
            _requiredApprovals >= 1 && _requiredApprovals <= _owners.length,
            "MultiSigWallet: invalid required approvals"
        );

        for (uint256 i = 0; i < _owners.length; i++) {
            address owner = _owners[i];
            require(owner != address(0), "MultiSigWallet: zero address owner");
            require(!isOwner[owner], "MultiSigWallet: duplicate owner");
            isOwner[owner] = true;
            owners.push(owner);
        }

        requiredApprovals = _requiredApprovals;
    }

    
    // Receive ETH

    receive() external payable {
    }
    function deposit() external payable {
    require(msg.value > 0, "MultiSigWallet: deposit amount must be greater than 0");
    trackedDeposits += msg.value;
    emit FundsDeposited(msg.sender, msg.value);
    }
    
    // Forced Deposit Detection(self destruct)
    
    function syncForcedDeposits() external {
        // Calculate the gap between what actually exists and what was tracked via deposit()
        uint256 untracked = address(this).balance - trackedDeposits;
        if (untracked > 0) {//if balance is greater than trackedDeposits then there is a forced deposit
            forcedDepositCount++;
            trackedDeposits += untracked;//untracked deposits are added to the tracked deposits to sync with the balance of the contract
            emit ForcedDepositDetected(forcedDepositCount, untracked);
        }
    }

    function getUntrackedBalance() external view returns (uint256) {
        return address(this).balance - trackedDeposits;
    }

    
    // Owner Management — callable directly by any existing owner
    /**
     *  Adds a new owner directly. Only existing owners can call this.
     *  newOwner Address to add as an owner.
     */
    function addOwner(address newOwner) external onlyOwner {
        require(newOwner != address(0), "MultiSigWallet: zero address");
        require(!isOwner[newOwner], "MultiSigWallet: already an owner");

        isOwner[newOwner] = true;
        owners.push(newOwner);

        emit OwnerAdded(newOwner, msg.sender);
    }

    /**
     *  Removes an existing owner directly. Only existing owners can call this.
     *  Cannot remove if it would drop the owner count below the required threshold.
     *  An owner cannot remove themselves if they are the last owner.
     *  ownerToRemove Address to remove from owners.
     */
    function removeOwner(address ownerToRemove) external onlyOwner {
        require(isOwner[ownerToRemove], "MultiSigWallet: not an owner");
        require(
            owners.length - 1 >= requiredApprovals,
            "MultiSigWallet: cannot go below required approvals threshold"
        );
        require(owners.length > 1, "MultiSigWallet: cannot remove the last owner");

        isOwner[ownerToRemove] = false;

        // Swap with last element and pop — avoids shifting the entire array
        for (uint256 i = 0; i < owners.length; i++) {
            if (owners[i] == ownerToRemove) {
                owners[i] = owners[owners.length - 1];
                owners.pop();
                break;
            }
        }

        emit OwnerRemoved(ownerToRemove, msg.sender);
    }

    event RequiredApprovalsChanged(uint256 oldRequired, uint256 newRequired, address changedBy);

    function changeRequiredApprovals(uint256 newRequired) external onlyOwner {
        //change the required approvals after deployment
    require(
        newRequired >= 1 && newRequired <= owners.length,
        "MultiSigWallet: invalid threshold"
    );
    require(
        newRequired != requiredApprovals,
        "MultiSigWallet: already set to this value"
    );

    uint256 oldRequired = requiredApprovals;
    requiredApprovals = newRequired;

    emit RequiredApprovalsChanged(oldRequired, newRequired, msg.sender);
}

    
    // Core Functions
    /**
     *  Proposes a new transaction. Any owner can submit.
     *  to    Destination address.
     *  value Amount of ETH in wei to send.
     *  data  Encoded calldata (use 0x for plain ETH transfers).
     */
    function submitTransaction(address to, uint256 value, bytes calldata data)
        external
        onlyOwner
        returns (uint256 txId)
    {
        require(to != address(0), "MultiSigWallet: invalid destination address");

        txId = nextTxId;
        nextTxId++;

        transactions[txId] = Transaction({
            txId: txId,
            to: to,
            value: value,
            data: data,
            executed: false,
            approvalCount: 0
        });

        emit TransactionSubmitted(txId, msg.sender, to, value);
    }

    /**
     *  Approves a pending transaction.
     *  txId ID of the transaction to approve.
     */
    function approveTransaction(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        require(!hasApproved[txId][msg.sender], "MultiSigWallet: already approved");

        hasApproved[txId][msg.sender] = true;
        transactions[txId].approvalCount++;

        emit TransactionApproved(txId, msg.sender);
    }

    /**
     *  Revokes a previously given approval.
     *  txId ID of the transaction to revoke approval from.
     */
    function revokeApproval(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        require(hasApproved[txId][msg.sender], "MultiSigWallet: not yet approved");

        hasApproved[txId][msg.sender] = false;
        transactions[txId].approvalCount--;

        emit ApprovalRevoked(txId, msg.sender);
    }

    /**
     *  Executes a transaction once approval threshold is met.
     *  The caller must be one of the approvers.
     *  txId ID of the transaction to execute.
     */
    function executeTransaction(uint256 txId)
        external
        onlyOwner
        txExists(txId)
        notExecuted(txId)
    {
        require(hasApproved[txId][msg.sender], "MultiSigWallet: executor must be an approver");

        Transaction storage txn = transactions[txId];

        require(
            txn.approvalCount >= requiredApprovals,
            "MultiSigWallet: insufficient approvals"
        );
        require(
            address(this).balance >= txn.value,
            "MultiSigWallet: insufficient contract balance"
        );

        // Set executed before external call to prevent reentrancy
        txn.executed = true;

        (bool success, ) = txn.to.call{value: txn.value}(txn.data);

        if (success) {
            if (trackedDeposits >= txn.value) {
                trackedDeposits -= txn.value;
            } else {
                trackedDeposits = 0;
            }
            emit TransactionExecuted(txId, msg.sender);
        } else {
            txn.executed = false;
            emit TransactionFailed(txId);
        }
    }

    
    // View Functions
   
     function getTransaction(uint256 txId)
        external
        view
        txExists(txId)
        returns (Transaction memory)
    {
        return transactions[txId];
    }

    function getOwners() external view returns (address[] memory) {
        return owners;
    }

    function getBalance() external view returns (uint256) {
        return address(this).balance;
    }

    function getTransactionCount() external view returns (uint256) {
        return nextTxId;
    }
}
