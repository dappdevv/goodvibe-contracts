// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Users.sol";

contract Marketplace is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct Listing {
        uint256 listingId;
        address seller;
        string itemType; // PRODUCT, SERVICE, RENTAL, EXCHANGE
        string title;
        string description;
        string ipfsMetadata;
        uint256 price;
        uint256 quantity;
        uint256 availableQuantity;
        bool isActive;
        uint256 createdAt;
        uint256 expiryDate;
    }

    struct Order {
        uint256 orderId;
        uint256 listingId;
        address buyer;
        address seller;
        uint256 quantity;
        uint256 totalPrice;
        OrderStatus status;
        uint256 createdAt;
        uint256 deadline;
        string ipfsProof;
    }

    struct Dispute {
        uint256 disputeId;
        uint256 orderId;
        address initiator;
        string ipfsEvidence;
        uint256 createdAt;
        DisputeStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
    }

    // Перечисления
    enum OrderStatus {
        PENDING,
        PAID,
        SHIPPED,
        DELIVERED,
        COMPLETED,
        DISPUTED,
        CANCELLED,
        REFUNDED
    }

    enum DisputeStatus {
        OPEN,
        RESOLVED,
        CANCELLED
    }

    enum DisputeResolution {
        NONE,
        BUYER_WIN,
        SELLER_WIN,
        REFUND
    }

    // Состояние
    IERC20 public gvtToken;
    DAOContracts public daoContracts;
    DAOUsers public usersContract;
    
    mapping(uint256 => Listing) public listings;
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public userListings;
    mapping(address => uint256[]) public userOrders;
    
    uint256 private _listingCounter;
    uint256 private _orderCounter;
    uint256 private _disputeCounter;
    
    uint256 public constant ORDER_TIMEOUT = 7 days;
    uint256 public constant DISPUTE_VOTING_PERIOD = 3 days;
    uint256 public constant MAX_LISTING_DURATION = 90 days;
    uint256 public constant PLATFORM_FEE = 25; // 2.5%
    uint256 public constant FEE_DENOMINATOR = 1000;
    
    // События
    event ListingCreated(uint256 indexed listingId, address indexed seller, string itemType);
    event ListingUpdated(uint256 indexed listingId);
    event ListingCancelled(uint256 indexed listingId);
    event OrderCreated(uint256 indexed orderId, uint256 indexed listingId, address indexed buyer);
    event OrderPaid(uint256 indexed orderId);
    event OrderShipped(uint256 indexed orderId);
    event OrderDelivered(uint256 indexed orderId);
    event OrderCompleted(uint256 indexed orderId);
    event OrderDisputed(uint256 indexed orderId, uint256 indexed disputeId);
    event DisputeResolved(uint256 indexed disputeId, DisputeResolution resolution);
    
    // Модификаторы
    modifier onlyGovernance() {
        require(daoContracts.getContractAddress("DAO_GOVERNANCE") == msg.sender, "Only governance");
        _;
    }
    
    modifier onlyOrderParticipant(uint256 orderId) {
        require(
            orders[orderId].buyer == msg.sender || 
            orders[orderId].seller == msg.sender,
            "Not order participant"
        );
        _;
    }
    
    // Конструктор
    constructor(
        address _gvtToken,
        address _daoContracts,
        address _usersContract
    ) Ownable(msg.sender) {
        gvtToken = IERC20(_gvtToken);
        daoContracts = DAOContracts(_daoContracts);
        usersContract = DAOUsers(_usersContract);
    }
    
    // Основные функции
    function createListing(
        string memory itemType,
        string memory title,
        string memory description,
        string memory ipfsMetadata,
        uint256 price,
        uint256 quantity,
        uint256 duration
    ) external nonReentrant whenNotPaused {
        require(duration <= MAX_LISTING_DURATION, "Duration too long");
        require(price > 0, "Invalid price");
        require(quantity > 0, "Invalid quantity");
        
        uint256 listingId = _listingCounter++;
        listings[listingId] = Listing({
            listingId: listingId,
            seller: msg.sender,
            itemType: itemType,
            title: title,
            description: description,
            ipfsMetadata: ipfsMetadata,
            price: price,
            quantity: quantity,
            availableQuantity: quantity,
            isActive: true,
            createdAt: block.timestamp,
            expiryDate: block.timestamp + (duration * 1 days)
        });
        
        userListings[msg.sender].push(listingId);
        
        emit ListingCreated(listingId, msg.sender, itemType);
    }
    
    function createOrder(uint256 listingId, uint256 quantity) external nonReentrant whenNotPaused {
        Listing storage listing = listings[listingId];
        require(listing.isActive, "Listing not active");
        require(listing.availableQuantity >= quantity, "Insufficient quantity");
        require(block.timestamp <= listing.expiryDate, "Listing expired");
        require(listing.seller != msg.sender, "Cannot buy your own listing");
        
        uint256 totalPrice = listing.price * quantity;
        uint256 fee = (totalPrice * PLATFORM_FEE) / FEE_DENOMINATOR;
        uint256 orderId = _orderCounter++;
        
        orders[orderId] = Order({
            orderId: orderId,
            listingId: listingId,
            buyer: msg.sender,
            seller: listing.seller,
            quantity: quantity,
            totalPrice: totalPrice,
            status: OrderStatus.PENDING,
            createdAt: block.timestamp,
            deadline: block.timestamp + ORDER_TIMEOUT,
            ipfsProof: ""
        });
        
        listing.availableQuantity -= quantity;
        if (listing.availableQuantity == 0) {
            listing.isActive = false;
        }
        
        userOrders[msg.sender].push(orderId);
        
        emit OrderCreated(orderId, listingId, msg.sender);
    }
    
    function confirmPayment(uint256 orderId) external nonReentrant onlyOrderParticipant(orderId) {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.PENDING, "Invalid order status");
        require(order.buyer == msg.sender, "Only buyer can confirm");
        
        uint256 fee = (order.totalPrice * PLATFORM_FEE) / FEE_DENOMINATOR;
        require(gvtToken.transferFrom(msg.sender, address(this), order.totalPrice), "Payment failed");
        
        order.status = OrderStatus.PAID;
        emit OrderPaid(orderId);
    }
    
    function confirmShipment(uint256 orderId) external nonReentrant onlyOrderParticipant(orderId) {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.PAID, "Order not paid");
        require(order.seller == msg.sender, "Only seller can confirm");
        
        order.status = OrderStatus.SHIPPED;
        emit OrderShipped(orderId);
    }
    
    function confirmDelivery(uint256 orderId) external nonReentrant onlyOrderParticipant(orderId) {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.SHIPPED, "Order not shipped");
        require(order.buyer == msg.sender, "Only buyer can confirm");
        
        order.status = OrderStatus.DELIVERED;
        emit OrderDelivered(orderId);
    }
    
    function completeOrder(uint256 orderId) external nonReentrant onlyOrderParticipant(orderId) {
        Order storage order = orders[orderId];
        require(order.status == OrderStatus.DELIVERED, "Order not delivered");
        require(order.seller == msg.sender, "Only seller can complete");
        
        uint256 fee = (order.totalPrice * PLATFORM_FEE) / FEE_DENOMINATOR;
        require(gvtToken.transfer(order.seller, order.totalPrice - fee), "Transfer failed");
        
        order.status = OrderStatus.COMPLETED;
        emit OrderCompleted(orderId);
    }
    
    function openDispute(
        uint256 orderId,
        string memory ipfsEvidence
    ) external nonReentrant onlyOrderParticipant(orderId) {
        Order storage order = orders[orderId];
        require(order.status != OrderStatus.COMPLETED, "Order already completed");
        require(order.status != OrderStatus.DISPUTED, "Dispute already open");
        
        uint256 disputeId = _disputeCounter++;
        Dispute storage dispute = disputes[disputeId];
        dispute.disputeId = disputeId;
        dispute.orderId = orderId;
        dispute.initiator = msg.sender;
        dispute.ipfsEvidence = ipfsEvidence;
        dispute.createdAt = block.timestamp;
        dispute.status = DisputeStatus.OPEN;
        dispute.votesFor = 0;
        dispute.votesAgainst = 0;
        
        order.status = OrderStatus.DISPUTED;
        
        emit OrderDisputed(orderId, disputeId);
    }
    
    function resolveDispute(
        uint256 disputeId,
        DisputeResolution resolution
    ) external onlyGovernance {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.status == DisputeStatus.OPEN, "Dispute not open");
        
        Order storage order = orders[dispute.orderId];
        address buyer = order.buyer;
        address seller = order.seller;
        
        if (resolution == DisputeResolution.BUYER_WIN) {
            // Возвращаем средства покупателю
            require(gvtToken.transfer(buyer, order.totalPrice), "Transfer failed");
            // Наказываем продавца
            _punishUser(seller, true);
        } else if (resolution == DisputeResolution.SELLER_WIN) {
            // Переводим средства продавцу
            uint256 fee = (order.totalPrice * PLATFORM_FEE) / FEE_DENOMINATOR;
            require(gvtToken.transfer(seller, order.totalPrice - fee), "Transfer failed");
            // Наказываем покупателя
            _punishUser(buyer, true);
        } else if (resolution == DisputeResolution.REFUND) {
            // Возвращаем средства покупателю
            require(gvtToken.transfer(buyer, order.totalPrice), "Transfer failed");
            // Наказываем обоих за невнимательность
            _punishUser(buyer, false);
            _punishUser(seller, false);
        }
        
        dispute.status = DisputeStatus.RESOLVED;
        order.status = OrderStatus.REFUNDED;
        
        emit DisputeResolved(disputeId, resolution);
    }
    
    // Вспомогательные функции
    function _punishUser(address user, bool isScam) internal {
        if (isScam) {
            // Устанавливаем статус SCAM и наказываем
            usersContract.setUserStatus(user, 3); // 3 = SCAM
            usersContract.decreaseKarma(user, 100);
            usersContract.decreaseRating(user, 3);
        } else {
            // Только уменьшаем рейтинг за невнимательность
            usersContract.decreaseRating(user, 1);
        }
    }
    
    function getUserListings(address user) external view returns (uint256[] memory) {
        return userListings[user];
    }
    
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }
    
    function getListingDetails(uint256 listingId) external view returns (
        uint256 id,
        address seller,
        string memory itemType,
        string memory title,
        string memory description,
        string memory ipfsMetadata,
        uint256 price,
        uint256 quantity,
        uint256 availableQuantity,
        bool isActive,
        uint256 createdAt,
        uint256 expiryDate
    ) {
        Listing storage listing = listings[listingId];
        return (
            listing.listingId,
            listing.seller,
            listing.itemType,
            listing.title,
            listing.description,
            listing.ipfsMetadata,
            listing.price,
            listing.quantity,
            listing.availableQuantity,
            listing.isActive,
            listing.createdAt,
            listing.expiryDate
        );
    }
    
    function getOrderDetails(uint256 orderId) external view returns (
        uint256 id,
        uint256 listingId,
        address buyer,
        address seller,
        uint256 quantity,
        uint256 totalPrice,
        OrderStatus status,
        uint256 createdAt,
        uint256 deadline,
        string memory ipfsProof
    ) {
        Order storage order = orders[orderId];
        return (
            order.orderId,
            order.listingId,
            order.buyer,
            order.seller,
            order.quantity,
            order.totalPrice,
            order.status,
            order.createdAt,
            order.deadline,
            order.ipfsProof
        );
    }
    
    // Административные функции
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function updateContracts(
        address _gvtToken,
        address _daoContracts,
        address _usersContract
    ) external onlyOwner {
        gvtToken = IERC20(_gvtToken);
        daoContracts = DAOContracts(_daoContracts);
        usersContract = DAOUsers(_usersContract);
    }
} 