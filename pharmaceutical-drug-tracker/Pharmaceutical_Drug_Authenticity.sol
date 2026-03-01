// SPDX-License-Identifier: GPL-3.0
pragma solidity >=0.8.2 <0.9.0;

contract Pharmaceutical_Drug_Authenticity {

    //  ROLE CONSTANTS 
    // Unique role identifiers derived via keccak256 for gas-efficient RBAC checks
    bytes32 public constant MANUFACTURER_ROLE = keccak256("MANUFACTURER_ROLE");
    bytes32 public constant DISTRIBUTOR_ROLE  = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant PHARMACY_ROLE     = keccak256("PHARMACY_ROLE");

    // ENUMS & STRUCTS 
    // Role options for registerHandler — ABI enforces valid values, casing is impossible to get wrong
    enum HandlerRole { Distributor, Pharmacy }

    enum Status {
        Manufactured,
        InTransit,
        AtDistributor,
        AtPharmacy,
        Dispensed,
        Recalled,
        Expired
    }

    struct DrugBatch {
        uint256 batchId;
        string  drugName;
        address manufacturer;
        uint256 manufactureDate;
        uint256 expiryDate;
        address currentHolder;
        Status  status;
        bool    locked;
        bool    exists;    // existence flag to distinguish batch 0 from uninitialised storage
    }

    struct TransferLog {
        address from;
        address to;
        uint256 timestamp;
        string  location;
    }

    // STATE VARIABLES
    address public admin;
    // Counter starts at 1 so batch ID 0 is never a valid batch
    uint256 public nextBatchId = 1;
    mapping(address => mapping(bytes32 => bool)) private roles;
    // Private batch storage; accessed only through view functions
    mapping(uint256 => DrugBatch)     private batches;
    mapping(uint256 => TransferLog[]) private transferHistory;

    //  EVENTS
    event ManufacturerRegistered(address indexed manufacturer);
    event HandlerRegistered(address indexed handler, string role);
    event BatchRegistered(uint256 indexed batchId, address indexed manufacturer, string drugName, uint256 expiryDate);
    event BatchTransferred(uint256 indexed batchId, address indexed from, address indexed to, string location);
    event BatchDispensed(uint256 indexed batchId, address indexed pharmacy, uint256 timestamp);
    event BatchRecalled(uint256 indexed batchId, address indexed manufacturer, string reason);
    event BatchExpired(uint256 indexed batchId, uint256 checkedAt);

    // MODIFIERS 
    // Restricts function access to the single deployer/admin address
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier onlyRole(bytes32 role) {
        require(roles[msg.sender][role], "Unauthorized role");
        _;
    }

    // Ensures only the address currently holding the batch can act on it
    modifier onlyCurrentHolder(uint256 batchId) {
        require(batches[batchId].currentHolder == msg.sender, "Not current holder");
        _;
    }

    // Prevents any action on a batch that has been permanently finalised
    modifier notLocked(uint256 batchId) {
        require(!batches[batchId].locked, "Batch is locked");
        _;
    }

    // Guards against operations on non-existent batch IDs
    modifier batchExists(uint256 batchId) {
        require(batches[batchId].exists, "Batch does not exist");
        _;
    }

    // CONSTRUCTOR
    // Records the deployer as admin; no roles are self-assigned so admin stays neutral
    constructor() {
        admin = msg.sender;
    }

    //  ADMIN FUNCTIONS 
    // Grants MANUFACTURER_ROLE; reverts if address already holds this role to prevent silent overwrites
    function registerManufacturer(address mfr) external onlyAdmin {
        require(mfr != address(0), "Invalid address");
        require(!roles[mfr][MANUFACTURER_ROLE], "Already a manufacturer");
        roles[mfr][MANUFACTURER_ROLE] = true;
        emit ManufacturerRegistered(mfr);
    }

    // Grants DISTRIBUTOR_ROLE or PHARMACY_ROLE via enum; invalid values revert automatically at ABI level
    function registerHandler(address handler, HandlerRole role) external onlyAdmin {
        require(handler != address(0), "Invalid address");

        if (role == HandlerRole.Distributor) {
            // Prevent silent role overwrite for distributors
            require(!roles[handler][DISTRIBUTOR_ROLE], "Already a distributor");
            roles[handler][DISTRIBUTOR_ROLE] = true;
            emit HandlerRegistered(handler, "Distributor");
        } else {
            // Prevent silent role overwrite for pharmacies
            require(!roles[handler][PHARMACY_ROLE], "Already a pharmacy");
            roles[handler][PHARMACY_ROLE] = true;
            emit HandlerRegistered(handler, "Pharmacy");
        }
    }

    // Public getter so off-chain tools can query whether an address holds a given role
    function hasRole(address account, bytes32 role) external view returns (bool) {
        return roles[account][role];
    }

    // MANUFACTURER FUNCTIONS
    function registerBatch(string calldata drugName, uint256 expiryDate)
        external
        onlyRole(MANUFACTURER_ROLE)
    {
        require(expiryDate > block.timestamp, "Expiry must be in the future");

        uint256 batchId = nextBatchId++;

        batches[batchId] = DrugBatch({
            batchId:         batchId,
            drugName:        drugName,
            manufacturer:    msg.sender,
            manufactureDate: block.timestamp,
            expiryDate:      expiryDate,
            currentHolder:   msg.sender,
            status:          Status.Manufactured,
            locked:          false,
            exists:          true
        });

        emit BatchRegistered(batchId, msg.sender, drugName, expiryDate);
    }

    // TRANSFER FUNCTION
    // Moves custody to a distributor or pharmacy; only the current holder may call this
    function transferBatch(uint256 batchId, address to, string calldata location)
        external
        batchExists(batchId)
        onlyCurrentHolder(batchId)
        notLocked(batchId)
    {
        // Only manufacturer or distributor may initiate a transfer
        require(
            roles[msg.sender][MANUFACTURER_ROLE] || roles[msg.sender][DISTRIBUTOR_ROLE],
            "Sender not authorised to transfer"
        );
        require(
            roles[to][DISTRIBUTOR_ROLE] || roles[to][PHARMACY_ROLE],
            "Recipient not authorised"
        );

        DrugBatch storage batch = batches[batchId];
        address previousHolder  = batch.currentHolder;

        batch.currentHolder = to;
        batch.status = roles[to][DISTRIBUTOR_ROLE] ? Status.AtDistributor : Status.AtPharmacy;

        transferHistory[batchId].push(TransferLog({
            from:      previousHolder,
            to:        to,
            timestamp: block.timestamp,
            location:  location
        }));

        emit BatchTransferred(batchId, previousHolder, to, location);
    }

    // DISPENSE FUNCTION
    // Finalises a batch as dispensed; only the pharmacy currently holding it may call this
    function dispenseBatch(uint256 batchId)
        external
        batchExists(batchId)
        onlyCurrentHolder(batchId)
        onlyRole(PHARMACY_ROLE)
        notLocked(batchId)
    {
        DrugBatch storage batch = batches[batchId];

        // Batch must have reached pharmacy status before it can be dispensed
        require(batch.status == Status.AtPharmacy, "Batch not at pharmacy");

        batch.status = Status.Dispensed;
        batch.locked = true;

        emit BatchDispensed(batchId, msg.sender, block.timestamp);
    }

    // RECALL FUNCTION 
    // Allows the original manufacturer of a batch to issue a recall at any unlocked stage
    function recallBatch(uint256 batchId, string calldata reason)
        external
        batchExists(batchId)
        onlyRole(MANUFACTURER_ROLE)
        notLocked(batchId)
    {
        DrugBatch storage batch = batches[batchId];

        // Only the manufacturer who registered this specific batch may recall it
        require(msg.sender == batch.manufacturer, "Not the original manufacturer");

        batch.status = Status.Recalled;
        batch.locked = true;

        emit BatchRecalled(batchId, msg.sender, reason);
    }

    // EXPIRY CHECK 
    // Mutates batch state to Expired and locks it, preventing any further actions
    function checkExpiry(uint256 batchId) external batchExists(batchId) {
        DrugBatch storage batch = batches[batchId];

        require(block.timestamp > batch.expiryDate, "Batch has not expired yet");
        // Only mark expired if not already in a terminal state
        require(
            batch.status != Status.Recalled  &&
            batch.status != Status.Dispensed &&
            batch.status != Status.Expired,
            "Batch already in terminal state"
        );

        batch.status = Status.Expired;
        batch.locked = true;

        emit BatchExpired(batchId, block.timestamp);
    }

    // VIEW FUNCTIONS 
    // Returns the full batch struct; reverts cleanly for non-existent IDs
    function getBatch(uint256 batchId)
        external
        view
        batchExists(batchId)
        returns (DrugBatch memory)
    {
        return batches[batchId];
    }

    // Returns the complete ordered chain-of-custody log for a given batch
    function getTransferHistory(uint256 batchId)
        external
        view
        batchExists(batchId)
        returns (TransferLog[] memory)
    {
        return transferHistory[batchId];
    }
}