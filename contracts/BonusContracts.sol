// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Users.sol";

contract BonusContracts is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct BonusContract {
        uint256 contractId;
        string name;
        string description;
        string ipfsMetadata;
        uint256 rewardAmount;
        uint256 startTime;
        uint256 endTime;
        uint256 minKarma;
        uint256 minRating;
        uint256 maxParticipants;
        uint256 currentParticipants;
        bool isActive;
        mapping(address => bool) hasClaimed;
    }

    struct BonusClaim {
        uint256 claimId;
        uint256 contractId;
        address user;
        uint256 amount;
        uint256 claimedAt;
    }

    // Состояние
    IERC20 public gvtToken;
    DAOContracts public daoContracts;
    DAOUsers public usersContract;
    
    mapping(uint256 => BonusContract) public bonusContracts;
    mapping(uint256 => BonusClaim) public bonusClaims;
    mapping(address => uint256[]) public userClaims;
    
    uint256 private _contractCounter;
    uint256 private _claimCounter;
    
    uint256 public constant MIN_REWARD = 10 * 10**18; // 10 GVT
    uint256 public constant MAX_REWARD = 10000 * 10**18; // 10K GVT
    
    // События
    event BonusContractCreated(uint256 indexed contractId, string name, uint256 rewardAmount);
    event BonusContractUpdated(uint256 indexed contractId);
    event BonusContractDeactivated(uint256 indexed contractId);
    event BonusClaimed(uint256 indexed claimId, address indexed user, uint256 contractId, uint256 amount);
    
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
    }
    
    // Основные функции
    function createBonusContract(
        string memory name,
        string memory description,
        string memory ipfsMetadata,
        uint256 rewardAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 minKarma,
        uint256 minRating,
        uint256 maxParticipants
    ) external onlyOwner {
        require(rewardAmount >= MIN_REWARD, "Reward too small");
        require(rewardAmount <= MAX_REWARD, "Reward too large");
        require(startTime < endTime, "Invalid time range");
        require(maxParticipants > 0, "Invalid participants limit");
        
        uint256 contractId = _contractCounter++;
        BonusContract storage contract = bonusContracts[contractId];
        contract.contractId = contractId;
        contract.name = name;
        contract.description = description;
        contract.ipfsMetadata = ipfsMetadata;
        contract.rewardAmount = rewardAmount;
        contract.startTime = startTime;
        contract.endTime = endTime;
        contract.minKarma = minKarma;
        contract.minRating = minRating;
        contract.maxParticipants = maxParticipants;
        contract.currentParticipants = 0;
        contract.isActive = true;
        
        emit BonusContractCreated(contractId, name, rewardAmount);
    }
    
    function claimBonus(uint256 contractId) external nonReentrant whenNotPaused {
        BonusContract storage contract = bonusContracts[contractId];
        require(contract.isActive, "Contract not active");
        require(block.timestamp >= contract.startTime, "Not started yet");
        require(block.timestamp <= contract.endTime, "Already ended");
        require(!contract.hasClaimed[msg.sender], "Already claimed");
        require(contract.currentParticipants < contract.maxParticipants, "Max participants reached");
        
        // Проверяем требования пользователя
        DAOUsers.User memory user = usersContract.users(msg.sender);
        require(user.karma >= contract.minKarma, "Insufficient karma");
        require(user.rating >= contract.minRating, "Insufficient rating");
        
        uint256 claimId = _claimCounter++;
        bonusClaims[claimId] = BonusClaim({
            claimId: claimId,
            contractId: contractId,
            user: msg.sender,
            amount: contract.rewardAmount,
            claimedAt: block.timestamp
        });
        
        contract.hasClaimed[msg.sender] = true;
        contract.currentParticipants++;
        
        if (contract.currentParticipants >= contract.maxParticipants) {
            contract.isActive = false;
        }
        
        userClaims[msg.sender].push(claimId);
        
        require(gvtToken.transfer(msg.sender, contract.rewardAmount), "Transfer failed");
        
        emit BonusClaimed(claimId, msg.sender, contractId, contract.rewardAmount);
    }
    
    // Административные функции
    function updateBonusContract(
        uint256 contractId,
        string memory description,
        string memory ipfsMetadata,
        uint256 rewardAmount,
        uint256 minKarma,
        uint256 minRating,
        uint256 maxParticipants
    ) external onlyOwner {
        BonusContract storage contract = bonusContracts[contractId];
        require(contract.contractId > 0, "Contract not exists");
        require(rewardAmount >= MIN_REWARD, "Reward too small");
        require(rewardAmount <= MAX_REWARD, "Reward too large");
        require(maxParticipants >= contract.currentParticipants, "Invalid participants limit");
        
        contract.description = description;
        contract.ipfsMetadata = ipfsMetadata;
        contract.rewardAmount = rewardAmount;
        contract.minKarma = minKarma;
        contract.minRating = minRating;
        contract.maxParticipants = maxParticipants;
        
        emit BonusContractUpdated(contractId);
    }
    
    function deactivateBonusContract(uint256 contractId) external onlyOwner {
        BonusContract storage contract = bonusContracts[contractId];
        require(contract.isActive, "Contract already inactive");
        
        contract.isActive = false;
        emit BonusContractDeactivated(contractId);
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
    function getUserClaims(address user) external view returns (uint256[] memory) {
        return userClaims[user];
    }
    
    function getBonusContractDetails(uint256 contractId) external view returns (
        uint256 id,
        string memory name,
        string memory description,
        string memory ipfsMetadata,
        uint256 rewardAmount,
        uint256 startTime,
        uint256 endTime,
        uint256 minKarma,
        uint256 minRating,
        uint256 maxParticipants,
        uint256 currentParticipants,
        bool isActive
    ) {
        BonusContract storage contract = bonusContracts[contractId];
        return (
            contract.contractId,
            contract.name,
            contract.description,
            contract.ipfsMetadata,
            contract.rewardAmount,
            contract.startTime,
            contract.endTime,
            contract.minKarma,
            contract.minRating,
            contract.maxParticipants,
            contract.currentParticipants,
            contract.isActive
        );
    }
    
    function getClaimDetails(uint256 claimId) external view returns (
        uint256 id,
        uint256 contractId,
        address user,
        uint256 amount,
        uint256 claimedAt
    ) {
        BonusClaim storage claim = bonusClaims[claimId];
        return (
            claim.claimId,
            claim.contractId,
            claim.user,
            claim.amount,
            claim.claimedAt
        );
    }
    
    function hasUserClaimed(uint256 contractId, address user) external view returns (bool) {
        return bonusContracts[contractId].hasClaimed[user];
    }
} 