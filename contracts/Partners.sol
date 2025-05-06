// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Users.sol";

contract Partners is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct Partner {
        uint256 partnerId;
        address user;
        uint256 level;
        uint256 totalReferrals;
        uint256 activeReferrals;
        uint256 totalEarnings;
        uint256 pendingEarnings;
        uint256 lastClaimTime;
        bool isActive;
    }

    struct ReferralLevel {
        uint256 level;
        uint256 minReferrals;
        uint256 rewardPercent;
        uint256 minStake;
        bool isActive;
    }

    struct Referral {
        uint256 referralId;
        address referrer;
        address referred;
        uint256 level;
        uint256 stake;
        uint256 reward;
        uint256 createdAt;
        bool isActive;
    }

    // Состояние
    IERC20 public gvtToken;
    DAOContracts public daoContracts;
    DAOUsers public usersContract;
    
    mapping(address => Partner) public partners;
    mapping(uint256 => ReferralLevel) public referralLevels;
    mapping(uint256 => Referral) public referrals;
    mapping(address => uint256[]) public userReferrals;
    
    uint256 private _levelCounter;
    uint256 private _referralCounter;
    
    uint256 public constant DENOMINATOR = 1000;
    uint256 public constant MIN_REWARD_PERCENT = 10; // 1%
    uint256 public constant MAX_REWARD_PERCENT = 500; // 50%
    uint256 public constant MIN_STAKE = 100 * 10**18; // 100 GVT
    uint256 public constant MAX_LEVELS = 10;
    
    // События
    event PartnerRegistered(address indexed user, uint256 level);
    event ReferralLevelCreated(uint256 indexed level, uint256 minReferrals, uint256 rewardPercent);
    event ReferralLevelUpdated(uint256 indexed level);
    event ReferralCreated(uint256 indexed referralId, address indexed referrer, address indexed referred);
    event RewardClaimed(address indexed partner, uint256 amount);
    
    // Модификаторы
    modifier onlyGovernance() {
        require(daoContracts.getContractAddress("DAO_GOVERNANCE") == msg.sender, "Only governance");
        _;
    }
    
    modifier onlyPartner() {
        require(partners[msg.sender].isActive, "Not a partner");
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
        
        // Создаем стандартные уровни
        _createReferralLevel(1, 0, 50, MIN_STAKE); // 5% за 1 реферала
        _createReferralLevel(2, 5, 100, MIN_STAKE * 2); // 10% за 5 рефералов
        _createReferralLevel(3, 10, 200, MIN_STAKE * 5); // 20% за 10 рефералов
    }
    
    // Основные функции
    function registerPartner(uint256 level) external nonReentrant whenNotPaused {
        require(!partners[msg.sender].isActive, "Already registered");
        require(level > 0 && level <= MAX_LEVELS, "Invalid level");
        require(referralLevels[level].isActive, "Level not active");
        
        partners[msg.sender] = Partner({
            partnerId: _levelCounter++,
            user: msg.sender,
            level: level,
            totalReferrals: 0,
            activeReferrals: 0,
            totalEarnings: 0,
            pendingEarnings: 0,
            lastClaimTime: block.timestamp,
            isActive: true
        });
        
        emit PartnerRegistered(msg.sender, level);
    }
    
    function addReferral(
        address referrer,
        address referred,
        uint256 stake
    ) external nonReentrant whenNotPaused {
        require(partners[referrer].isActive, "Referrer not active");
        require(referrer != referred, "Cannot refer yourself");
        require(stake >= MIN_STAKE, "Stake too small");
        
        Partner storage partner = partners[referrer];
        ReferralLevel storage level = referralLevels[partner.level];
        require(stake >= level.minStake, "Stake below minimum");
        
        uint256 reward = (stake * level.rewardPercent) / DENOMINATOR;
        uint256 referralId = _referralCounter++;
        
        referrals[referralId] = Referral({
            referralId: referralId,
            referrer: referrer,
            referred: referred,
            level: partner.level,
            stake: stake,
            reward: reward,
            createdAt: block.timestamp,
            isActive: true
        });
        
        userReferrals[referrer].push(referralId);
        
        partner.totalReferrals++;
        partner.activeReferrals++;
        partner.pendingEarnings += reward;
        
        emit ReferralCreated(referralId, referrer, referred);
    }
    
    function claimRewards() external nonReentrant onlyPartner {
        Partner storage partner = partners[msg.sender];
        require(partner.pendingEarnings > 0, "No rewards to claim");
        
        uint256 amount = partner.pendingEarnings;
        partner.pendingEarnings = 0;
        partner.totalEarnings += amount;
        partner.lastClaimTime = block.timestamp;
        
        require(gvtToken.transfer(msg.sender, amount), "Transfer failed");
        
        emit RewardClaimed(msg.sender, amount);
    }
    
    // Административные функции
    function _createReferralLevel(
        uint256 level,
        uint256 minReferrals,
        uint256 rewardPercent,
        uint256 minStake
    ) internal {
        require(level > 0 && level <= MAX_LEVELS, "Invalid level");
        require(rewardPercent >= MIN_REWARD_PERCENT && rewardPercent <= MAX_REWARD_PERCENT, "Invalid reward");
        require(minStake >= MIN_STAKE, "Invalid stake");
        
        referralLevels[level] = ReferralLevel({
            level: level,
            minReferrals: minReferrals,
            rewardPercent: rewardPercent,
            minStake: minStake,
            isActive: true
        });
        
        emit ReferralLevelCreated(level, minReferrals, rewardPercent);
    }
    
    function createReferralLevel(
        uint256 level,
        uint256 minReferrals,
        uint256 rewardPercent,
        uint256 minStake
    ) external onlyOwner {
        _createReferralLevel(level, minReferrals, rewardPercent, minStake);
    }
    
    function updateReferralLevel(
        uint256 level,
        uint256 minReferrals,
        uint256 rewardPercent,
        uint256 minStake
    ) external onlyOwner {
        ReferralLevel storage referralLevel = referralLevels[level];
        require(referralLevel.isActive, "Level not active");
        require(rewardPercent >= MIN_REWARD_PERCENT && rewardPercent <= MAX_REWARD_PERCENT, "Invalid reward");
        require(minStake >= MIN_STAKE, "Invalid stake");
        
        referralLevel.minReferrals = minReferrals;
        referralLevel.rewardPercent = rewardPercent;
        referralLevel.minStake = minStake;
        
        emit ReferralLevelUpdated(level);
    }
    
    function deactivatePartner(address partner) external onlyOwner {
        require(partners[partner].isActive, "Partner not active");
        partners[partner].isActive = false;
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
    function getUserReferrals(address user) external view returns (uint256[] memory) {
        return userReferrals[user];
    }
    
    function getPartnerDetails(address partner) external view returns (
        uint256 id,
        uint256 level,
        uint256 totalReferrals,
        uint256 activeReferrals,
        uint256 totalEarnings,
        uint256 pendingEarnings,
        uint256 lastClaimTime,
        bool isActive
    ) {
        Partner storage p = partners[partner];
        return (
            p.partnerId,
            p.level,
            p.totalReferrals,
            p.activeReferrals,
            p.totalEarnings,
            p.pendingEarnings,
            p.lastClaimTime,
            p.isActive
        );
    }
    
    function getReferralLevelDetails(uint256 level) external view returns (
        uint256 id,
        uint256 minReferrals,
        uint256 rewardPercent,
        uint256 minStake,
        bool isActive
    ) {
        ReferralLevel storage l = referralLevels[level];
        return (
            l.level,
            l.minReferrals,
            l.rewardPercent,
            l.minStake,
            l.isActive
        );
    }
    
    function getReferralDetails(uint256 referralId) external view returns (
        uint256 id,
        address referrer,
        address referred,
        uint256 level,
        uint256 stake,
        uint256 reward,
        uint256 createdAt,
        bool isActive
    ) {
        Referral storage r = referrals[referralId];
        return (
            r.referralId,
            r.referrer,
            r.referred,
            r.level,
            r.stake,
            r.reward,
            r.createdAt,
            r.isActive
        );
    }
} 