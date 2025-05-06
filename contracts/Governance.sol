// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./Users.sol";
import "./GoodVibeNFT.sol";

contract Governance is Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;

    // Константы
    uint256 public constant FOUNDER_VOTES = 1000000;
    uint256 public constant MIN_KARMA_FOR_PROPOSAL = 100;
    uint256 public constant MIN_VERIFICATIONS = 3;
    uint256 public constant PROPOSAL_COOLDOWN = 31 days;
    uint256 public constant VOTING_PERIOD = 7 days;
    uint256 public constant SUPPORT_THRESHOLD = 70; // 70%
    uint256 public constant OPPOSITION_THRESHOLD = 40; // 40%
    uint256 public constant VARIANT_SUPPORT_THRESHOLD = 80; // 80%
    uint256 public constant DEPLOYMENT_THRESHOLD = 70; // 70%

    // Структуры
    struct Proposal {
        uint256 id;
        address proposer;
        string description;
        uint256 stakedTokens;
        uint256 startTime;
        uint256 endTime;
        uint256 forVotes;
        uint256 againstVotes;
        ProposalStatus status;
        address acceptedVariant;
        bool isDeployed;
    }

    struct Variant {
        uint256 id;
        address author;
        string description;
        uint256 votes;
        bool isAccepted;
    }

    // Перечисления
    enum ProposalStatus {
        Active,
        UnderConsideration,
        Accepted,
        Rejected,
        Deployment
    }

    // Состояние
    DAOUsers public usersContract;
    GoodVibeNFT public nftContract;
    IERC20 public gvtToken;
    address public founder;
    address public daoDevelopers;
    address public daoChanger;

    mapping(uint256 => Proposal) public proposals;
    mapping(uint256 => mapping(uint256 => Variant)) public variants;
    mapping(address => uint256) public lastProposalTime;
    mapping(address => mapping(uint256 => bool)) public hasVoted;
    mapping(address => mapping(uint256 => bool)) public hasVotedVariant;
    mapping(uint256 => Counters.Counter) public variantCounters;

    Counters.Counter private _proposalIds;
    Counters.Counter private _variantIds;

    // События
    event ProposalCreated(uint256 indexed proposalId, address indexed proposer, string description, uint256 stakedTokens);
    event ProposalVoted(uint256 indexed proposalId, address indexed voter, bool support, uint256 votes);
    event VariantAdded(uint256 indexed proposalId, uint256 indexed variantId, address indexed author, string description);
    event VariantVoted(uint256 indexed proposalId, uint256 indexed variantId, address indexed voter);
    event ProposalStatusChanged(uint256 indexed proposalId, ProposalStatus newStatus);
    event ProposalDeployed(uint256 indexed proposalId, address indexed daoChanger);

    // Модификаторы
    modifier onlyVerifiedUser() {
        require(
            usersContract.users(msg.sender).verificationCount >= MIN_VERIFICATIONS ||
            (usersContract.users(msg.sender).verificationCount >= 1 && usersContract.verifications(msg.sender)[founder]),
            "Not verified"
        );
        _;
    }

    modifier onlyNFTHolder() {
        require(nftContract.balanceOf(msg.sender) > 0, "Must hold NFT");
        _;
    }

    modifier onlyDAODevelopers() {
        require(msg.sender == daoDevelopers, "Only DAO Developers");
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
    }

    // Основные функции
    function createProposal(string memory description, uint256 stakedTokens) 
        external 
        nonReentrant 
        onlyNFTHolder 
        onlyVerifiedUser 
    {
        require(block.timestamp >= lastProposalTime[msg.sender] + PROPOSAL_COOLDOWN, "Cooldown active");
        require(stakedTokens > 0, "Must stake tokens");
        require(gvtToken.transferFrom(msg.sender, address(this), stakedTokens), "Transfer failed");

        uint256 proposalId = _proposalIds.current();
        _proposalIds.increment();

        proposals[proposalId] = Proposal({
            id: proposalId,
            proposer: msg.sender,
            description: description,
            stakedTokens: stakedTokens,
            startTime: block.timestamp,
            endTime: block.timestamp + VOTING_PERIOD,
            forVotes: 0,
            againstVotes: 0,
            status: ProposalStatus.Active,
            acceptedVariant: address(0),
            isDeployed: false
        });

        lastProposalTime[msg.sender] = block.timestamp;
        emit ProposalCreated(proposalId, msg.sender, description, stakedTokens);
    }

    function vote(uint256 proposalId, bool support) external onlyVerifiedUser {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Active, "Not active");
        require(block.timestamp <= proposal.endTime, "Voting ended");
        require(!hasVoted[msg.sender][proposalId], "Already voted");

        uint256 votes = 1;
        if (msg.sender == founder) {
            votes = FOUNDER_VOTES;
        }

        if (support) {
            proposal.forVotes += votes;
        } else {
            proposal.againstVotes += votes;
            proposal.forVotes = proposal.forVotes > votes * 2 ? proposal.forVotes - votes * 2 : 0;
        }

        hasVoted[msg.sender][proposalId] = true;
        emit ProposalVoted(proposalId, msg.sender, support, votes);

        _checkProposalStatus(proposalId);
    }

    function addVariant(uint256 proposalId, string memory description) external onlyVerifiedUser {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.UnderConsideration, "Not under consideration");
        require(block.timestamp <= proposal.endTime + VOTING_PERIOD, "Variant period ended");

        uint256 variantId = _variantIds.current();
        _variantIds.increment();

        variants[proposalId][variantId] = Variant({
            id: variantId,
            author: msg.sender,
            description: description,
            votes: 0,
            isAccepted: false
        });

        variantCounters[proposalId].increment();
        emit VariantAdded(proposalId, variantId, msg.sender, description);
    }

    function voteForVariant(uint256 proposalId, uint256 variantId) external onlyVerifiedUser {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.UnderConsideration, "Not under consideration");
        require(block.timestamp <= proposal.endTime + VOTING_PERIOD, "Variant period ended");
        require(!hasVotedVariant[msg.sender][proposalId], "Already voted for variant");

        Variant storage variant = variants[proposalId][variantId];
        require(variant.id != 0, "Variant does not exist");

        uint256 votes = 1;
        if (msg.sender == founder) {
            votes = FOUNDER_VOTES;
        }

        variant.votes += votes;
        hasVotedVariant[msg.sender][proposalId] = true;
        emit VariantVoted(proposalId, variantId, msg.sender);

        _checkVariantStatus(proposalId, variantId);
    }

    function deployProposal(uint256 proposalId, address _daoChanger) external onlyDAODevelopers {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Accepted, "Not accepted");
        require(!proposal.isDeployed, "Already deployed");

        daoChanger = _daoChanger;
        proposal.status = ProposalStatus.Deployment;
        emit ProposalStatusChanged(proposalId, ProposalStatus.Deployment);
    }

    function voteForDeployment(uint256 proposalId, bool support) external onlyNFTHolder {
        Proposal storage proposal = proposals[proposalId];
        require(proposal.status == ProposalStatus.Deployment, "Not in deployment");
        require(!hasVoted[msg.sender][proposalId], "Already voted");

        if (support) {
            proposal.forVotes += 1;
        } else {
            proposal.againstVotes += 1;
        }

        hasVoted[msg.sender][proposalId] = true;
        emit ProposalVoted(proposalId, msg.sender, support, 1);

        _checkDeploymentStatus(proposalId);
    }

    // Внутренние функции
    function _checkProposalStatus(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        if (block.timestamp > proposal.endTime) {
            uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
            if (totalVotes > 0) {
                uint256 supportPercentage = (proposal.forVotes * 100) / totalVotes;
                uint256 oppositionPercentage = (proposal.againstVotes * 100) / totalVotes;

                if (supportPercentage >= SUPPORT_THRESHOLD) {
                    proposal.status = ProposalStatus.UnderConsideration;
                    proposal.endTime = block.timestamp + VOTING_PERIOD;
                    emit ProposalStatusChanged(proposalId, ProposalStatus.UnderConsideration);
                } else if (oppositionPercentage >= OPPOSITION_THRESHOLD) {
                    proposal.status = ProposalStatus.Rejected;
                    lastProposalTime[proposal.proposer] = block.timestamp + PROPOSAL_COOLDOWN * 2;
                    emit ProposalStatusChanged(proposalId, ProposalStatus.Rejected);
                }
            }
        }
    }

    function _checkVariantStatus(uint256 proposalId, uint256 variantId) internal {
        Proposal storage proposal = proposals[proposalId];
        Variant storage variant = variants[proposalId][variantId];
        
        uint256 totalVotes = 0;
        for (uint256 i = 0; i < variantCounters[proposalId].current(); i++) {
            totalVotes += variants[proposalId][i].votes;
        }

        if (totalVotes > 0) {
            uint256 supportPercentage = (variant.votes * 100) / totalVotes;
            if (supportPercentage >= VARIANT_SUPPORT_THRESHOLD) {
                proposal.status = ProposalStatus.Accepted;
                proposal.acceptedVariant = variant.author;
                emit ProposalStatusChanged(proposalId, ProposalStatus.Accepted);
            }
        }
    }

    function _checkDeploymentStatus(uint256 proposalId) internal {
        Proposal storage proposal = proposals[proposalId];
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;
        
        if (totalVotes > 0) {
            uint256 supportPercentage = (proposal.forVotes * 100) / totalVotes;
            if (supportPercentage >= DEPLOYMENT_THRESHOLD) {
                proposal.isDeployed = true;
                emit ProposalDeployed(proposalId, daoChanger);
            }
        }
    }

    // Вспомогательные функции
    function getProposal(uint256 proposalId) external view returns (
        uint256 id,
        address proposer,
        string memory description,
        uint256 stakedTokens,
        uint256 startTime,
        uint256 endTime,
        uint256 forVotes,
        uint256 againstVotes,
        ProposalStatus status,
        address acceptedVariant,
        bool isDeployed
    ) {
        Proposal storage proposal = proposals[proposalId];
        return (
            proposal.id,
            proposal.proposer,
            proposal.description,
            proposal.stakedTokens,
            proposal.startTime,
            proposal.endTime,
            proposal.forVotes,
            proposal.againstVotes,
            proposal.status,
            proposal.acceptedVariant,
            proposal.isDeployed
        );
    }

    function getVariant(uint256 proposalId, uint256 variantId) external view returns (
        uint256 id,
        address author,
        string memory description,
        uint256 votes,
        bool isAccepted
    ) {
        Variant storage variant = variants[proposalId][variantId];
        return (
            variant.id,
            variant.author,
            variant.description,
            variant.votes,
            variant.isAccepted
        );
    }
} 