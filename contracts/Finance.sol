// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Users.sol";
import "./GoodVibeNFT.sol";

contract Finance is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    // Константы
    uint256 public constant MIN_KARMA_FOR_PROPOSAL = 100;
    uint256 public constant MIN_VERIFICATIONS = 3;
    uint256 public constant VOTES_PER_RATING = 10;
    uint256 public constant MAX_VOTES_PER_PROPOSAL = 10;
    uint256 public constant PROPOSAL_PERIOD = 7 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant DEVELOPMENT_PERIOD = 7 days;

    // Структуры
    struct Proposal {
        uint256 id;
        address proposer;
        string title;
        string description;
        uint256 requiredAmount;
        uint256 donatedAmount;
        uint256 totalVotes;
        uint256 startTime;
        uint256 endTime;
        ProposalStatus status;
        address implementationContract;
    }

    struct Vote {
        uint256 proposalId;
        uint256 voteCount;
    }

    // Перечисления
    enum ProposalStatus {
        Active,
        Voting,
        Development,
        Implemented,
        Rejected
    }

    // Состояние
    DAOUsers public usersContract;
    GoodVibeNFT public nftContract;
    IERC20 public gvtToken;
    address public founder;
    address public daoDevelopers;

    mapping(uint256 => Proposal) public proposals;
    mapping(address => mapping(uint256 => uint256)) public userVotes;
    mapping(address => uint256) public totalUserVotes;
    mapping(uint256 => mapping(address => bool)) public hasVoted;
    mapping(uint256 => address) public implementationContracts;

    Counters.Counter private _proposalIds;
    uint256 public currentPeriodStart;
    uint256 public currentPeriod;

    // События
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string title, uint256 requiredAmount, uint256 donatedAmount);
    event ProposalVoted(uint256 indexed proposalId, address indexed voter, uint256 voteCount);
    event ProposalImplemented(uint256 indexed proposalId, address indexed implementationContract);
    event PeriodChanged(uint256 newPeriod);

    // Модификаторы
    modifier onlyVerifiedUser() {
        require(
            usersContract.users(msg.sender).verificationCount >= MIN_VERIFICATIONS ||
            (usersContract.users(msg.sender).verificationCount >= 1 && usersContract.verifications(msg.sender)[founder]),
            "Not verified"
        );
        _;
    }

    modifier onlyDAODevelopers() {
        require(msg.sender == daoDevelopers, "Only DAO Developers");
        _;
    }

    modifier onlyActivePeriod() {
        require(block.timestamp >= currentPeriodStart && 
                block.timestamp < currentPeriodStart + PROPOSAL_PERIOD + VOTING_PERIOD + DEVELOPMENT_PERIOD,
                "Not active period");
        _;
    }

    // Конструктор
    constructor(
        address _usersContract,
        address _nftContract,
        address _gvtToken,
        address _founder,
        address _daoDevelopers
    ) Ownable(msg.sender) {
        usersContract = DAOUsers(_usersContract);
        nftContract = GoodVibeNFT(_nftContract);
        gvtToken = IERC20(_gvtToken);
        founder = _founder;
        daoDevelopers = _daoDevelopers;
        currentPeriodStart = block.timestamp;
        currentPeriod = 1;
    }

    // Основные функции
    function createProposal(
        string memory title,
        string memory description,
        uint256 requiredAmount,
        uint256 donatedAmount
    ) external nonReentrant onlyVerifiedUser onlyActivePeriod {
        require(block.timestamp < currentPeriodStart + PROPOSAL_PERIOD, "Proposal period ended");
        require(requiredAmount > 0, "Invalid required amount");
        require(donatedAmount > 0, "Invalid donated amount");
        require(gvtToken.transferFrom(msg.sender, address(this), donatedAmount), "Transfer failed");

        uint256 proposalId = _proposalIds.current();
        _proposalIds.increment();

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            title: title,
            description: description,
            requiredAmount: requiredAmount,
            donatedAmount: donatedAmount,
            totalVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + PROPOSAL_PERIOD + VOTING_PERIOD + DEVELOPMENT_PERIOD,
            status: ProposalStatus.Active,
            implementationContract: address(0)
        });

        emit ProposalCreated(proposalId, msg.sender, title, requiredAmount, donatedAmount);
    }

    function vote(uint256 proposalId, uint256 voteCount) external onlyVerifiedUser {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Not active");
        require(block.timestamp >= currentPeriodStart + PROPOSAL_PERIOD, "Voting not started");
        require(block.timestamp < currentPeriodStart + PROPOSAL_PERIOD + VOTING_PERIOD, "Voting ended");
        require(!hasVoted[proposalId][msg.sender], "Already voted");
        require(voteCount <= MAX_VOTES_PER_PROPOSAL, "Too many votes");

        uint256 userRating = usersContract.users(msg.sender).rating;
        uint256 availableVotes = userRating * VOTES_PER_RATING;
        require(totalUserVotes[msg.sender] + voteCount <= availableVotes, "Not enough votes");

        proposal.totalVotes += voteCount;
        userVotes[msg.sender][proposalId] = voteCount;
        totalUserVotes[msg.sender] += voteCount;
        hasVoted[proposalId][msg.sender] = true;

        emit ProposalVoted(proposalId, msg.sender, voteCount);
    }

    function implementProposal(uint256 proposalId, address implementationContract) 
        external 
        onlyDAODevelopers 
    {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Not active");
        require(block.timestamp >= currentPeriodStart + PROPOSAL_PERIOD + VOTING_PERIOD, "Development not started");
        require(block.timestamp < currentPeriodStart + PROPOSAL_PERIOD + VOTING_PERIOD + DEVELOPMENT_PERIOD, "Development ended");
        require(implementationContract != address(0), "Invalid implementation contract");

        proposal.status = ProposalStatus.Implemented;
        proposal.implementationContract = implementationContract;
        implementationContracts[proposalId] = implementationContract;

        require(gvtToken.transfer(implementationContract, proposal.requiredAmount), "Transfer failed");
        emit ProposalImplemented(proposalId, implementationContract);
    }

    function startNewPeriod() external onlyOwner {
        require(block.timestamp >= currentPeriodStart + PROPOSAL_PERIOD + VOTING_PERIOD + DEVELOPMENT_PERIOD, "Current period not ended");
        
        currentPeriodStart = block.timestamp;
        currentPeriod++;
        
        // Сброс голосов пользователей
        for (uint256 i = 0; i < _proposalIds.current(); i++) {
            if (proposals[i].status == ProposalStatus.Active) {
                proposals[i].status = ProposalStatus.Rejected;
            }
        }
        
        emit PeriodChanged(currentPeriod);
    }

    // Вспомогательные функции
    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        string memory title,
        string memory description,
        uint256 requiredAmount,
        uint256 donatedAmount,
        uint256 totalVotes,
        uint256 startTime,
        uint256 endTime,
        ProposalStatus status,
        address implementationContract
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.title,
            proposal.description,
            proposal.requiredAmount,
            proposal.donatedAmount,
            proposal.totalVotes,
            proposal.startTime,
            proposal.endTime,
            proposal.status,
            proposal.implementationContract
        );
    }

    function getUserVotes(address user, uint256 proposalId) external view returns (uint256) {
        return userVotes[user][proposalId];
    }

    function getTotalUserVotes(address user) external view returns (uint256) {
        return totalUserVotes[user];
    }

    function getAvailableVotes(address user) external view returns (uint256) {
        uint256 userRating = usersContract.users(user).rating;
        return (userRating * VOTES_PER_RATING) - totalUserVotes[user];
    }
} 