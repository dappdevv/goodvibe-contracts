// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

contract DAOUsers is Ownable {
    using Counters for Counters.Counter;

    enum Status { ACTIVE, BANNED, BOT, SCAM }

    struct User {
        string name;
        Status status;
        address referrer;
        uint256 registered;
        address userAddress;
        uint256 karma;
        uint8 rating;
        uint8 level;
        uint256 premium;
        uint256 verificationCount;
    }

    struct Invite {
        uint256 id;
        address inviter;
        address invitee;
        uint256 expiresAt;
        uint256 gasAmount;
        bool gasPaid;
        bool used;
    }

    mapping(address => User) public users;
    mapping(bytes32 => bool) private _usedNames;
    mapping(uint256 => Invite) public invites;
    mapping(address => uint256[]) public userInvites;
    Counters.Counter private _inviteIdCounter;

    address public immutable founder;
    uint256 public constant MAX_ACTIVE_INVITES = 10;
    uint256 public constant INVITE_EXPIRATION = 1 days;

    event UserRegistered(address indexed user, address indexed referrer, string name);
    event InviteCreated(uint256 indexed id, address indexed inviter, address indexed invitee, uint256 gasAmount);
    event InviteUsed(uint256 indexed id, address indexed invitee);

    modifier onlyVerified(address inviter) {
        require(users[inviter].karma >= 100, "Low karma");
        require(users[inviter].status == Status.ACTIVE, "Not active");
        require(users[inviter].verificationCount >= 3 || (inviter == founder && users[inviter].verificationCount >= 1), "Not enough verifications");
        _;
    }

    constructor() {
        founder = msg.sender;
    }

    function createInvite(address invitee, uint256 gasAmount) external onlyVerified(msg.sender) {
        require(invitee != address(0), "Zero address");
        require(users[msg.sender].status == Status.ACTIVE, "Not active");
        require(userInvites[msg.sender].length < MAX_ACTIVE_INVITES, "Too many invites");
        uint256 id = _inviteIdCounter.current();
        _inviteIdCounter.increment();
        invites[id] = Invite({
            id: id,
            inviter: msg.sender,
            invitee: invitee,
            expiresAt: block.timestamp + INVITE_EXPIRATION,
            gasAmount: gasAmount,
            gasPaid: gasAmount > 0,
            used: false
        });
        userInvites[msg.sender].push(id);
        emit InviteCreated(id, msg.sender, invitee, gasAmount);
    }

    function register(string memory username, uint256 inviteId) external {
        require(users[msg.sender].registered == 0, "Already registered");
        require(!_usedNames[keccak256(bytes(username))], "Username taken");
        Invite storage inv = invites[inviteId];
        require(inv.invitee == msg.sender, "Not your invite");
        require(!inv.used, "Invite used");
        require(block.timestamp <= inv.expiresAt, "Invite expired");
        _usedNames[keccak256(bytes(username))] = true;
        inv.used = true;
        users[msg.sender] = User({
            name: username,
            status: Status.ACTIVE,
            referrer: inv.inviter,
            registered: block.timestamp,
            userAddress: msg.sender,
            karma: 100,
            rating: 5,
            level: 0,
            premium: block.timestamp + 7 days,
            verificationCount: 0
        });
        if (inv.gasPaid && inv.gasAmount > 0) {
            payable(msg.sender).transfer(inv.gasAmount);
        }
        emit UserRegistered(msg.sender, inv.inviter, username);
        emit InviteUsed(inviteId, msg.sender);
    }

    // Функция для получения активных приглашений пользователя
    function getActiveInvites(address inviter) external view returns (uint256[] memory) {
        uint256[] memory all = userInvites[inviter];
        uint256 count;
        for (uint256 i = 0; i < all.length; i++) {
            if (!invites[all[i]].used && block.timestamp <= invites[all[i]].expiresAt) {
                count++;
            }
        }
        uint256[] memory active = new uint256[](count);
        uint256 idx;
        for (uint256 i = 0; i < all.length; i++) {
            if (!invites[all[i]].used && block.timestamp <= invites[all[i]].expiresAt) {
                active[idx++] = all[i];
            }
        }
        return active;
    }

    // Функция для пополнения баланса для оплаты газа приглашения
    receive() external payable {}
}