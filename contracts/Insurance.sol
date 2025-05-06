// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract Insurance is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct InsurancePolicy {
        uint256 policyId;
        address holder;
        uint256 amount;
        uint256 premium;
        uint256 startTime;
        uint256 endTime;
        bool isActive;
        bool isClaimed;
    }

    struct Claim {
        uint256 claimId;
        uint256 policyId;
        address claimant;
        uint256 amount;
        string ipfsEvidence;
        uint256 timestamp;
        bool isApproved;
        bool isRejected;
    }

    // Состояние
    IERC20 public gvtToken;
    address public futureFond;
    uint256 public constant MIN_POLICY_DURATION = 30 days;
    uint256 public constant MAX_POLICY_DURATION = 365 days;
    uint256 public constant MIN_PREMIUM_PERCENTAGE = 5; // 5%
    uint256 public constant MAX_PREMIUM_PERCENTAGE = 20; // 20%
    
    mapping(uint256 => InsurancePolicy) public policies;
    mapping(uint256 => Claim) public claims;
    mapping(address => uint256[]) public userPolicies;
    
    uint256 private _policyCounter;
    uint256 private _claimCounter;
    
    // События
    event PolicyCreated(uint256 indexed policyId, address indexed holder, uint256 amount);
    event PolicyExpired(uint256 indexed policyId);
    event ClaimSubmitted(uint256 indexed claimId, uint256 indexed policyId);
    event ClaimApproved(uint256 indexed claimId, uint256 amount);
    event ClaimRejected(uint256 indexed claimId);
    event PremiumPaid(uint256 indexed policyId, uint256 amount);
    
    // Модификаторы
    modifier onlyFutureFond() {
        require(msg.sender == futureFond, "Only Future Fond");
        _;
    }
    
    modifier onlyPolicyHolder(uint256 policyId) {
        require(policies[policyId].holder == msg.sender, "Not policy holder");
        _;
    }
    
    // Конструктор
    constructor(
        address _gvtToken,
        address _futureFond
    ) Ownable(msg.sender) {
        gvtToken = IERC20(_gvtToken);
        futureFond = _futureFond;
    }
    
    // Основные функции
    function createPolicy(
        uint256 amount,
        uint256 duration
    ) external nonReentrant whenNotPaused {
        require(duration >= MIN_POLICY_DURATION, "Duration too short");
        require(duration <= MAX_POLICY_DURATION, "Duration too long");
        
        uint256 premium = calculatePremium(amount, duration);
        require(gvtToken.transferFrom(msg.sender, address(this), premium), "Premium transfer failed");
        
        uint256 policyId = _policyCounter++;
        policies[policyId] = InsurancePolicy({
            policyId: policyId,
            holder: msg.sender,
            amount: amount,
            premium: premium,
            startTime: block.timestamp,
            endTime: block.timestamp + duration,
            isActive: true,
            isClaimed: false
        });
        
        userPolicies[msg.sender].push(policyId);
        
        emit PolicyCreated(policyId, msg.sender, amount);
        emit PremiumPaid(policyId, premium);
    }
    
    function submitClaim(
        uint256 policyId,
        string memory ipfsEvidence
    ) external nonReentrant whenNotPaused onlyPolicyHolder(policyId) {
        InsurancePolicy storage policy = policies[policyId];
        require(policy.isActive, "Policy not active");
        require(!policy.isClaimed, "Already claimed");
        require(block.timestamp <= policy.endTime, "Policy expired");
        
        uint256 claimId = _claimCounter++;
        claims[claimId] = Claim({
            claimId: claimId,
            policyId: policyId,
            claimant: msg.sender,
            amount: policy.amount,
            ipfsEvidence: ipfsEvidence,
            timestamp: block.timestamp,
            isApproved: false,
            isRejected: false
        });
        
        emit ClaimSubmitted(claimId, policyId);
    }
    
    function approveClaim(uint256 claimId) external onlyOwner nonReentrant {
        Claim storage claim = claims[claimId];
        require(!claim.isApproved && !claim.isRejected, "Claim already processed");
        
        InsurancePolicy storage policy = policies[claim.policyId];
        require(policy.isActive, "Policy not active");
        
        claim.isApproved = true;
        policy.isClaimed = true;
        policy.isActive = false;
        
        require(gvtToken.transfer(claim.claimant, claim.amount), "Transfer failed");
        
        emit ClaimApproved(claimId, claim.amount);
    }
    
    function rejectClaim(uint256 claimId) external onlyOwner {
        Claim storage claim = claims[claimId];
        require(!claim.isApproved && !claim.isRejected, "Claim already processed");
        
        claim.isRejected = true;
        emit ClaimRejected(claimId);
    }
    
    // Вспомогательные функции
    function calculatePremium(uint256 amount, uint256 duration) public pure returns (uint256) {
        uint256 basePremium = (amount * MIN_PREMIUM_PERCENTAGE) / 100;
        uint256 durationMultiplier = (duration * 100) / MIN_POLICY_DURATION;
        return (basePremium * durationMultiplier) / 100;
    }
    
    function getUserPolicies(address user) external view returns (uint256[] memory) {
        return userPolicies[user];
    }
    
    function getPolicyDetails(uint256 policyId) external view returns (
        uint256 policyId_,
        address holder,
        uint256 amount,
        uint256 premium,
        uint256 startTime,
        uint256 endTime,
        bool isActive,
        bool isClaimed
    ) {
        InsurancePolicy storage policy = policies[policyId];
        return (
            policy.policyId,
            policy.holder,
            policy.amount,
            policy.premium,
            policy.startTime,
            policy.endTime,
            policy.isActive,
            policy.isClaimed
        );
    }
    
    function getClaimDetails(uint256 claimId) external view returns (
        uint256 claimId_,
        uint256 policyId,
        address claimant,
        uint256 amount,
        string memory ipfsEvidence,
        uint256 timestamp,
        bool isApproved,
        bool isRejected
    ) {
        Claim storage claim = claims[claimId];
        return (
            claim.claimId,
            claim.policyId,
            claim.claimant,
            claim.amount,
            claim.ipfsEvidence,
            claim.timestamp,
            claim.isApproved,
            claim.isRejected
        );
    }
    
    // Административные функции
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function updateFutureFond(address _futureFond) external onlyOwner {
        futureFond = _futureFond;
    }
} 