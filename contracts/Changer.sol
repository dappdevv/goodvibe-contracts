// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";

contract Changer is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct Change {
        uint256 changeId;
        string targetContract;
        bytes changeData;
        string ipfsDescription;
        uint256 createdAt;
        uint256 auditDeadline;
        bool isAudited;
        bool isApproved;
        bool isExecuted;
        address auditor;
        string auditResult;
    }

    // Состояние
    DAOContracts public daoContracts;
    mapping(uint256 => Change) public changes;
    uint256 private _changeCounter;
    
    uint256 public constant AUDIT_PERIOD = 7 days;
    uint256 public constant EXECUTION_PERIOD = 3 days;
    
    // События
    event ChangeProposed(uint256 indexed changeId, string indexed targetContract);
    event ChangeAudited(uint256 indexed changeId, bool approved);
    event ChangeExecuted(uint256 indexed changeId);
    event ChangeExpired(uint256 indexed changeId);
    
    // Модификаторы
    modifier onlyAuditor() {
        require(daoContracts.getContractAddress("DAO_DEVELOPERS") == msg.sender, "Only auditor");
        _;
    }
    
    modifier onlyExecutor() {
        require(daoContracts.getContractAddress("EXECUTOR") == msg.sender, "Only executor");
        _;
    }
    
    // Конструктор
    constructor(address _daoContracts) Ownable(msg.sender) {
        daoContracts = DAOContracts(_daoContracts);
    }
    
    // Основные функции
    function proposeChange(
        string memory targetContract,
        bytes memory changeData,
        string memory ipfsDescription
    ) external whenNotPaused {
        require(daoContracts.getContractAddress(targetContract) != address(0), "Invalid target");
        
        uint256 changeId = _changeCounter++;
        changes[changeId] = Change({
            changeId: changeId,
            targetContract: targetContract,
            changeData: changeData,
            ipfsDescription: ipfsDescription,
            createdAt: block.timestamp,
            auditDeadline: block.timestamp + AUDIT_PERIOD,
            isAudited: false,
            isApproved: false,
            isExecuted: false,
            auditor: address(0),
            auditResult: ""
        });
        
        emit ChangeProposed(changeId, targetContract);
    }
    
    function auditChange(
        uint256 changeId,
        bool approved,
        string memory auditResult
    ) external onlyAuditor {
        Change storage change = changes[changeId];
        require(!change.isAudited, "Already audited");
        require(block.timestamp <= change.auditDeadline, "Audit period expired");
        
        change.isAudited = true;
        change.isApproved = approved;
        change.auditor = msg.sender;
        change.auditResult = auditResult;
        
        emit ChangeAudited(changeId, approved);
    }
    
    function executeChange(uint256 changeId) external onlyExecutor nonReentrant {
        Change storage change = changes[changeId];
        require(change.isAudited, "Not audited");
        require(change.isApproved, "Not approved");
        require(!change.isExecuted, "Already executed");
        require(block.timestamp <= change.auditDeadline + EXECUTION_PERIOD, "Execution period expired");
        
        change.isExecuted = true;
        
        // Здесь будет логика применения изменений
        // Это должно быть реализовано в Executor.sol
        
        emit ChangeExecuted(changeId);
    }
    
    // Вспомогательные функции
    function getChangeDetails(uint256 changeId) external view returns (
        uint256 id,
        string memory targetContract,
        bytes memory changeData,
        string memory ipfsDescription,
        uint256 createdAt,
        uint256 auditDeadline,
        bool isAudited,
        bool isApproved,
        bool isExecuted,
        address auditor,
        string memory auditResult
    ) {
        Change storage change = changes[changeId];
        return (
            change.changeId,
            change.targetContract,
            change.changeData,
            change.ipfsDescription,
            change.createdAt,
            change.auditDeadline,
            change.isAudited,
            change.isApproved,
            change.isExecuted,
            change.auditor,
            change.auditResult
        );
    }
    
    function getPendingChanges() external view returns (uint256[] memory) {
        uint256 count = 0;
        for(uint256 i = 0; i < _changeCounter; i++) {
            if(!changes[i].isAudited) {
                count++;
            }
        }
        
        uint256[] memory pendingChanges = new uint256[](count);
        uint256 index = 0;
        
        for(uint256 i = 0; i < _changeCounter; i++) {
            if(!changes[i].isAudited) {
                pendingChanges[index] = i;
                index++;
            }
        }
        
        return pendingChanges;
    }
    
    // Административные функции
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function updateDAOContracts(address _daoContracts) external onlyOwner {
        daoContracts = DAOContracts(_daoContracts);
    }
} 