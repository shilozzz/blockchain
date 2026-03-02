// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

//OpenZeppelin ReentrancyGuard (inline, no import needed for deployment)
abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED     = 2;
    uint256 private _status;

    constructor() { _status = _NOT_ENTERED; }

    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }
}

/**
 * LendingPool
 * Integer overflow/underflow already safe under Solidity ^0.8.30.
 *
*/
contract Lending_Pool is ReentrancyGuard {

    //Structures
    struct Loan {
        address borrower;
        uint256 principal;
        uint256 interestRate;  // Annual rate in basis-points (1 000 = 10%)
        uint256 borrowedAt;
        uint256 dueAt;
        bool    repaid;
    }

    //  State Variables
    uint256 public constant ANNUAL_RATE_BPS = 1_000; // 10% per annum

    mapping(address => uint256) public lenderDeposits;
    mapping(address => Loan)    public activeLoans;
    mapping(address => bool)    public hasActiveLoan;

    uint256 public totalInterestCollected;
    uint256 public totalDeposited;

    /**
     * FIX (Forced ETH / selfdestruct):
     * poolLiquidity is the ONLY source of truth for available ETH.
     * It is incremented only in deposit() and repay(), and decremented
     * only in withdraw() and borrow(). Because selfdestruct/coinbase
     * can inflate address(this).balance without calling any function,
     * we intentionally IGNORE address(this).balance in all logic.
     */
    uint256 public poolLiquidity;

    //  Events
    event Deposited(address indexed lender,   uint256 amount, uint256 newPoolTotal);
    event Withdrawn(address indexed lender,   uint256 amount);
    event Borrowed( address indexed borrower, uint256 principal, uint256 interestDue, uint256 dueTimestamp);
    event Repaid(   address indexed borrower, uint256 totalRepaid, uint256 interestPaid);
    event DefaultDetected(address indexed borrower, uint256 amountOwed, uint256 overdueBy);

    //  Lender Functions
    /**
     * Deposit ETH into the pool.
     * poolLiquidity is incremented here — this is the ONLY way legitimate ETH enters the spendable accounting.
     */
    function deposit() external payable {
        require(msg.value > 0, "LendingPool: deposit must be > 0");

        // Effects
        lenderDeposits[msg.sender] += msg.value;
        totalDeposited             += msg.value;
        poolLiquidity              += msg.value; // FIX: track internally

        emit Deposited(msg.sender, msg.value, poolLiquidity);
    }

    /**
     * Withdraw ETH plus proportional interest share.
     * FIX (Reentrancy): nonReentrant modifier + CEI pattern.
     * FIX (Forced ETH): uses poolLiquidity, not address(this).balance.
     */
    function withdraw(uint256 amount) external nonReentrant {
        require(amount > 0,                     "LendingPool: amount must be > 0");
        require(lenderDeposits[msg.sender] > 0, "LendingPool: no deposit found");

        //Compute entitlement
        uint256 interestShare = 0;
        if (totalDeposited > 0 && totalInterestCollected > 0) {
            interestShare =
                (totalInterestCollected * lenderDeposits[msg.sender]) /
                totalDeposited;
        }
        uint256 maxWithdrawable = lenderDeposits[msg.sender] + interestShare;

        require(amount <= maxWithdrawable,   "LendingPool: amount exceeds entitlement");
        require(amount <= poolLiquidity,     "LendingPool: insufficient pool liquidity"); // FIX

        //Effects (ALL state writes before any transfer)
        if (amount >= maxWithdrawable) {
            totalDeposited             -= lenderDeposits[msg.sender];
            lenderDeposits[msg.sender]  = 0;
        } else {
            uint256 principalPortion = amount <= lenderDeposits[msg.sender]
                ? amount
                : lenderDeposits[msg.sender];
            lenderDeposits[msg.sender] -= principalPortion;
            totalDeposited             -= principalPortion;
        }
        poolLiquidity -= amount; // FIX: decrement internal tracker

        //Interaction (transfer last — CEI)
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "LendingPool: ETH transfer failed");

        emit Withdrawn(msg.sender, amount);
    }

    //  Borrower Functions
    /**
     * Borrow ETH from the pool.
     * FIX (Reentrancy): nonReentrant modifier.
     * FIX (Forced ETH): liquidity check against poolLiquidity.
     * CEI: all state written before .call transfer.
     */
    function borrow(uint256 amount, uint256 durationDays) external nonReentrant {
        require(amount > 0,                      "LendingPool: borrow amount must be > 0");
        require(durationDays > 0,                "LendingPool: duration must be > 0");
        require(!hasActiveLoan[msg.sender],      "LendingPool: existing active loan");
        require(amount <= poolLiquidity,         "LendingPool: insufficient pool liquidity"); // FIX

        uint256 dueAt       = block.timestamp + (durationDays * 1 days);
        uint256 interestDue = _computeInterest(amount, ANNUAL_RATE_BPS, durationDays * 1 days);

        //Effects
        activeLoans[msg.sender] = Loan({
            borrower:     msg.sender,
            principal:    amount,
            interestRate: ANNUAL_RATE_BPS,
            borrowedAt:   block.timestamp,
            dueAt:        dueAt,
            repaid:       false
        });
        hasActiveLoan[msg.sender]  = true;
        poolLiquidity             -= amount; // FIX: decrement before transfer

        // Interaction
        (bool ok, ) = payable(msg.sender).call{value: amount}("");
        require(ok, "LendingPool: ETH transfer failed");

        emit Borrowed(msg.sender, amount, interestDue, dueAt);
    }

    /**
     * Repay principal + accrued interest.
     * FIX (Reentrancy): nonReentrant modifier.
     * FIX (Forced ETH): poolLiquidity incremented on repay so
     * repaid funds re-enter the legitimate accounting.
     * CEI: state written before emit (no external call here).
     */
    function repay() external payable nonReentrant {
        require(hasActiveLoan[msg.sender], "LendingPool: no active loan");

        Loan storage loan = activeLoans[msg.sender];
        require(!loan.repaid, "LendingPool: loan already repaid");

        uint256 secondsElapsed = block.timestamp - loan.borrowedAt;
        uint256 interest       = _computeInterest(loan.principal, loan.interestRate, secondsElapsed);
        uint256 totalOwed      = loan.principal + interest;

        require(msg.value == totalOwed, "LendingPool: incorrect repayment amount");

    // Effects
        loan.repaid                = true;
        hasActiveLoan[msg.sender]  = false;
        totalInterestCollected    += interest;
        poolLiquidity             += msg.value; // FIX: repayment re-enters accounting

        emit Repaid(msg.sender, msg.value, interest);
    }

    //  Public / View Functions
    /**
     * Flag an overdue loan. Callable by anyone.
     */
    function checkDefault(address borrower) external {
        require(hasActiveLoan[borrower], "LendingPool: no active loan for address");

        Loan storage loan = activeLoans[borrower];
        require(!loan.repaid, "LendingPool: loan already repaid");

        if (block.timestamp > loan.dueAt) {
            uint256 secondsElapsed = block.timestamp - loan.borrowedAt;
            uint256 interest       = _computeInterest(loan.principal, loan.interestRate, secondsElapsed);
            uint256 amountOwed     = loan.principal + interest;
            uint256 overdueBy      = block.timestamp - loan.dueAt;

            emit DefaultDetected(borrower, amountOwed, overdueBy);
        }
    }

    /**
     * Returns the tracked pool liquidity (immune to forced ETH).
     * address(this).balance is intentionally NOT used here for logic.
     * It is shown alongside only for informational transparency so
     * anyone can observe if forced ETH has been injected.
     */
    function getPoolBalance() external view returns (
        uint256 trackedLiquidity,
        uint256 rawContractBalance
    ) {
        trackedLiquidity   = poolLiquidity;          // FIX: use internal tracker
        rawContractBalance = address(this).balance;  // informational only
    }

    /**
     * Returns the full Loan struct for a given borrower.
     */
    function getLoan(address borrower) external view returns (Loan memory) {
        return activeLoans[borrower];
    }

    /**
     * Returns the exact amount owed by a borrower right now.
     */
    function getCurrentOwed(address borrower) external view returns (uint256 totalOwed) {
        require(hasActiveLoan[borrower], "LendingPool: no active loan for address");
        Loan storage loan  = activeLoans[borrower];
        uint256 elapsed    = block.timestamp - loan.borrowedAt;
        uint256 interest   = _computeInterest(loan.principal, loan.interestRate, elapsed);
        totalOwed          = loan.principal + interest;
    }

    //  Internal Helpers
    /**
     *interest = (principal × rateBps × secondsElapsed) / (365 days × 10_000)
     * Pure integer arithmetic. Safe under Solidity ^0.8.20 checked math.
     */
    function _computeInterest(
        uint256 principal,
        uint256 rateBps,
        uint256 secondsElapsed
    ) internal pure returns (uint256) {
        return (principal * rateBps * secondsElapsed) / (365 days * 10_000);
    }

    //  Fallback — reject plain ETH sends to prevent accounting desync
    /**
     * FIX (Forced ETH): Rejecting receive() means accidental direct sends
     * revert cleanly. Note: selfdestruct bypass CANNOT be blocked at the
     * EVM level — which is exactly why poolLiquidity exists as the
     * internal tracker. rawContractBalance in getPoolBalance() lets
     * anyone verify if a desync has occurred.
     */
    receive() external payable {
        revert("LendingPool: use deposit()");
    }

    fallback() external payable {
        revert("LendingPool: use deposit()");
    }
}