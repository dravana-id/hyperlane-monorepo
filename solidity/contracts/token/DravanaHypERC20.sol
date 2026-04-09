// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import {HypERC20} from "./HypERC20.sol";
import {TokenMessage} from "./libs/TokenMessage.sol";
import {TypeCasts} from "../libs/TypeCasts.sol";

interface IDravanaSmartWalletFactory {
    function isDeployedAccount(address account) external view returns (bool);
}

/**
 * @title DravanaHypERC20
 * @notice Delayed-mint synthetic token for Hyperlane Warp Route (Option 2).
 * @dev Keeps Router/Mailbox/ISM behavior and message format unchanged:
 *      `_handle(uint32,bytes32,bytes)` still receives TokenMessage payload.
 *      Instead of immediate mint in `_handle`, this contract stores pending messages
 *      and requires `consumeAndMint(messageId)` by intended recipient wallet.
 */
contract DravanaHypERC20 is HypERC20 {
    using TypeCasts for bytes32;
    using TokenMessage for bytes;

    struct PendingMessage {
        address recipient;
        uint256 amount;
        uint32 origin;
        bytes32 sender;
        uint256 expiry;
        bool consumed;
    }

    mapping(bytes32 => PendingMessage) public messages;

    /// @notice Default TTL (seconds) from message arrival to mint consumption.
    uint256 public pendingMintTtl = 1 days;

    /// @notice Dravana AA factory — unset disables recipient/caller allowlist checks.
    IDravanaSmartWalletFactory public smartWalletFactory;

    /// @notice Optional Hyperlane domain id -> EVM chain id (for SmartWallet outbound validation).
    mapping(uint32 => uint256) public domainToChain;

    event MessageStored(
        bytes32 indexed messageId,
        uint32 indexed origin,
        bytes32 indexed sender,
        address recipient,
        uint256 amount,
        uint256 expiry
    );
    event MessageConsumed(
        bytes32 indexed messageId,
        address indexed recipient,
        uint256 amount
    );
    event PendingMintTtlSet(uint256 ttl);

    constructor(
        uint8 __decimals,
        uint256 _scaleNumerator,
        uint256 _scaleDenominator,
        address _mailbox
    ) HypERC20(__decimals, _scaleNumerator, _scaleDenominator, _mailbox) {}

    /**
     * @notice Keep initialize signature compatible with warp deploy, but disallow
     *         direct initial minting (Option 2 delayed-mint policy).
     * @dev Proxy storage does not inherit `pendingMintTtl = 1 days` from the implementation
     *      bytecode initializer — must set TTL here or `pendingMintTtl` stays 0 (instant expiry).
     */
    function initialize(
        uint256,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner
    ) public override initializer {
        __ERC20_init(_name, _symbol);
        _MailboxClient_initialize(_hook, _interchainSecurityModule, _owner);
        pendingMintTtl = 1 days;
    }

    function setPendingMintTtl(uint256 _ttl) external onlyOwner {
        require(_ttl > 0, "ttl=0");
        pendingMintTtl = _ttl;
        emit PendingMintTtlSet(_ttl);
    }

    function setSmartWalletFactory(address _factory) external onlyOwner {
        require(_factory != address(0), "FACTORY_ZERO");
        smartWalletFactory = IDravanaSmartWalletFactory(_factory);
    }

    /// @notice Map Hyperlane destination domain to EVM chain id (optional SmartWallet domain checks).
    function setDomain(uint32 domain, uint256 evmChainId) external onlyOwner {
        require(evmChainId != 0, "CHAIN_ZERO");
        domainToChain[domain] = evmChainId;
    }

    /**
     * @dev Store-only receive path. No auto-mint.
     * Message format remains TokenMessage (recipient, amount).
     */
    function _handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) internal override {
        address recipient = _message.recipient().bytes32ToAddress();
        uint256 amount = _inboundAmount(_message.amount());
        bytes32 messageId = keccak256(abi.encode(_origin, _sender, _message));

        PendingMessage storage pending = messages[messageId];
        require(pending.recipient == address(0), "message exists");

        require(address(smartWalletFactory) != address(0), "FACTORY_UNSET");
        require(smartWalletFactory.isDeployedAccount(recipient), "RECIPIENT_NOT_SW");

        uint256 expiry = block.timestamp + pendingMintTtl;
        messages[messageId] = PendingMessage({
            recipient: recipient,
            amount: amount,
            origin: _origin,
            sender: _sender,
            expiry: expiry,
            consumed: false
        });

        emit ReceivedTransferRemote(_origin, _message.recipient(), _message.amount());
        emit MessageStored(messageId, _origin, _sender, recipient, amount, expiry);
    }

    function consumeAndMint(bytes32 messageId) external {
        PendingMessage storage pending = messages[messageId];
        require(pending.recipient != address(0), "message missing");
        require(!pending.consumed, "already consumed");
        require(block.timestamp <= pending.expiry, "expired");
        require(msg.sender == pending.recipient, "invalid recipient");
        require(pending.amount > 0, "amount=0");
        require(address(smartWalletFactory) != address(0), "FACTORY_UNSET");
        require(smartWalletFactory.isDeployedAccount(msg.sender), "ONLY_SMART_WALLET");

        pending.consumed = true;
        _mint(msg.sender, pending.amount);
        emit MessageConsumed(messageId, msg.sender, pending.amount);
    }

    /// @notice Whether `caller` may consume `messageId` (view helper for frontends / policy).
    function isMessageConsumable(bytes32 messageId, address caller) external view returns (bool) {
        PendingMessage storage pending = messages[messageId];
        if (address(smartWalletFactory) == address(0)) return false;
        if (pending.recipient == address(0) || pending.consumed) return false;
        if (block.timestamp > pending.expiry) return false;
        if (caller != pending.recipient) return false;
        if (!smartWalletFactory.isDeployedAccount(caller)) return false;
        return true;
    }

    /**
     * @dev Prevent all implicit mint paths from TokenRouter internals.
     *      Minting is only allowed via `consumeAndMint`.
     */
    function _transferTo(address, uint256) internal pure override {
        revert("use consumeAndMint");
    }

    /**
     * @dev Disable token-fee minting in delayed-mint mode.
     */
    function _transferFee(address, uint256 _amount) internal pure override {
        require(_amount == 0, "fee unsupported");
    }
}
