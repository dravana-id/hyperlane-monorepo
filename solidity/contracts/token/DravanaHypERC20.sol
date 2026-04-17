// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

import "./libs/TypeCasts.sol";
import "./token/libs/TokenMessage.sol";

interface IDravanaSmartWalletFactory {
    function isDeployedAccount(address account) external view returns (bool);

    function isAllowedInboundWarpRecipient(address account) external view returns (bool);
}

/**
 * @title DravanaHypERC20
 * @notice Dev-local warp token aligned with Hyperlane fork `DravanaHypERC20` (HypERC20 base in monorepo):
 *         - `handle` body is Hyperlane TokenMessage (recipient bytes32 + amount), NOT a custom ABI tuple.
 *         - `messageId = keccak256(abi.encode(origin, sender, body))` matches fork / SDK encoding.
 *         Option 2: store on handle, mint only via `consumeAndMint`.
 * @dev Outbound: `transferRemote` burns from `msg.sender` (SmartWallet in production); no separate bridge adapter.
 */
contract DravanaHypERC20 is ERC20, Ownable, ReentrancyGuard {
    using TypeCasts for bytes32;
    using TokenMessage for bytes;

    struct PendingMessage {
        address recipient;
        uint256 amount;
        uint32 originDomain;
        bytes32 remoteSender;
        uint256 expiry;
        bool consumed;
    }

    address public immutable mailbox;

    mapping(bytes32 => PendingMessage) public messages;
    mapping(uint32 => uint256) public domainToChain;

    /// @notice Mirrors fork default; mint must be consumed before this deadline after arrival.
    uint256 public pendingMintTtl = 1 days;

    IDravanaSmartWalletFactory public smartWalletFactory;

    event SmartWalletFactorySet(address indexed factory);
    event PendingMintTtlSet(uint256 ttl);
    event MessageStored(
        bytes32 indexed messageId,
        address indexed recipient,
        uint256 amount,
        uint32 originDomain,
        bytes32 remoteSender,
        uint256 expiry
    );
    event MessageConsumed(bytes32 indexed messageId, address indexed recipient, uint256 amount);
    /// @dev Dev-only: no mailbox dispatch; production uses monorepo HypERC20 `transferRemote`.
    event TransferRemoteDev(uint32 indexed destination, bytes32 indexed recipient, uint256 amount, bytes32 messageId);

    constructor(string memory name_, string memory symbol_, address mailbox_, address initialOwner) ERC20(name_, symbol_) Ownable() {
        require(mailbox_ != address(0), "MAILBOX_ZERO");
        require(initialOwner != address(0), "OWNER_ZERO");
        _transferOwnership(initialOwner);
        mailbox = mailbox_;
    }

    function setSmartWalletFactory(address factory) external onlyOwner {
        require(factory != address(0), "FACTORY_ZERO");
        smartWalletFactory = IDravanaSmartWalletFactory(factory);
        emit SmartWalletFactorySet(factory);
    }

    function setDomain(uint32 domain, uint256 chainId) external onlyOwner {
        require(chainId != 0, "CHAIN_ZERO");
        domainToChain[domain] = chainId;
    }

    function setPendingMintTtl(uint256 ttl) external onlyOwner {
        require(ttl > 0, "ttl=0");
        pendingMintTtl = ttl;
        emit PendingMintTtlSet(ttl);
    }

    /**
     * @dev Mailbox entry — store only. Body MUST be Hyperlane TokenMessage (64 bytes).
     *      messageId = keccak256(abi.encode(origin, sender, body)) — same as Hyperlane fork contract.
     */
    function handle(uint32 origin, bytes32 sender, bytes calldata body) external payable {
        require(msg.sender == mailbox, "ONLY_MAILBOX");
        require(body.length == 64, "BAD_TOKEN_MSG");

        address recipient = body.recipient().bytes32ToAddress();
        uint256 rawAmount = body.amount();
        require(recipient != address(0), "INVALID_RECIPIENT");
        require(rawAmount > 0, "INVALID_AMOUNT");

        require(address(smartWalletFactory) != address(0), "FACTORY_UNSET");
        // Counterfactual AA wallets have no code until UserOp/init; factory gates deployed OR pre-registered CREATE2.
        require(smartWalletFactory.isAllowedInboundWarpRecipient(recipient), "RECIPIENT_NOT_SW");

        bytes32 messageId = keccak256(abi.encode(origin, sender, body));
        require(messages[messageId].recipient == address(0), "MESSAGE_EXISTS");

        uint256 expiry = block.timestamp + pendingMintTtl;
        messages[messageId] = PendingMessage({
            recipient: recipient,
            amount: rawAmount,
            originDomain: origin,
            remoteSender: sender,
            expiry: expiry,
            consumed: false
        });

        emit MessageStored(messageId, recipient, rawAmount, origin, sender, expiry);
    }

    function consumeAndMint(bytes32 messageId) external nonReentrant {
        PendingMessage storage m = messages[messageId];
        require(m.recipient != address(0), "MESSAGE_NOT_FOUND");
        require(!m.consumed, "ALREADY_CONSUMED");
        require(block.timestamp <= m.expiry, "EXPIRED");
        require(msg.sender == m.recipient, "INVALID_CALLER");
        require(m.amount > 0, "INVALID_MESSAGE");
        require(address(smartWalletFactory) != address(0), "FACTORY_UNSET");
        require(smartWalletFactory.isDeployedAccount(msg.sender), "ONLY_SMART_WALLET");

        m.consumed = true;
        _mint(m.recipient, m.amount);
        emit MessageConsumed(messageId, m.recipient, m.amount);
    }

    /**
     * @notice Dev stub matching Hyperlane TokenRouter API — burns from `msg.sender` (must be SmartWallet).
     * @dev Production monorepo token dispatches via Mailbox; this only burns for local testing.
     */
    function transferRemote(uint32 destination, bytes32 recipient, uint256 amount) external payable returns (bytes32 messageId) {
        require(amount > 0, "AMOUNT_ZERO");
        require(recipient != bytes32(0), "RECIPIENT_ZERO");
        _burn(msg.sender, amount);
        messageId = keccak256(abi.encode(destination, recipient, amount, msg.sender, block.number));
        emit TransferRemoteDev(destination, recipient, amount, messageId);
        return messageId;
    }

    function isMessageConsumable(bytes32 messageId, address caller) external view returns (bool) {
        PendingMessage storage m = messages[messageId];
        if (address(smartWalletFactory) == address(0)) return false;
        if (m.recipient == address(0) || m.consumed) return false;
        if (block.timestamp > m.expiry) return false;
        if (caller != m.recipient) return false;
        if (!smartWalletFactory.isDeployedAccount(caller)) return false;
        return true;
    }
}
