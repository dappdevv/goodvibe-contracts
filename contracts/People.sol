// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DAOPeople is Ownable {
    using Counters for Counters.Counter;
    
    struct SocialProfile {
        string ipfsMetadata;
        uint256 reputation;
        uint256 followers;
        uint256 following;
        Counters.Counter postCount;
        mapping(uint256 => string) achievements;
        uint8 privacyLevel;
    }
    
    struct Community {
        address creator;
        string name;
        uint256 memberCount;
        uint256 created;
        string rulesIpfsHash;
        mapping(address => bool) members;
    }
    
    mapping(address => SocialProfile) private _profiles;
    mapping(uint256 => Community) public communities;
    mapping(address => mapping(uint256 => bool)) private _nftBadges;
    mapping(bytes32 => bool) private _contentModerated;
    
    Counters.Counter private _communityId;
    uint256 public constant MIN_REPUTATION_CREATE_COMMUNITY = 500;
    
    event ProfileUpdated(address indexed user, string ipfsHash);
    event CommunityCreated(uint256 indexed id, address creator);
    event ContentFlagged(bytes32 indexed contentHash, address moderator);
    
    modifier onlyVerified() {
        require(_profiles[msg.sender].reputation >= 100, "Insufficient reputation");
        _;
    }
    
    function createProfile(string memory ipfsMetadata) external {
        require(bytes(_profiles[msg.sender].ipfsMetadata).length == 0, "Profile exists");
        
        _profiles[msg.sender] = SocialProfile({
            ipfsMetadata: ipfsMetadata,
            reputation: 100,
            followers: 0,
            following: 0,
            postCount: Counters.Counter(0),
            privacyLevel: 1
        });
    }
    
    function createCommunity(
        string memory name,
        string memory rulesIpfs
    ) external onlyVerified {
        require(_profiles[msg.sender].reputation >= MIN_REPUTATION_CREATE_COMMUNITY, 
            "Reputation too low");
            
        uint256 newId = _communityId.current();
        communities[newId] = Community({
            creator: msg.sender,
            name: name,
            memberCount: 1,
            created: block.timestamp,
            rulesIpfsHash: rulesIpfs
        });
        
        communities[newId].members[msg.sender] = true;
        _communityId.increment();
        
        emit CommunityCreated(newId, msg.sender);
    }
    
    function flagContent(bytes32 contentHash) external onlyVerified {
        require(!_contentModerated[contentHash], "Already flagged");
        
        _contentModerated[contentHash] = true;
        _profiles[msg.sender].reputation += 10;
        
        emit ContentFlagged(contentHash, msg.sender);
    }
    
    function addAchievement(
        address user,
        string memory achievementIpfs,
        uint256 nftTokenId
    ) external onlyOwner {
        require(_nftBadges[user][nftTokenId] == false, "Achievement exists");
        
        uint256 index = _profiles[user].postCount.current();
        _profiles[user].achievements[index] = achievementIpfs;
        _profiles[user].postCount.increment();
        _nftBadges[user][nftTokenId] = true;
    }
    
    function getAchievement(address user, uint256 index) 
        external 
        view 
        returns (string memory) 
    {
        return _profiles[user].achievements[index];
    }
    
    function updatePrivacy(uint8 level) external {
        require(level <= 3, "Invalid privacy level");
        _profiles[msg.sender].privacyLevel = level;
    }
}