// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";

contract FutureFond is Ownable, ReentrancyGuard, Pausable {
    // Константы
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000_000 * 10**18; // 1 триллион GVT
    uint256 public constant DAO_BORN_AMOUNT = 333_000_000_000 * 10**18; // 333 миллиарда GVT
    uint256 public constant DAO_CHILDREN_AMOUNT = 333_000_000_000 * 10**18; // 333 миллиарда GVT
    uint256 public constant DAO_FUTURE_AMOUNT = 333_000_000_000 * 10**18; // 333 миллиарда GVT
    uint256 public constant DAO_INSURANCE_AMOUNT = 1_000_000_000 * 10**18; // 1 миллиард GVT

    // Временные константы (в секундах)
    uint256 public constant DAO_BORN_START = 1735689600; // 2025-01-01
    uint256 public constant DAO_BORN_END = 2398291200;   // 2045-12-31
    uint256 public constant DAO_CHILDREN_START = 2398291200; // 2045-12-31
    uint256 public constant DAO_CHILDREN_END = 3060892800;   // 2065-12-31
    uint256 public constant DAO_FUTURE_START = 3723494400; // 2085-01-01
    uint256 public constant DAO_FUTURE_END = 32503680000;  // 3005-12-31

    // Структуры
    struct TimeLockedFund {
        string name;
        uint256 amount;
        uint256 startTime;
        uint256 endTime;
        bool isInitialized;
        bool isReleased;
    }

    // Состояние
    IERC20 public gvtToken;
    address public daoFinance;
    address public daoInsurance;

    mapping(string => TimeLockedFund) public funds;
    bool public isInitialized;

    // События
    event FundInitialized(string indexed fundName, uint256 amount, uint256 startTime, uint256 endTime);
    event FundReleased(string indexed fundName, uint256 amount);
    event TokensTransferred(string indexed fundName, address indexed to, uint256 amount);

    // Модификаторы
    modifier onlyDAOFinance() {
        require(msg.sender == daoFinance, "Only DAO Finance");
        _;
    }

    modifier onlyDAOInsurance() {
        require(msg.sender == daoInsurance, "Only DAO Insurance");
        _;
    }

    modifier onlyUninitialized() {
        require(!isInitialized, "Already initialized");
        _;
    }

    // Конструктор
    constructor(
        address _gvtToken,
        address _daoFinance,
        address _daoInsurance
    ) Ownable(msg.sender) {
        gvtToken = IERC20(_gvtToken);
        daoFinance = _daoFinance;
        daoInsurance = _daoInsurance;
    }

    // Основные функции
    function initialize() external onlyOwner onlyUninitialized {
        require(gvtToken.transferFrom(msg.sender, address(this), TOTAL_SUPPLY), "Transfer failed");

        // Инициализация DAO BORN
        funds["DAO_BORN"] = TimeLockedFund({
            name: "DAO BORN",
            amount: DAO_BORN_AMOUNT,
            startTime: DAO_BORN_START,
            endTime: DAO_BORN_END,
            isInitialized: true,
            isReleased: false
        });

        // Инициализация DAO CHILDREN
        funds["DAO_CHILDREN"] = TimeLockedFund({
            name: "DAO CHILDREN",
            amount: DAO_CHILDREN_AMOUNT,
            startTime: DAO_CHILDREN_START,
            endTime: DAO_CHILDREN_END,
            isInitialized: true,
            isReleased: false
        });

        // Инициализация DAO FUTURE
        funds["DAO_FUTURE"] = TimeLockedFund({
            name: "DAO FUTURE",
            amount: DAO_FUTURE_AMOUNT,
            startTime: DAO_FUTURE_START,
            endTime: DAO_FUTURE_END,
            isInitialized: true,
            isReleased: false
        });

        // Инициализация DAO INSURANCE
        funds["DAO_INSURANCE"] = TimeLockedFund({
            name: "DAO INSURANCE",
            amount: DAO_INSURANCE_AMOUNT,
            startTime: block.timestamp,
            endTime: type(uint256).max,
            isInitialized: true,
            isReleased: false
        });

        isInitialized = true;

        emit FundInitialized("DAO_BORN", DAO_BORN_AMOUNT, DAO_BORN_START, DAO_BORN_END);
        emit FundInitialized("DAO_CHILDREN", DAO_CHILDREN_AMOUNT, DAO_CHILDREN_START, DAO_CHILDREN_END);
        emit FundInitialized("DAO_FUTURE", DAO_FUTURE_AMOUNT, DAO_FUTURE_START, DAO_FUTURE_END);
        emit FundInitialized("DAO_INSURANCE", DAO_INSURANCE_AMOUNT, block.timestamp, type(uint256).max);
    }

    function releaseFund(string memory fundName) external onlyDAOFinance {
        TimeLockedFund storage fund = funds[fundName];
        require(fund.isInitialized, "Fund not initialized");
        require(!fund.isReleased, "Fund already released");
        require(block.timestamp >= fund.startTime, "Release time not reached");
        require(block.timestamp <= fund.endTime, "Release period ended");

        fund.isReleased = true;
        emit FundReleased(fundName, fund.amount);
    }

    function transferToDAOFinance(string memory fundName) external onlyDAOFinance {
        TimeLockedFund storage fund = funds[fundName];
        require(fund.isInitialized, "Fund not initialized");
        require(fund.isReleased, "Fund not released");
        require(block.timestamp >= fund.startTime, "Release time not reached");
        require(block.timestamp <= fund.endTime, "Release period ended");

        uint256 amount = fund.amount;
        fund.amount = 0;
        require(gvtToken.transfer(daoFinance, amount), "Transfer failed");
        emit TokensTransferred(fundName, daoFinance, amount);
    }

    function transferToDAOInsurance(uint256 amount) external onlyDAOInsurance {
        TimeLockedFund storage fund = funds["DAO_INSURANCE"];
        require(fund.isInitialized, "Insurance fund not initialized");
        require(amount <= fund.amount, "Insufficient insurance funds");

        fund.amount -= amount;
        require(gvtToken.transfer(daoInsurance, amount), "Transfer failed");
        emit TokensTransferred("DAO_INSURANCE", daoInsurance, amount);
    }

    // Вспомогательные функции
    function getFundInfo(string memory fundName) external view returns (
        string memory name,
        uint256 amount,
        uint256 startTime,
        uint256 endTime,
        bool isInitialized,
        bool isReleased
    ) {
        TimeLockedFund storage fund = funds[fundName];
        return (
            fund.name,
            fund.amount,
            fund.startTime,
            fund.endTime,
            fund.isInitialized,
            fund.isReleased
        );
    }

    function getTimeUntilRelease(string memory fundName) external view returns (uint256) {
        TimeLockedFund storage fund = funds[fundName];
        if (block.timestamp >= fund.startTime) {
            return 0;
        }
        return fund.startTime - block.timestamp;
    }

    function getTimeUntilEnd(string memory fundName) external view returns (uint256) {
        TimeLockedFund storage fund = funds[fundName];
        if (block.timestamp >= fund.endTime) {
            return 0;
        }
        return fund.endTime - block.timestamp;
    }
} 