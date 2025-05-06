// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

// DAO USER FILES CONTRACT
contract DAOUserFiles {
    using Counters for Counters.Counter;
    
    struct File {
        string ipfsHash;
        string encryptedKey;
        uint256 size;
        uint256 price;
        uint256 expiry;
    }
    
    mapping(address => mapping(uint256 => File)) public userFiles;
    mapping(address => Counters.Counter) private _fileCounters;
    
    uint256 public constant BASE_STORAGE = 100 * 1024 * 1024; // 100MB
    uint256 public storagePricePerMB = 0.001 ether;
    
    event FileUploaded(address indexed user, uint256 fileId, string ipfsHash);
    event StorageExtended(address indexed user, uint256 newSize);
    
    function uploadFile(
        string memory ipfsHash,
        string memory encryptedKey,
        uint256 size
    ) external {
        uint256 fileId = _fileCounters[msg.sender].current();
        userFiles[msg.sender][fileId] = File({
            ipfsHash: ipfsHash,
            encryptedKey: encryptedKey,
            size: size,
            price: 0,
            expiry: 0
        });
        _fileCounters[msg.sender].increment();
        
        emit FileUploaded(msg.sender, fileId, ipfsHash);
    }
    
    function extendStorage(uint256 additionalMB) external payable {
        require(msg.value >= additionalMB * storagePricePerMB, "Insufficient funds");
        
        // Логика расширения хранилища
        emit StorageExtended(msg.sender, additionalMB);
    }
    
    function calculateStorageCost(address user) public view returns (uint256) {
        uint256 usedSpace = _calculateUsedSpace(user);
        if(usedSpace <= BASE_STORAGE) return 0;
        
        uint256 extraMB = (usedSpace - BASE_STORAGE) / (1024 * 1024);
        return extraMB * storagePricePerMB;
    }
    
    function _calculateUsedSpace(address user) private view returns (uint256) {
        uint256 totalSize;
        for(uint256 i = 0; i < _fileCounters[user].current(); i++) {
            totalSize += userFiles[user][i].size;
        }
        return totalSize;
    }
}