// SPDX-License-Identifier: Apache-2.0
pragma solidity >=0.8.0;

import {TypeCasts} from "../libs/TypeCasts.sol";
import {HypERC20} from "./HypERC20.sol";
import {TokenMessage} from "./libs/TokenMessage.sol";
import {TokenRouter} from "./libs/TokenRouter.sol";

interface IDravanaSmartWalletFactory {
    function isDeployedAccount(address account) external view returns (bool);

    function isAllowedInboundWarpRecipient(address account) external view returns (bool);
}

/**
 * @title DravanaSynthetic
 * @notice Synthetic warp ERC20 for production: outbound uses Hyperlane `transferRemote` (`TokenRouter`),
 *         inbound overrides `_handle` to store pending mint (Option 2), then recipients call `consumeAndMint`.
 * @dev Extends `HypERC20` with Dravana-specific inbound handling:
 *      - Uses inherited `Router.handle` → `_handle` (remote router enrollment enforced).
 *      - Pending row key: `keccak256(abi.encode(origin, sender, body))` matching backend `computePendingMintMessageId`.
 *      - Supports legacy 64-byte token bodies or 96-byte bodies with trailing metadata (salt), matching `TokenMessage` layout.
 */
contract DravanaSynthetic is HypERC20 {
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

    mapping(bytes32 => PendingMessage) public messages;
    mapping(uint32 => uint256) public domainToChain;

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

    constructor(
        uint8 __decimals,
        uint256 _scaleNumerator,
        uint256 _scaleDenominator,
        address _mailbox
    ) HypERC20(__decimals, _scaleNumerator, _scaleDenominator, _mailbox) {}

    /**
     * @inheritdoc HypERC20
     */
    function initialize(
        uint256 _totalSupply,
        string memory _name,
        string memory _symbol,
        address _hook,
        address _interchainSecurityModule,
        address _owner
    ) public virtual override initializer {
        super.initialize(_totalSupply, _name, _symbol, _hook, _interchainSecurityModule, _owner);
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
     * @dev Override of `TokenRouter._handle`. Stores pending mint instead of minting immediately;
     *      amount is scaled with `_inboundAmount`.
     */
    function _handle(
        uint32 _origin,
        bytes32 _sender,
        bytes calldata _message
    ) internal virtual override {
        require(_message.length == 64 || _message.length == 96, "BAD_TOKEN_MSG");

        address recipient = _message.recipient().bytes32ToAddress();
        uint256 rawAmount = _message.amount();
        require(recipient != address(0), "INVALID_RECIPIENT");
        require(rawAmount > 0, "INVALID_AMOUNT");

        require(address(smartWalletFactory) != address(0), "FACTORY_UNSET");
        require(smartWalletFactory.isAllowedInboundWarpRecipient(recipient), "RECIPIENT_NOT_SW");

        bytes32 messageId = keccak256(abi.encode(_origin, _sender, _message));
        require(messages[messageId].recipient == address(0), "MESSAGE_EXISTS");

        uint256 localAmount = _inboundAmount(rawAmount);

        uint256 expiry = block.timestamp + pendingMintTtl;
        messages[messageId] = PendingMessage({
            recipient: recipient,
            amount: localAmount,
            originDomain: _origin,
            remoteSender: _sender,
            expiry: expiry,
            consumed: false
        });

        emit MessageStored(messageId, recipient, localAmount, _origin, _sender, expiry);
    }

    function consumeAndMint(bytes32 messageId) external virtual {
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

    function isMessageConsumable(bytes32 messageId, address caller) external view returns (bool) {
        PendingMessage storage pending = messages[messageId];
        if (address(smartWalletFactory) == address(0)) return false;
        if (pending.recipient == address(0) || pending.consumed) return false;
        if (block.timestamp > pending.expiry) return false;
        if (caller != pending.recipient) return false;
        if (!smartWalletFactory.isDeployedAccount(caller)) return false;
        return true;
    }
}
