// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";

contract DAOPartners is Ownable {
    address public daoTreasury;

    uint256 public premiumPrice = 1100 ether; // 1100 ETH (или другой нативный токен, зависит от сети)
    uint256 public daoCommission = 1000; // 10% (10000 = 100%)
    uint256 public constant COMMISSION_DENOMINATOR = 10000;
    uint256 public constant MAX_PREMIUM_MONTHS = 6;
    uint256 public constant PREMIUM_DURATION = 30 days;

    // Маркетинг-план: проценты по уровням (10000 = 100%)
    uint256[] public refPercents = [3000, 2000, 1000, 500, 500, 500, 500, 2000];
    uint8 public constant LEVELS = 8;

    struct Partner {
        address user;
        address referrer;
        uint256 premium;
    }
    mapping(address => Partner) public partners;

    // Верификация
    enum VerificationStatus { NONE, AWAITING, VERIFIED, REJECTED }
    struct VerificationRequest {
        uint256 id;
        address verifiable;
        address verificator;
        string fioHash; // зашифрованная строка ФИО
        string fioPlain; // ФИО для сравнения (можно убрать после верификации)
        string selfie;
        string key;
        VerificationStatus status;
    }
    mapping(uint256 => VerificationRequest) public verifications;
    mapping(address => uint256[]) public userVerifications;
    uint256 public verificationCounter;

    event PremiumPaid(address indexed user, uint256 months, uint256 amount, uint256 timestamp);
    event VerificationStarted(uint256 indexed id, address indexed verifiable, address indexed verificator);
    event Verified(uint256 indexed id, address indexed verifiable, address indexed verificator);
    event VerificationRejected(uint256 indexed id);
    event Withdraw(address indexed to, uint256 amount);
    event ParamsChanged(uint256 premiumPrice, uint256 daoCommission);

    constructor(address _daoTreasury) {
        require(_daoTreasury != address(0), "Zero address");
        daoTreasury = _daoTreasury;
    }

    function setPremiumPrice(uint256 price) external onlyOwner {
        premiumPrice = price;
        emit ParamsChanged(premiumPrice, daoCommission);
    }
    function setDAOCommission(uint256 commission) external onlyOwner {
        require(commission <= COMMISSION_DENOMINATOR, "Too high");
        daoCommission = commission;
        emit ParamsChanged(premiumPrice, daoCommission);
    }
    function setTreasury(address treasury) external onlyOwner {
        require(treasury != address(0), "Zero address");
        daoTreasury = treasury;
    }
    function withdraw(address payable to, uint256 amount) external onlyOwner {
        require(to != address(0), "Zero address");
        require(address(this).balance >= amount, "Insufficient balance");
        to.transfer(amount);
        emit Withdraw(to, amount);
    }

    // Оплата премиума и распределение по реферальной цепочке
    function payPremium(uint8 months) external payable {
        require(months > 0 && months <= MAX_PREMIUM_MONTHS, "Invalid months");
        uint256 amount = premiumPrice * months;
        require(msg.value >= amount, "Insufficient payment");
        uint256 commission = (amount * daoCommission) / COMMISSION_DENOMINATOR;
        if (commission > 0) {
            payable(daoTreasury).transfer(commission);
        }
        uint256 toDistribute = amount - commission;
        address current = partners[msg.sender].referrer;
        for (uint8 i = 0; i < LEVELS; i++) {
            uint256 reward = (amount * refPercents[i]) / COMMISSION_DENOMINATOR;
            if (current != address(0) && partners[current].premium >= block.timestamp) {
                payable(current).transfer(reward);
                toDistribute -= reward;
                current = partners[current].referrer;
            } else {
                // если нет премиума — средства остаются на контракте
                current = current == address(0) ? address(0) : partners[current].referrer;
            }
        }
        // Обновляем премиум
        if (partners[msg.sender].premium < block.timestamp) {
            partners[msg.sender].premium = block.timestamp + PREMIUM_DURATION * months;
        } else {
            partners[msg.sender].premium += PREMIUM_DURATION * months;
        }
        // Возврат излишка
        if (msg.value > amount) {
            payable(msg.sender).transfer(msg.value - amount);
        }
        emit PremiumPaid(msg.sender, months, amount, block.timestamp);
    }

    // Верификация пользователя
    function startVerification(
        string memory fioPlain,
        address verificator,
        string memory selfie,
        string memory key,
        string memory fioHash
    ) external {
        require(verificator != address(0), "Zero verificator");
        uint256 id = verificationCounter++;
        verifications[id] = VerificationRequest({
            id: id,
            verifiable: msg.sender,
            verificator: verificator,
            fioHash: fioHash,
            fioPlain: fioPlain,
            selfie: selfie,
            key: key,
            status: VerificationStatus.AWAITING
        });
        userVerifications[msg.sender].push(id);
        userVerifications[verificator].push(id);
        emit VerificationStarted(id, msg.sender, verificator);
    }

    function getAwaitingVerifications(address user) external view returns (uint256[] memory) {
        uint256[] memory all = userVerifications[user];
        uint256 count;
        for (uint256 i = 0; i < all.length; i++) {
            if (verifications[all[i]].status == VerificationStatus.AWAITING) {
                count++;
            }
        }
        uint256[] memory awaiting = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < all.length; i++) {
            if (verifications[all[i]].status == VerificationStatus.AWAITING) {
                awaiting[idx++] = all[i];
            }
        }
        return awaiting;
    }

    function verify(uint256 id, string memory fioPlain) external {
        VerificationRequest storage req = verifications[id];
        require(req.verificator == msg.sender, "Not your request");
        require(req.status == VerificationStatus.AWAITING, "Not awaiting");
        // Проверка совпадения ФИО (дешифрование вне контракта, сравнение plain)
        require(keccak256(bytes(req.fioPlain)) == keccak256(bytes(fioPlain)), "FIO mismatch");
        req.status = VerificationStatus.VERIFIED;
        emit Verified(id, req.verifiable, msg.sender);
    }

    function rejectVerification(uint256 id) external {
        VerificationRequest storage req = verifications[id];
        require(req.verificator == msg.sender, "Not your request");
        require(req.status == VerificationStatus.AWAITING, "Not awaiting");
        req.status = VerificationStatus.REJECTED;
        emit VerificationRejected(id);
    }

    // Регистрация партнёра (вызывается при регистрации пользователя)
    function registerPartner(address user, address referrer) external onlyOwner {
        require(user != address(0), "Zero user");
        partners[user] = Partner({user: user, referrer: referrer, premium: 0});
    }

    // Приём ETH
    receive() external payable {}
}
