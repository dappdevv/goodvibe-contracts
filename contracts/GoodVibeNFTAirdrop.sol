// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./Users.sol";
import "./GoodVibeNFT.sol";

contract GoodVibeNFTAirdrop is ERC721, Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    struct Location {
        int256 latitude;
        int256 longitude;
        bool isOccupied;
    }

    struct User {
        uint256 verificationCount;
        address referrer;
        bool hasMinted;
    }

    mapping(uint256 => Location) public tokenLocations;
    mapping(address => User) public users;
    mapping(address => uint256) public availableBonusNFT;
    mapping(address => mapping(address => bool)) public hasVerified;

    event NFTMinted(address indexed to, uint256 tokenId, int256 latitude, int256 longitude);
    event UserVerified(address indexed verifier, address indexed verified);
    event BonusNFTAdded(address indexed referrer);

    DAOUsers public usersContract;
    GoodVibeNFT public nftContract;

    constructor(address _usersContract, address _nftContract) ERC721("GoodVibeNFT", "GVNFT") Ownable(msg.sender) {
        usersContract = DAOUsers(_usersContract);
        nftContract = GoodVibeNFT(_nftContract);
    }

    function verifyUser(address userToVerify) external {
        require(msg.sender != userToVerify, "Cannot verify yourself");
        require(!hasVerified[msg.sender][userToVerify], "Already verified this user");
        require(!users[userToVerify].hasMinted, "User already minted NFT");

        hasVerified[msg.sender][userToVerify] = true;
        users[userToVerify].verificationCount++;

        emit UserVerified(msg.sender, userToVerify);
    }

    function setReferrer(address referrer) external {
        require(users[msg.sender].referrer == address(0), "Referrer already set");
        require(referrer != msg.sender, "Cannot set yourself as referrer");
        require(referrer != address(0), "Invalid referrer address");

        users[msg.sender].referrer = referrer;
    }

    function mintNFT(int256 latitude, int256 longitude) external {
        require(usersContract.users(msg.sender).verificationCount >= 3, "Need 3 verifications to mint");
        require(!users[msg.sender].hasMinted, "Already minted NFT");
        require(!isLocationOccupied(latitude, longitude), "Location already occupied");

        _tokenIds.increment();
        uint256 newTokenId = _tokenIds.current();

        _safeMint(msg.sender, newTokenId);
        tokenLocations[newTokenId] = Location(latitude, longitude, true);
        users[msg.sender].hasMinted = true;

        // Add bonus NFT to referrer if exists
        if (users[msg.sender].referrer != address(0)) {
            availableBonusNFT[users[msg.sender].referrer]++;
            emit BonusNFTAdded(users[msg.sender].referrer);
        }

        emit NFTMinted(msg.sender, newTokenId, latitude, longitude);
    }

    function isLocationOccupied(int256 latitude, int256 longitude) public view returns (bool) {
        for (uint256 i = 1; i <= _tokenIds.current(); i++) {
            if (tokenLocations[i].latitude == latitude && 
                tokenLocations[i].longitude == longitude && 
                tokenLocations[i].isOccupied) {
                return true;
            }
        }
        return false;
    }

    function getVerificationCount(address user) external view returns (uint256) {
        return users[user].verificationCount;
    }

    function getTokenLocation(uint256 tokenId) external view returns (Location memory) {
        return tokenLocations[tokenId];
    }

    function getAvailableBonusNFT(address user) external view returns (uint256) {
        return availableBonusNFT[user];
    }
}
