// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "./Users.sol";
import "./Partners.sol";
import "./GoodVibeNFT.sol";

contract GoodVibeNFTAirdrop is Ownable {
    using Counters for Counters.Counter;
    Counters.Counter private _airdropMinted;
    Counters.Counter private _bonusMinted;

    DAOUsers public usersContract;
    DAOPartners public partnersContract;
    GoodVibeNFT public nftContract;

    mapping(address => bool) public hasMintedAirdrop;
    mapping(address => uint256) public availableBonusNFT;
    mapping(address => uint256) public bonusMinted;

    event NFTAirdropMinted(address indexed user, uint256 tokenId);
    event BonusNFTGranted(address indexed referrer, uint256 amount);
    event BonusNFTMinted(address indexed referrer, uint256 tokenId);

    constructor(address _users, address _partners, address _nft) Ownable(msg.sender) {
        require(_users != address(0) && _partners != address(0) && _nft != address(0), "Zero address");
        usersContract = DAOUsers(_users);
        partnersContract = DAOPartners(_partners);
        nftContract = GoodVibeNFT(_nft);
    }

    /// @notice Чеканка NFT для пользователя, соответствующего условиям
    function mintAirdropNFT(int32 lng, int32 lat) external {
        require(!hasMintedAirdrop[msg.sender], "Already minted");
        DAOUsers.User memory user = usersContract.users(msg.sender);
        require(user.registered > 0, "Not registered in DAO");
        require(user.userAddress == msg.sender, "Invalid user");
        require(user.name[0] != 0, "No username");
        // Проверка верификаций и премиума через DAOPartners
        require(partnersContract.getVerificationCount(msg.sender) >= 3, "Need 3 verifications");
        require(partnersContract.hasActivePremium(msg.sender), "No active premium");
        // Чеканим NFT через основной контракт
        uint256 tokenId = nftContract.getTokenId(lng, lat);
        require(!nftContract.exists(tokenId), "Token exists");
        nftContract.mint(msg.sender, lng, lat);
        hasMintedAirdrop[msg.sender] = true;
        _airdropMinted.increment();
        // Начисляем бонусный NFT рефереру
        address referrer = user.referrer;
        if (referrer != address(0)) {
            availableBonusNFT[referrer]++;
            emit BonusNFTGranted(referrer, availableBonusNFT[referrer]);
        }
        emit NFTAirdropMinted(msg.sender, tokenId);
    }

    /// @notice Чеканка бонусного NFT для реферера
    function mintBonusNFT(int32 lng, int32 lat) external {
        require(availableBonusNFT[msg.sender] > 0, "No bonus NFT");
        uint256 tokenId = nftContract.getTokenId(lng, lat);
        require(!nftContract.exists(tokenId), "Token exists");
        nftContract.mint(msg.sender, lng, lat);
        availableBonusNFT[msg.sender]--;
        bonusMinted[msg.sender]++;
        _bonusMinted.increment();
        emit BonusNFTMinted(msg.sender, tokenId);
    }

    // Вспомогательные функции для статистики
    function totalAirdropMinted() external view returns (uint256) {
        return _airdropMinted.current();
    }
    function totalBonusMinted() external view returns (uint256) {
        return _bonusMinted.current();
    }
}
