// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// DAO USERS CONTRACT
contract DAOUsers is Ownable {
    using Counters for Counters.Counter;
    
    struct User {
        string name;
        uint8 status; // 0 - active, 1 - banned, 2 - bot, 3 - scam
        address referrer;
        uint256 registered;
        uint256 karma;
        uint8 rating;
        uint8 level;
        uint256 premiumEnd;
        uint256 verificationCount;
        Counters.Counter activeInvites;
    }
    
    mapping(address => User) public users;
    mapping(address => mapping(address => bool)) public verifications;
    mapping(bytes32 => bool) private _usedNames;
    
    address public immutable founder;
    uint256 public constant MAX_ACTIVE_INVITES = 10;
    
    event UserRegistered(address indexed user, address indexed referrer);
    event UserVerified(address indexed user, address indexed verifier);
    
    constructor() {
        founder = msg.sender;
    }
    
    modifier onlyVerifiedUser() {
        require(
            users[msg.sender].verificationCount >= 3 || 
            (users[msg.sender].verificationCount >= 1 && verifications[msg.sender][founder]),
            "Not verified"
        );
        _;
    }
    
    function register(
        address referrer,
        string memory username,
        string memory ipfsHash
    ) external {
        require(users[msg.sender].registered == 0, "Already registered");
        require(_usedNames[keccak256(bytes(username))] == false, "Username taken");
        require(_isValidReferrer(referrer), "Invalid referrer");
        
        _usedNames[keccak256(bytes(username))] = true;
        
        users[msg.sender] = User({
            name: username,
            status: 0,
            referrer: referrer,
            registered: block.timestamp,
            karma: 100,
            rating: 5,
            level: 0,
            premiumEnd: block.timestamp + 7 days,
            verificationCount: 0,
            activeInvites: Counters.Counter(0)
        });
        
        users[referrer].activeInvites.increment();
        emit UserRegistered(msg.sender, referrer);
    }
    
    function verifyUser(address user) external onlyVerifiedUser {
        require(user != msg.sender, "Cannot self-verify");
        require(!verifications[user][msg.sender], "Already verified");
        require(users[user].status == 0, "User not active");
        
        verifications[user][msg.sender] = true;
        users[user].verificationCount += 1;
        
        emit UserVerified(user, msg.sender);
    }
    
    function _isValidReferrer(address referrer) private view returns (bool) {
        return users[referrer].karma >= 100 && 
               users[referrer].status == 0 && 
               users[referrer].activeInvites.current() < MAX_ACTIVE_INVITES;
    }
}