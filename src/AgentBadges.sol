// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title AgentBadges — soulbound achievement badges for Binance Agent ID holders
/// @notice Built for the Binance Agent ID Hackathon (submission closes 9 Dec 2026).
/// @dev Minimal self-contained ERC-721 (no external imports) so the contract
///      verifies on BscScan as a single file. Badges are SOULBOUND: every
///      transfer / approval reverts. Tips forward immediately to the recipient;
///      the contract never holds user funds (there is no withdraw function).
///      Gating: gm(), tip() and claimBadge() all require the caller to hold
///      an Agent ID (balanceOf > 0 on the Agent ID contract).
///      NOTE: the Agent ID contract does NOT implement ERC721Enumerable, so
///      this contract never relies on enumeration of Agent IDs.
contract AgentBadges {
    // ------------------------------------------------------------------------
    // Agent ID (SPACE ID Agent ID, ERC-721, soulbound, BSC mainnet)
    // Passed in the constructor so tests can point at a mock; on mainnet use
    // 0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F.
    // ------------------------------------------------------------------------
    address public immutable agentId;

    /// @notice Minimum tip: 0.0001 BNB.
    uint256 public constant MIN_TIP = 0.0001 ether;
    uint256 public constant DAY = 1 days;

    // ------------------------------------------------------------------------
    // Badges (token ids 1-5 are BADGE types; each mint gets a unique tokenId)
    // ------------------------------------------------------------------------
    uint256 public constant BADGE_FIRST_GM = 1;
    uint256 public constant BADGE_STREAK_3 = 2;
    uint256 public constant BADGE_STREAK_7 = 3;
    uint256 public constant BADGE_FIRST_TIP = 4;
    uint256 public constant BADGE_COLLECTOR = 5;
    uint256 public constant BADGE_COUNT = 5;

    string public constant name = "AgentBadges";
    string public constant symbol = "AGBADGE";

    /// @notice Base URL for badge artwork (static SVGs in the repo, GitHub Pages).
    string public constant IMAGE_BASE = "https://itaro9110.github.io/agentbadges/badges/";

    // ------------------------------------------------------------------------
    // ERC-721 storage
    // ------------------------------------------------------------------------
    mapping(uint256 => address) private _owners;
    mapping(address => uint256) private _balances;
    /// @notice Next token id to mint; also equals the total badges minted.
    uint256 public nextTokenId;
    /// @notice tokenId => badge id (1-5).
    mapping(uint256 => uint256) public tokenBadge;

    // ------------------------------------------------------------------------
    // Quest state
    // ------------------------------------------------------------------------
    /// @notice Day number (block.timestamp / 1 days) of the user's last GM.
    mapping(address => uint256) public lastGmDay;
    /// @notice Current consecutive-day GM streak.
    mapping(address => uint256) public currentStreak;
    /// @notice Total distinct days the user has GM'd.
    mapping(address => uint256) public totalGmDays;
    /// @notice True once the user has tipped another Agent ID holder.
    mapping(address => bool) public hasTipped;
    /// @notice user => badge id => earned?
    mapping(address => mapping(uint256 => bool)) public hasBadge;
    /// @notice Number of distinct badges a user holds.
    mapping(address => uint256) public badgeCount;
    mapping(address => uint256[]) private _userBadges;

    // Simple reentrancy guard (tip() forwards ETH).
    uint256 private _locked = 1;

    // ------------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------------
    event GM(address indexed user, uint256 indexed day, uint256 streak);
    event Tip(address indexed from, address indexed to, uint256 amount);
    event BadgeClaimed(address indexed user, uint256 indexed badgeId, uint256 tokenId);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    // ------------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------------
    error NotAgentIdHolder();
    error RecipientNotAgentIdHolder();
    error AlreadyCheckedInToday();
    error TipTooSmall();
    error TipFailed();
    error CannotTipSelf();
    error InvalidBadge();
    error BadgeAlreadyClaimed();
    error QuestNotComplete();
    error Soulbound();
    error NonexistentToken();
    error Reentrancy();
    error ZeroAddress();

    modifier nonReentrant() {
        if (_locked != 1) revert Reentrancy();
        _locked = 2;
        _;
        _locked = 1;
    }

    constructor(address _agentId) {
        if (_agentId == address(0)) revert ZeroAddress();
        agentId = _agentId;
    }

    // ------------------------------------------------------------------------
    // Agent ID gating
    // ------------------------------------------------------------------------
    /// @notice True if `user` holds at least one Agent ID.
    function isAgentIdHolder(address user) public view returns (bool) {
        return IAgentId(agentId).balanceOf(user) > 0;
    }

    // ------------------------------------------------------------------------
    // Quests
    // ------------------------------------------------------------------------
    /// @notice Daily check-in. Once per day per address. Builds the GM streak.
    function gm() external {
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder();
        uint256 day = block.timestamp / DAY;
        if (lastGmDay[msg.sender] == day) revert AlreadyCheckedInToday();
        if (lastGmDay[msg.sender] == day - 1) {
            currentStreak[msg.sender] += 1;
        } else {
            currentStreak[msg.sender] = 1;
        }
        lastGmDay[msg.sender] = day;
        totalGmDays[msg.sender] += 1;
        emit GM(msg.sender, day, currentStreak[msg.sender]);
    }

    /// @notice Tip another Agent ID holder. The full amount is forwarded
    ///         immediately; the contract keeps nothing.
    function tip(address to) external payable nonReentrant {
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder();
        if (to == msg.sender) revert CannotTipSelf();
        if (!isAgentIdHolder(to)) revert RecipientNotAgentIdHolder();
        if (msg.value < MIN_TIP) revert TipTooSmall();
        hasTipped[msg.sender] = true;
        (bool ok,) = to.call{value: msg.value}("");
        if (!ok) revert TipFailed();
        emit Tip(msg.sender, to, msg.value);
    }

    /// @notice Claim a badge once its quest condition is met. One per address.
    function claimBadge(uint256 badgeId) external {
        if (badgeId == 0 || badgeId > BADGE_COUNT) revert InvalidBadge();
        if (!isAgentIdHolder(msg.sender)) revert NotAgentIdHolder();
        if (hasBadge[msg.sender][badgeId]) revert BadgeAlreadyClaimed();
        if (badgeId == BADGE_FIRST_GM) {
            if (totalGmDays[msg.sender] < 1) revert QuestNotComplete();
        } else if (badgeId == BADGE_STREAK_3) {
            if (currentStreak[msg.sender] < 3) revert QuestNotComplete();
        } else if (badgeId == BADGE_STREAK_7) {
            if (currentStreak[msg.sender] < 7) revert QuestNotComplete();
        } else if (badgeId == BADGE_FIRST_TIP) {
            if (!hasTipped[msg.sender]) revert QuestNotComplete();
        } else if (badgeId == BADGE_COLLECTOR) {
            if (badgeCount[msg.sender] < 3) revert QuestNotComplete();
        }

        uint256 tokenId = ++nextTokenId;
        hasBadge[msg.sender][badgeId] = true;
        badgeCount[msg.sender] += 1;
        _userBadges[msg.sender].push(badgeId);
        tokenBadge[tokenId] = badgeId;
        _owners[tokenId] = msg.sender;
        _balances[msg.sender] += 1;
        emit Transfer(address(0), msg.sender, tokenId);
        emit BadgeClaimed(msg.sender, badgeId, tokenId);
    }

    // ------------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------------
    /// @notice Badge ids (1-5) earned by `user`, in claim order.
    function badgesOf(address user) external view returns (uint256[] memory) {
        return _userBadges[user];
    }

    /// @notice Current consecutive-day GM streak of `user`.
    function gmStreak(address user) external view returns (uint256) {
        return currentStreak[user];
    }

    /// @notice Human-readable name of a badge.
    function badgeName(uint256 badgeId) public pure returns (string memory) {
        if (badgeId == BADGE_FIRST_GM) return "First GM";
        if (badgeId == BADGE_STREAK_3) return "Three-Day Streak";
        if (badgeId == BADGE_STREAK_7) return "Seven-Day Streak";
        if (badgeId == BADGE_FIRST_TIP) return "First Tip";
        if (badgeId == BADGE_COLLECTOR) return "Collector";
        return "";
    }

    /// @notice Human-readable description of a badge.
    function badgeDescription(uint256 badgeId) public pure returns (string memory) {
        if (badgeId == BADGE_FIRST_GM) return "Say GM once as an Agent ID holder.";
        if (badgeId == BADGE_STREAK_3) return "Say GM on 3 consecutive days.";
        if (badgeId == BADGE_STREAK_7) return "Say GM on 7 consecutive days.";
        if (badgeId == BADGE_FIRST_TIP) return "Tip another Agent ID holder at least 0.0001 BNB.";
        if (badgeId == BADGE_COLLECTOR) return "Hold any 3 AgentBadges.";
        return "";
    }

    // ------------------------------------------------------------------------
    // ERC-721 (minimal, soulbound)
    // ------------------------------------------------------------------------
    function balanceOf(address owner) public view returns (uint256) {
        if (owner == address(0)) revert NonexistentToken();
        return _balances[owner];
    }

    function ownerOf(uint256 tokenId) public view returns (address) {
        address owner = _owners[tokenId];
        if (owner == address(0)) revert NonexistentToken();
        return owner;
    }

    /// @notice On-chain metadata: data:application/json;base64 JSON with name,
    ///         description, artwork URL and attributes. No external metadata host.
    function tokenURI(uint256 tokenId) public view returns (string memory) {
        if (_owners[tokenId] == address(0)) revert NonexistentToken();
        uint256 badgeId = tokenBadge[tokenId];
        string memory json = string(
            abi.encodePacked(
                '{"name":"AgentBadges #',
                _toString(tokenId),
                " - ",
                badgeName(badgeId),
                '","description":"Soulbound achievement badge for Binance Agent ID holders. ',
                badgeDescription(badgeId),
                '","image":"',
                IMAGE_BASE,
                _toString(badgeId),
                '.svg","attributes":[{"trait_type":"Badge","value":"',
                badgeName(badgeId),
                '"},{"trait_type":"Badge ID","value":',
                _toString(badgeId),
                "}]}"
            )
        );
        return string(abi.encodePacked("data:application/json;base64,", _base64(bytes(json))));
    }

    // Soulbound: every transfer / approval reverts.
    function approve(address, uint256) public pure {
        revert Soulbound();
    }

    function setApprovalForAll(address, bool) public pure {
        revert Soulbound();
    }

    function getApproved(uint256) public pure returns (address) {
        return address(0);
    }

    function isApprovedForAll(address, address) public pure returns (bool) {
        return false;
    }

    function transferFrom(address, address, uint256) public pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256) public pure {
        revert Soulbound();
    }

    function safeTransferFrom(address, address, uint256, bytes memory) public pure {
        revert Soulbound();
    }

    function supportsInterface(bytes4 interfaceId) public pure returns (bool) {
        return interfaceId == 0x01ffc9a7 // ERC165
            || interfaceId == 0x80ac58cd // ERC721
            || interfaceId == 0x5b5e139f; // ERC721Metadata
    }

    // ------------------------------------------------------------------------
    // Helpers (pure Solidity, no assembly)
    // ------------------------------------------------------------------------
    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    bytes internal constant _BASE64_TABLE = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

    function _base64(bytes memory data) internal pure returns (string memory) {
        uint256 len = data.length;
        if (len == 0) return "";
        uint256 encodedLen = 4 * ((len + 2) / 3);
        bytes memory result = new bytes(encodedLen);
        bytes memory table = _BASE64_TABLE;
        uint256 j = 0;
        for (uint256 i = 0; i < len; i += 3) {
            uint256 a = uint256(uint8(data[i]));
            uint256 b = i + 1 < len ? uint256(uint8(data[i + 1])) : 0;
            uint256 c = i + 2 < len ? uint256(uint8(data[i + 2])) : 0;
            uint256 triple = (a << 16) | (b << 8) | c;
            result[j++] = table[(triple >> 18) & 0x3F];
            result[j++] = table[(triple >> 12) & 0x3F];
            result[j++] = i + 1 < len ? table[(triple >> 6) & 0x3F] : bytes1("=");
            result[j++] = i + 2 < len ? table[triple & 0x3F] : bytes1("=");
        }
        return string(result);
    }
}

/// @notice Minimal interface of the Agent ID contract (only what we need).
interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}
