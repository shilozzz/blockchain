// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

///  PropertyRegistry
///  A government-grade on-chain land registry preventing fraud through
///  immutable ownership records and auditable transfer history.
contract Property_Registry {

    
    //  Structures

    struct Property {
        uint256 propertyId;
        address currentOwner;
        string  location;
        uint256 areaSqMeters;
        uint256 listPrice;
        bool    isForSale;
        uint256 registeredAt;
    }


    //  State Variables

    address public admin;
    uint256 private _nextPropertyId;   // auto-incrementing ID counter

    ///  propertyId → Property record
    mapping(uint256 => Property) public properties;

    ///  propertyId → ordered list of every address that has ever owned it
    mapping(uint256 => address[]) private ownershipHistory;

    ///  owner address → list of propertyIds currently owned
    mapping(address => uint256[]) private ownedProperties;


    //  Events

    event PropertyRegistered(
        uint256 indexed propertyId,
        address indexed initialOwner,
        string  location,
        uint256 area
    );

    event PropertyListedForSale(
        uint256 indexed propertyId,
        address indexed owner,
        uint256 price
    );

    event PropertyDelisted(
        uint256 indexed propertyId,
        address indexed owner
    );

    event PropertySold(
        uint256 indexed propertyId,
        address indexed previousOwner,
        address indexed newOwner,
        uint256 price
    );

    event PropertyTransferred(
        uint256 indexed propertyId,
        address indexed from,
        address indexed to
    );

    event AdminChanged(
        address indexed oldAdmin,
        address indexed newAdmin
    );


    //  Modifiers

    modifier onlyAdmin() {
        require(msg.sender == admin, "PropertyRegistry: caller is not admin");
        _;
    }

    modifier onlyCurrentOwner(uint256 propertyId) {
        require(
            properties[propertyId].currentOwner == msg.sender,
            "PropertyRegistry: caller is not the current owner"
        );
        _;
    }

    modifier propertyExists(uint256 propertyId) {
        require(
            properties[propertyId].registeredAt != 0,
            "PropertyRegistry: property does not exist"
        );
        _;
    }


    //  Constructor

    constructor() {
        admin = msg.sender;
        _nextPropertyId = 1;    // IDs start at 1 so that 0 is the "null" sentinel
    }

    //  Admin Functions

    ///  Register a new land parcel. Admin use only.
    ///  initialOwner - The government-verified first owner.
    ///  location -  Human-readable location string (e.g. cadastral reference).
    ///  areaSqMeters - Parcel size in square metres.
    ///  propertyId - The ID assigned to the new property.
    function registerProperty(
        address initialOwner,
        string calldata location,
        uint256 areaSqMeters
    ) external onlyAdmin returns (uint256 propertyId) {
        require(initialOwner != address(0), "PropertyRegistry: zero address owner");
        require(bytes(location).length > 0,  "PropertyRegistry: empty location");
        require(areaSqMeters > 0,            "PropertyRegistry: area must be > 0");

        propertyId = _nextPropertyId++;

        properties[propertyId] = Property({
            propertyId   : propertyId,
            currentOwner : initialOwner,
            location     : location,
            areaSqMeters : areaSqMeters,
            listPrice    : 0,
            isForSale    : false,
            registeredAt : block.timestamp
        });

        // Seed the ownership history with the first owner.
        ownershipHistory[propertyId].push(initialOwner);

        // Index by owner.
        ownedProperties[initialOwner].push(propertyId);

        emit PropertyRegistered(propertyId, initialOwner, location, areaSqMeters);
    }

    ///  Transfer the admin role to a new address.
    function changeAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), "PropertyRegistry: zero address");
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    //  Owner Functions

    ///  List a property for sale at the specified price.
    ///  price Asking price in wei (must be > 0).
    function listForSale(uint256 propertyId, uint256 price)
        external
        propertyExists(propertyId)
        onlyCurrentOwner(propertyId)
    {
        require(price > 0, "PropertyRegistry: price must be > 0");

        Property storage p = properties[propertyId];
        p.isForSale  = true;
        p.listPrice  = price;

        emit PropertyListedForSale(propertyId, msg.sender, price);
    }

    ///  Remove a property from sale.
    function delistFromSale(uint256 propertyId)
        external
        propertyExists(propertyId)
        onlyCurrentOwner(propertyId)
    {
        Property storage p = properties[propertyId];
        require(p.isForSale, "PropertyRegistry: property is not listed");

        p.isForSale = false;
        p.listPrice = 0;

        emit PropertyDelisted(propertyId, msg.sender);
    }

    ///  Gift or inherit a property to another address without payment.
    function transferProperty(uint256 propertyId, address newOwner)
        external
        propertyExists(propertyId)
        onlyCurrentOwner(propertyId)
    {
        require(newOwner != address(0),          "PropertyRegistry: zero address");
        require(newOwner != msg.sender,          "PropertyRegistry: cannot transfer to yourself");

        _transferOwnership(propertyId, msg.sender, newOwner, false);
        emit PropertyTransferred(propertyId, msg.sender, newOwner);
    }

    //  Public / Payable Functions

    ///  Purchase a listed property. msg.value must exactly match listPrice.
    function buyProperty(uint256 propertyId)
        external
        payable
        propertyExists(propertyId)
    {
        Property storage p = properties[propertyId];

        // Business rules
        require(p.isForSale,                          "PropertyRegistry: property is not for sale");
        require(msg.sender != admin,                  "PropertyRegistry: admin cannot buy properties");
        require(msg.sender != p.currentOwner,         "PropertyRegistry: owner cannot buy own property");
        require(msg.value == p.listPrice,             "PropertyRegistry: incorrect ETH amount sent");

        address previousOwner = p.currentOwner;
        uint256 salePrice     = p.listPrice;

        // Transfer ownership records (also clears isForSale and listPrice).
        _transferOwnership(propertyId, previousOwner, msg.sender, true);

        // Forward funds to the seller.
        (bool sent, ) = previousOwner.call{value: salePrice}("");
        require(sent, "PropertyRegistry: ETH transfer to seller failed");

        emit PropertySold(propertyId, previousOwner, msg.sender, salePrice);
    }


    //  View / Pure Functions

    ///  Returns the complete, ordered chain of owners for a property.
    function getOwnershipHistory(uint256 propertyId)
        external
        view
        propertyExists(propertyId)
        returns (address[] memory)
    {
        return ownershipHistory[propertyId];
    }

    ///  Returns all property IDs currently owned by an address.
    function getPropertiesOwnedBy(address owner)
        external
        view
        returns (uint256[] memory)
    {
        return ownedProperties[owner];
    }

    ///  Convenience getter for a full Property struct.
    function getProperty(uint256 propertyId)
        external
        view
        propertyExists(propertyId)
        returns (Property memory)
    {
        return properties[propertyId];
    }

    //  Internal Helpers

    ///  Core ownership-transfer logic shared by buyProperty and transferProperty.
    ///  Clears the sale listing, updates the current owner, appends history,
    ///  and maintains the ownedProperties index for both parties.
    function _transferOwnership(
        uint256 propertyId,
        address from,
        address to,
        bool    wasSale
    ) internal {
        Property storage p = properties[propertyId];

        // Clear sale state regardless of transfer type.
        if (p.isForSale) {
            p.isForSale = false;
            p.listPrice = 0;
        }

        // Update the canonical owner.
        p.currentOwner = to;

        // Append to the immutable ownership history.
        ownershipHistory[propertyId].push(to);

        // Update ownedProperties index

        // Remove propertyId from the previous owner's list.
        _removeFromOwnedProperties(from, propertyId);

        // Add propertyId to the new owner's list.
        ownedProperties[to].push(propertyId);

        // Suppress unused-variable warning when wasSale is false.
        wasSale;
    }

    ///  Removes a single propertyId from an owner's ownedProperties array
    ///  using the swap-and-pop pattern for O(n) worst-case removal.
    function _removeFromOwnedProperties(address owner, uint256 propertyId) internal {
        uint256[] storage ids = ownedProperties[owner];
        uint256 length = ids.length;

        for (uint256 i = 0; i < length; i++) {
            if (ids[i] == propertyId) {
                // Swap with the last element then pop.
                ids[i] = ids[length - 1];
                ids.pop();
                return;
            }
        }
        // If not found we simply return — this should never happen under normal operation.
    }
}
