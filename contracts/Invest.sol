// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Users.sol";

contract Invest is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct InvestmentPlan {
        uint256 duration; // в днях
        uint256 returnRate; // в процентах (100 = 100%)
        uint256 minAmount;
        uint256 maxAmount;
        bool isActive;
    }

    struct Investment {
        uint256 investmentId;
        address investor;
        uint256 planId;
        uint256 amount;
        uint256 returnAmount;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isClaimed;
    }

    // Состояние
    IERC20 public gvtToken;
    DAOContracts public daoContracts;
    DAOUsers public usersContract;
    
    mapping(uint256 => InvestmentPlan) public investmentPlans;
    mapping(uint256 => Investment) public investments;
    mapping(address => uint256[]) public userInvestments;
    
    uint256 private _planCounter;
    uint256 private _investmentCounter;
    
    uint256 public constant DENOMINATOR = 100;
    uint256 public constant MIN_INVESTMENT_AMOUNT = 100 * 10**18; // 100 GVT
    uint256 public constant MAX_INVESTMENT_AMOUNT = 1000000 * 10**18; // 1M GVT
    
    // События
    event PlanCreated(uint256 indexed planId, uint256 duration, uint256 returnRate);
    event PlanUpdated(uint256 indexed planId);
    event PlanDeactivated(uint256 indexed planId);
    event InvestmentCreated(uint256 indexed investmentId, address indexed investor, uint256 planId, uint256 amount);
    event InvestmentClaimed(uint256 indexed investmentId, uint256 amount);
    
    // Модификаторы
    modifier onlyGovernance() {
        require(daoContracts.getContractAddress("DAO_GOVERNANCE") == msg.sender, "Only governance");
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
        
        // Создаем стандартные планы
        _createPlan(7, 105, MIN_INVESTMENT_AMOUNT, MAX_INVESTMENT_AMOUNT); // 7 дней - 105%
        _createPlan(30, 130, MIN_INVESTMENT_AMOUNT, MAX_INVESTMENT_AMOUNT); // 30 дней - 130%
        _createPlan(100, 200, MIN_INVESTMENT_AMOUNT, MAX_INVESTMENT_AMOUNT); // 100 дней - 200%
    }
    
    // Основные функции
    function invest(uint256 planId, uint256 amount) external nonReentrant whenNotPaused {
        InvestmentPlan storage plan = investmentPlans[planId];
        require(plan.isActive, "Plan not active");
        require(amount >= plan.minAmount, "Amount too small");
        require(amount <= plan.maxAmount, "Amount too large");
        
        uint256 returnAmount = (amount * plan.returnRate) / DENOMINATOR;
        uint256 investmentId = _investmentCounter++;
        
        investments[investmentId] = Investment({
            investmentId: investmentId,
            investor: msg.sender,
            planId: planId,
            amount: amount,
            returnAmount: returnAmount,
            startTime: block.timestamp,
            endTime: block.timestamp + (plan.duration * 1 days),
            isActive: true,
            isClaimed: false
        });
        
        userInvestments[msg.sender].push(investmentId);
        
        require(gvtToken.transferFrom(msg.sender, address(this), amount), "Transfer failed");
        
        emit InvestmentCreated(investmentId, msg.sender, planId, amount);
    }
    
    function claimInvestment(uint256 investmentId) external nonReentrant {
        Investment storage investment = investments[investmentId];
        require(investment.isActive, "Investment not active");
        require(!investment.isClaimed, "Already claimed");
        require(investment.investor == msg.sender, "Not investor");
        require(block.timestamp >= investment.endTime, "Lock period not ended");
        
        investment.isClaimed = true;
        investment.isActive = false;
        
        require(gvtToken.transfer(msg.sender, investment.returnAmount), "Transfer failed");
        
        emit InvestmentClaimed(investmentId, investment.returnAmount);
    }
    
    // Административные функции
    function _createPlan(
        uint256 duration,
        uint256 returnRate,
        uint256 minAmount,
        uint256 maxAmount
    ) internal {
        uint256 planId = _planCounter++;
        investmentPlans[planId] = InvestmentPlan({
            duration: duration,
            returnRate: returnRate,
            minAmount: minAmount,
            maxAmount: maxAmount,
            isActive: true
        });
        
        emit PlanCreated(planId, duration, returnRate);
    }
    
    function createPlan(
        uint256 duration,
        uint256 returnRate,
        uint256 minAmount,
        uint256 maxAmount
    ) external onlyOwner {
        _createPlan(duration, returnRate, minAmount, maxAmount);
    }
    
    function updatePlan(
        uint256 planId,
        uint256 returnRate,
        uint256 minAmount,
        uint256 maxAmount
    ) external onlyOwner {
        InvestmentPlan storage plan = investmentPlans[planId];
        require(plan.duration > 0, "Plan not exists");
        
        plan.returnRate = returnRate;
        plan.minAmount = minAmount;
        plan.maxAmount = maxAmount;
        
        emit PlanUpdated(planId);
    }
    
    function deactivatePlan(uint256 planId) external onlyOwner {
        InvestmentPlan storage plan = investmentPlans[planId];
        require(plan.isActive, "Plan already inactive");
        
        plan.isActive = false;
        emit PlanDeactivated(planId);
    }
    
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
    
    // Вспомогательные функции
    function getUserInvestments(address user) external view returns (uint256[] memory) {
        return userInvestments[user];
    }
    
    function getPlanDetails(uint256 planId) external view returns (
        uint256 duration,
        uint256 returnRate,
        uint256 minAmount,
        uint256 maxAmount,
        bool isActive
    ) {
        InvestmentPlan storage plan = investmentPlans[planId];
        return (
            plan.duration,
            plan.returnRate,
            plan.minAmount,
            plan.maxAmount,
            plan.isActive
        );
    }
    
    function getInvestmentDetails(uint256 investmentId) external view returns (
        uint256 id,
        address investor,
        uint256 planId,
        uint256 amount,
        uint256 returnAmount,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isClaimed
    ) {
        Investment storage investment = investments[investmentId];
        return (
            investment.investmentId,
            investment.investor,
            investment.planId,
            investment.amount,
            investment.returnAmount,
            investment.startTime,
            investment.endTime,
            investment.isActive,
            investment.isClaimed
        );
    }
} 