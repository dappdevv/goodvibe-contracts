// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "./DAOContracts.sol";
import "./Changer.sol";

contract Executor is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct Execution {
        uint256 executionId;
        uint256 changeId;
        address targetContract;
        bytes changeData;
        uint256 executedAt;
        bool success;
        string errorMessage;
    }

    // Состояние
    DAOContracts public daoContracts;
    Changer public changer;
    mapping(uint256 => Execution) public executions;
    uint256 private _executionCounter;
    
    // События
    event ExecutionStarted(uint256 indexed executionId, uint256 indexed changeId);
    event ExecutionCompleted(uint256 indexed executionId, bool success);
    event ExecutionFailed(uint256 indexed executionId, string errorMessage);
    
    // Модификаторы
    modifier onlyChanger() {
        require(msg.sender == address(changer), "Only changer");
        _;
    }
    
    // Конструктор
    constructor(
        address _daoContracts,
        address _changer
    ) Ownable(msg.sender) {
        daoContracts = DAOContracts(_daoContracts);
        changer = Changer(_changer);
    }
    
    // Основные функции
    function executeChange(uint256 changeId) external onlyChanger nonReentrant whenNotPaused {
        (
            uint256 id,
            string memory targetContract,
            bytes memory changeData,
            ,
            ,
            ,
            ,
            ,
            ,
            ,
            
        ) = changer.getChangeDetails(changeId);
        
        address targetAddress = daoContracts.getContractAddress(targetContract);
        require(targetAddress != address(0), "Invalid target contract");
        
        uint256 executionId = _executionCounter++;
        executions[executionId] = Execution({
            executionId: executionId,
            changeId: changeId,
            targetContract: targetAddress,
            changeData: changeData,
            executedAt: block.timestamp,
            success: false,
            errorMessage: ""
        });
        
        emit ExecutionStarted(executionId, changeId);
        
        // Выполняем изменение
        (bool success, bytes memory result) = targetAddress.call(changeData);
        
        if (success) {
            executions[executionId].success = true;
            emit ExecutionCompleted(executionId, true);
        } else {
            string memory errorMessage = _getErrorMessage(result);
            executions[executionId].errorMessage = errorMessage;
            emit ExecutionFailed(executionId, errorMessage);
        }
    }
    
    // Вспомогательные функции
    function _getErrorMessage(bytes memory _data) internal pure returns (string memory) {
        if (_data.length < 68) return "Unknown error";
        
        assembly {
            let ptr := mload(0x40)
            let size := mload(_data)
            mstore(ptr, 0x20)
            mstore(ptr, size)
            let data := add(ptr, 0x20)
            calldatacopy(data, 36, size)
            return(ptr, add(size, 0x20))
        }
    }
    
    function getExecutionDetails(uint256 executionId) external view returns (
        uint256 id,
        uint256 changeId,
        address targetContract,
        bytes memory changeData,
        uint256 executedAt,
        bool success,
        string memory errorMessage
    ) {
        Execution storage execution = executions[executionId];
        return (
            execution.executionId,
            execution.changeId,
            execution.targetContract,
            execution.changeData,
            execution.executedAt,
            execution.success,
            execution.errorMessage
        );
    }
    
    // Административные функции
    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }
    
    function updateContracts(
        address _daoContracts,
        address _changer
    ) external onlyOwner {
        daoContracts = DAOContracts(_daoContracts);
        changer = Changer(_changer);
    }
} 