// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Users.sol";

contract P2P is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct Order {
        uint256 orderId;
        address maker;
        uint256 amount;
        uint256 price;
        string paymentMethod;
        string ipfsDetails;
        uint256 createdAt;
        bool isActive;
        bool isCompleted;
    }

    struct Trade {
        uint256 tradeId;
        uint256 orderId;
        address maker;
        address taker;
        uint256 amount;
        uint256 price;
        string paymentMethod;
        uint256 createdAt;
        uint256 deadline;
        TradeStatus status;
        string ipfsProof;
    }

    struct Dispute {
        uint256 disputeId;
        uint256 tradeId;
        address initiator;
        string ipfsEvidence;
        uint256 createdAt;
        DisputeStatus status;
        uint256 votesFor;
        uint256 votesAgainst;
        mapping(address => bool) hasVoted;
    }

    // Перечисления
    enum TradeStatus {
        PENDING,
        PAID,
        COMPLETED,
        DISPUTED,
        CANCELLED
    }

    enum DisputeStatus {
        OPEN,
        RESOLVED,
        CANCELLED
    }

    enum DisputeResolution {
        NONE,
        MAKER_WIN,
        TAKER_WIN,
        REFUND
    }

    // Состояние
    IERC20 public gvtToken;
    DAOContracts public daoContracts;
    DAOUsers public usersContract;
    
    mapping(uint256 => Order) public orders;
    mapping(uint256 => Trade) public trades;
    mapping(uint256 => Dispute) public disputes;
    mapping(address => uint256[]) public userOrders;
    mapping(address => uint256[]) public userTrades;
    
    uint256 private _orderCounter;
    uint256 private _tradeCounter;
    uint256 private _disputeCounter;
    
    uint256 public constant TRADE_TIMEOUT = 24 hours;
    uint256 public constant DISPUTE_VOTING_PERIOD = 3 days;
    uint256 public constant MIN_ORDER_AMOUNT = 100 * 10**18; // 100 GVT
    uint256 public constant MAX_ORDER_AMOUNT = 1000000 * 10**18; // 1M GVT
    
    // События
    event OrderCreated(uint256 indexed orderId, address indexed maker, uint256 amount, uint256 price);
    event OrderCancelled(uint256 indexed orderId);
    event TradeCreated(uint256 indexed tradeId, uint256 indexed orderId, address indexed taker);
    event TradePaid(uint256 indexed tradeId);
    event TradeCompleted(uint256 indexed tradeId);
    event TradeDisputed(uint256 indexed tradeId, uint256 indexed disputeId);
    event DisputeResolved(uint256 indexed disputeId, DisputeResolution resolution);
    
    // Модификаторы
    modifier onlyGovernance() {
        require(daoContracts.getContractAddress("DAO_GOVERNANCE") == msg.sender, "Only governance");
        _;
    }
    
    modifier onlyTradeParticipant(uint256 tradeId) {
        require(
            trades[tradeId].maker == msg.sender || 
            trades[tradeId].taker == msg.sender,
            "Not trade participant"
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
    function createOrder(
        uint256 amount,
        uint256 price,
        string memory paymentMethod,
        string memory ipfsDetails
    ) external nonReentrant whenNotPaused {
        require(amount >= MIN_ORDER_AMOUNT, "Amount too small");
        require(amount <= MAX_ORDER_AMOUNT, "Amount too large");
        require(price > 0, "Invalid price");
        
        uint256 orderId = _orderCounter++;
        orders[orderId] = Order({
            orderId: orderId,
            maker: msg.sender,
            amount: amount,
            price: price,
            paymentMethod: paymentMethod,
            ipfsDetails: ipfsDetails,
            createdAt: block.timestamp,
            isActive: true,
            isCompleted: false
        });
        
        userOrders[msg.sender].push(orderId);
        
        emit OrderCreated(orderId, msg.sender, amount, price);
    }
    
    function createTrade(uint256 orderId) external nonReentrant whenNotPaused {
        Order storage order = orders[orderId];
        require(order.isActive, "Order not active");
        require(order.maker != msg.sender, "Cannot trade with yourself");
        
        uint256 tradeId = _tradeCounter++;
        trades[tradeId] = Trade({
            tradeId: tradeId,
            orderId: orderId,
            maker: order.maker,
            taker: msg.sender,
            amount: order.amount,
            price: order.price,
            paymentMethod: order.paymentMethod,
            createdAt: block.timestamp,
            deadline: block.timestamp + TRADE_TIMEOUT,
            status: TradeStatus.PENDING,
            ipfsProof: ""
        });
        
        userTrades[msg.sender].push(tradeId);
        order.isActive = false;
        
        emit TradeCreated(tradeId, orderId, msg.sender);
    }
    
    function confirmPayment(uint256 tradeId) external nonReentrant onlyTradeParticipant(tradeId) {
        Trade storage trade = trades[tradeId];
        require(trade.status == TradeStatus.PENDING, "Invalid trade status");
        require(trade.taker == msg.sender, "Only taker can confirm");
        
        trade.status = TradeStatus.PAID;
        emit TradePaid(tradeId);
    }
    
    function completeTrade(uint256 tradeId) external nonReentrant onlyTradeParticipant(tradeId) {
        Trade storage trade = trades[tradeId];
        require(trade.status == TradeStatus.PAID, "Trade not paid");
        require(trade.maker == msg.sender, "Only maker can complete");
        
        trade.status = TradeStatus.COMPLETED;
        emit TradeCompleted(tradeId);
    }
    
    function openDispute(
        uint256 tradeId,
        string memory ipfsEvidence
    ) external nonReentrant onlyTradeParticipant(tradeId) {
        Trade storage trade = trades[tradeId];
        require(trade.status != TradeStatus.COMPLETED, "Trade already completed");
        require(trade.status != TradeStatus.DISPUTED, "Dispute already open");
        
        uint256 disputeId = _disputeCounter++;
        Dispute storage dispute = disputes[disputeId];
        dispute.disputeId = disputeId;
        dispute.tradeId = tradeId;
        dispute.initiator = msg.sender;
        dispute.ipfsEvidence = ipfsEvidence;
        dispute.createdAt = block.timestamp;
        dispute.status = DisputeStatus.OPEN;
        dispute.votesFor = 0;
        dispute.votesAgainst = 0;
        
        trade.status = TradeStatus.DISPUTED;
        
        emit TradeDisputed(tradeId, disputeId);
    }
    
    function resolveDispute(
        uint256 disputeId,
        DisputeResolution resolution
    ) external onlyGovernance {
        Dispute storage dispute = disputes[disputeId];
        require(dispute.status == DisputeStatus.OPEN, "Dispute not open");
        
        Trade storage trade = trades[dispute.tradeId];
        address maker = trade.maker;
        address taker = trade.taker;
        
        if (resolution == DisputeResolution.MAKER_WIN) {
            // Наказываем taker
            _punishUser(taker, true);
        } else if (resolution == DisputeResolution.TAKER_WIN) {
            // Наказываем maker
            _punishUser(maker, true);
        } else if (resolution == DisputeResolution.REFUND) {
            // Возвращаем средства
            require(gvtToken.transfer(taker, trade.amount), "Transfer failed");
            // Наказываем обоих за невнимательность
            _punishUser(maker, false);
            _punishUser(taker, false);
        }
        
        dispute.status = DisputeStatus.RESOLVED;
        trade.status = TradeStatus.CANCELLED;
        
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
    
    function getUserOrders(address user) external view returns (uint256[] memory) {
        return userOrders[user];
    }
    
    function getUserTrades(address user) external view returns (uint256[] memory) {
        return userTrades[user];
    }
    
    function getOrderDetails(uint256 orderId) external view returns (
        uint256 id,
        address maker,
        uint256 amount,
        uint256 price,
        string memory paymentMethod,
        string memory ipfsDetails,
        uint256 createdAt,
        bool isActive,
        bool isCompleted
    ) {
        Order storage order = orders[orderId];
        return (
            order.orderId,
            order.maker,
            order.amount,
            order.price,
            order.paymentMethod,
            order.ipfsDetails,
            order.createdAt,
            order.isActive,
            order.isCompleted
        );
    }
    
    function getTradeDetails(uint256 tradeId) external view returns (
        uint256 id,
        uint256 orderId,
        address maker,
        address taker,
        uint256 amount,
        uint256 price,
        string memory paymentMethod,
        uint256 createdAt,
        uint256 deadline,
        TradeStatus status,
        string memory ipfsProof
    ) {
        Trade storage trade = trades[tradeId];
        return (
            trade.tradeId,
            trade.orderId,
            trade.maker,
            trade.taker,
            trade.amount,
            trade.price,
            trade.paymentMethod,
            trade.createdAt,
            trade.deadline,
            trade.status,
            trade.ipfsProof
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