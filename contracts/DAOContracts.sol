// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract DAOContracts is Ownable, Pausable {
    // Структуры
    struct ContractInfo {
        string name;
        address contractAddress;
        bool isActive;
        uint256 addedAt;
        string ipfsMetadata;
    }

    // Состояние
    mapping(string => ContractInfo) public contracts;
    string[] public contractNames;
    
    // События
    event ContractAdded(string indexed name, address indexed contractAddress);
    event ContractUpdated(string indexed name, address indexed newAddress);
    event ContractDeactivated(string indexed name);
    event ContractActivated(string indexed name);
    
    // Модификаторы
    modifier onlyActiveContract(string memory name) {
        require(contracts[name].isActive, "Contract not active");
        _;
    }
    
    // Конструктор
    constructor() Ownable(msg.sender) {}
    
    // Основные функции
    function addContract(
        string memory name,
        address contractAddress,
        string memory ipfsMetadata
    ) external onlyOwner {
        require(contracts[name].contractAddress == address(0), "Contract already exists");
        require(contractAddress != address(0), "Invalid address");
        
        contracts[name] = ContractInfo({
            name: name,
            contractAddress: contractAddress,
            isActive: true,
            addedAt: block.timestamp,
            ipfsMetadata: ipfsMetadata
        });
        
        contractNames.push(name);
        
        emit ContractAdded(name, contractAddress);
    }
    
    function updateContract(
        string memory name,
        address newAddress,
        string memory ipfsMetadata
    ) external onlyOwner onlyActiveContract(name) {
        require(newAddress != address(0), "Invalid address");
        
        contracts[name].contractAddress = newAddress;
        contracts[name].ipfsMetadata = ipfsMetadata;
        
        emit ContractUpdated(name, newAddress);
    }
    
    function deactivateContract(string memory name) external onlyOwner {
        require(contracts[name].isActive, "Contract already inactive");
        
        contracts[name].isActive = false;
        emit ContractDeactivated(name);
    }
    
    function activateContract(string memory name) external onlyOwner {
        require(!contracts[name].isActive, "Contract already active");
        
        contracts[name].isActive = true;
        emit ContractActivated(name);
    }
    
    // Вспомогательные функции
    function getContractAddress(string memory name) external view returns (address) {
        return contracts[name].contractAddress;
    }
    
    function getContractInfo(string memory name) external view returns (
        string memory contractName,
        address contractAddress,
        bool isActive,
        uint256 addedAt,
        string memory ipfsMetadata
    ) {
        ContractInfo memory info = contracts[name];
        return (
            info.name,
            info.contractAddress,
            info.isActive,
            info.addedAt,
            info.ipfsMetadata
        );
    }
    
    function getAllContracts() external view returns (
        string[] memory names,
        address[] memory addresses,
        bool[] memory activeStatus
    ) {
        uint256 length = contractNames.length;
        names = new string[](length);
        addresses = new address[](length);
        activeStatus = new bool[](length);
        
        for(uint256 i = 0; i < length; i++) {
            names[i] = contracts[contractNames[i]].name;
            addresses[i] = contracts[contractNames[i]].contractAddress;
            activeStatus[i] = contracts[contractNames[i]].isActive;
        }
        
        return (names, addresses, activeStatus);
    }
    
    // Административные функции
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
} 