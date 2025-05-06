// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DAOContracts.sol";
import "./Users.sol";
import "./People.sol";
import "./UserFiles.sol";
import "./Partners.sol";
import "./BonusContracts.sol";
import "./Invest.sol";
import "./P2P.sol";
import "./Marketplace.sol";
import "./Changer.sol";
import "./Executor.sol";

contract DAOFoundation is Ownable, ReentrancyGuard, Pausable {
    // Структуры
    struct ContractDeployment {
        address contractAddress;
        string name;
        uint256 deployedAt;
        bool isActive;
    }

    // Состояние
    address public immutable founder;
    address public gvtToken;
    DAOContracts public daoContracts;
    
    mapping(string => ContractDeployment) public deployments;
    string[] public deployedContracts;
    
    uint256 public constant MIN_INITIAL_SUPPLY = 1000000 * 10**18; // 1M GVT
    uint256 public constant MAX_INITIAL_SUPPLY = 1000000000 * 10**18; // 1B GVT
    
    // События
    event ContractDeployed(string indexed name, address indexed contractAddress);
    event ContractUpdated(string indexed name, address indexed newAddress);
    event ContractDeactivated(string indexed name);
    event GVTTokenSet(address indexed token);
    
    // Модификаторы
    modifier onlyFounder() {
        require(msg.sender == founder, "Only founder");
        _;
    }
    
    modifier onlyActiveContract(string memory name) {
        require(deployments[name].isActive, "Contract not active");
        _;
    }
    
    // Конструктор
    constructor(address _founder) Ownable(_founder) {
        founder = _founder;
    }
    
    // Основные функции
    function deployContracts(
        address _gvtToken,
        string memory daoName,
        string memory daoDescription,
        string memory ipfsMetadata
    ) external onlyFounder nonReentrant whenNotPaused {
        require(_gvtToken != address(0), "Invalid GVT token");
        require(IERC20(_gvtToken).totalSupply() >= MIN_INITIAL_SUPPLY, "Insufficient supply");
        require(IERC20(_gvtToken).totalSupply() <= MAX_INITIAL_SUPPLY, "Excessive supply");
        
        gvtToken = _gvtToken;
        
        // Деплоим DAOContracts первым, так как он нужен для других контрактов
        daoContracts = new DAOContracts();
        _registerContract("DAO_CONTRACTS", address(daoContracts));
        
        // Деплоим основные контракты
        DAOUsers users = new DAOUsers();
        _registerContract("DAO_USERS", address(users));
        
        DAOPeople people = new DAOPeople();
        _registerContract("DAO_PEOPLE", address(people));
        
        DAOUserFiles userFiles = new DAOUserFiles();
        _registerContract("DAO_USER_FILES", address(userFiles));
        
        Partners partners = new Partners(gvtToken, address(daoContracts), address(users));
        _registerContract("DAO_PARTNERS", address(partners));
        
        BonusContracts bonusContracts = new BonusContracts(gvtToken, address(daoContracts), address(users));
        _registerContract("DAO_BONUS_CONTRACTS", address(bonusContracts));
        
        Invest invest = new Invest(gvtToken, address(daoContracts));
        _registerContract("DAO_INVEST", address(invest));
        
        P2P p2p = new P2P(gvtToken, address(daoContracts), address(users));
        _registerContract("DAO_P2P", address(p2p));
        
        Marketplace marketplace = new Marketplace(gvtToken, address(daoContracts), address(users));
        _registerContract("DAO_MARKETPLACE", address(marketplace));
        
        Changer changer = new Changer(address(daoContracts));
        _registerContract("DAO_CHANGER", address(changer));
        
        Executor executor = new Executor(address(daoContracts), address(changer));
        _registerContract("DAO_EXECUTOR", address(executor));
        
        // Регистрируем все контракты в DAOContracts
        daoContracts.addContract("DAO_USERS", address(users), ipfsMetadata);
        daoContracts.addContract("DAO_PEOPLE", address(people), ipfsMetadata);
        daoContracts.addContract("DAO_USER_FILES", address(userFiles), ipfsMetadata);
        daoContracts.addContract("DAO_PARTNERS", address(partners), ipfsMetadata);
        daoContracts.addContract("DAO_BONUS_CONTRACTS", address(bonusContracts), ipfsMetadata);
        daoContracts.addContract("DAO_INVEST", address(invest), ipfsMetadata);
        daoContracts.addContract("DAO_P2P", address(p2p), ipfsMetadata);
        daoContracts.addContract("DAO_MARKETPLACE", address(marketplace), ipfsMetadata);
        daoContracts.addContract("DAO_CHANGER", address(changer), ipfsMetadata);
        daoContracts.addContract("DAO_EXECUTOR", address(executor), ipfsMetadata);
        
        // Инициализируем связи между контрактами
        users.updateContracts(address(daoContracts));
        people.updateContracts(address(daoContracts));
        userFiles.updateContracts(address(daoContracts));
        partners.updateContracts(gvtToken, address(daoContracts), address(users));
        bonusContracts.updateContracts(gvtToken, address(daoContracts), address(users));
        invest.updateContracts(gvtToken, address(daoContracts));
        p2p.updateContracts(gvtToken, address(daoContracts), address(users));
        marketplace.updateContracts(gvtToken, address(daoContracts), address(users));
        changer.updateContracts(address(daoContracts));
        executor.updateContracts(address(daoContracts), address(changer));
    }
    
    // Административные функции
    function _registerContract(string memory name, address contractAddress) internal {
        require(contractAddress != address(0), "Invalid address");
        require(deployments[name].contractAddress == address(0), "Contract already exists");
        
        deployments[name] = ContractDeployment({
            contractAddress: contractAddress,
            name: name,
            deployedAt: block.timestamp,
            isActive: true
        });
        
        deployedContracts.push(name);
        emit ContractDeployed(name, contractAddress);
    }
    
    function updateContract(
        string memory name,
        address newAddress
    ) external onlyFounder nonReentrant whenNotPaused {
        require(newAddress != address(0), "Invalid address");
        require(deployments[name].isActive, "Contract not active");
        
        deployments[name].contractAddress = newAddress;
        emit ContractUpdated(name, newAddress);
    }
    
    function deactivateContract(string memory name) external onlyFounder {
        require(deployments[name].isActive, "Contract not active");
        deployments[name].isActive = false;
        emit ContractDeactivated(name);
    }
    
    function pause() external onlyFounder {
        _pause();
    }
    
    function unpause() external onlyFounder {
        _unpause();
    }
    
    // Вспомогательные функции
    function getDeployedContracts() external view returns (string[] memory) {
        return deployedContracts;
    }
    
    function getContractAddress(string memory name) external view returns (address) {
        return deployments[name].contractAddress;
    }
    
    function isContractActive(string memory name) external view returns (bool) {
        return deployments[name].isActive;
    }
    
    function getDeploymentInfo(string memory name) external view returns (
        address contractAddress,
        string memory contractName,
        uint256 deployedAt,
        bool isActive
    ) {
        ContractDeployment storage deployment = deployments[name];
        return (
            deployment.contractAddress,
            deployment.name,
            deployment.deployedAt,
            deployment.isActive
        );
    }
} 