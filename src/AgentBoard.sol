// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Minimal read interface for the SPACE ID Agent ID contract
///         (ERC-721, non-transferable, one per user) on BNB Chain.
interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}

/// @title AgentBoard — an Agent-ID-native intent board, check-in and vouch board
/// @notice Every write on this board requires the caller to hold an Agent ID
///         (`balanceOf(agentId, caller) > 0`). The Agent ID is not a cosmetic
///         badge here: it is the board's only access-control mechanism, its
///         anti-spam identity layer, and the key that ties every intent,
///         check-in streak and vouch to a unique on-chain agent identity.
///
///         What holders can do:
///         1. Post one public intent ("what my agent does / what I need"),
///            update it, or take it down.
///         2. Check in once per UTC day to build a visible streak.
///         3. Vouch for other holders' intents (one vouch per holder per intent).
///
///         The contract holds no funds, takes no fees, offers no token and
///         promises no returns. Contact between holders happens off-chain,
///         holder to holder; the board only publishes what a holder opts in
///         to publish about their own agent identity.
contract AgentBoard {
    // ------------------------------------------------------------------
    // Errors
    // ------------------------------------------------------------------
    error NotAgentIdHolder();
    error EmptyText();
    error TextTooLong(uint256 length, uint256 max);
    error IntentAlreadyActive();
    error NoActiveIntent();
    error IntentNotFound(uint256 intentId);
    error IntentInactive(uint256 intentId);
    error CannotVouchOwnIntent();
    error AlreadyVouched(uint256 intentId);
    error AlreadyCheckedInToday();

    // ------------------------------------------------------------------
    // Types & storage
    // ------------------------------------------------------------------
    struct Intent {
        address author;
        string text;
        uint64 createdAt;
        uint64 updatedAt;
        bool active;
        uint32 vouchCount;
    }

    uint256 public constant MAX_TEXT_BYTES = 280;

    /// @notice The Agent ID contract this board gates on (immutable).
    IAgentId public immutable agentId;

    Intent[] private _intents;

    /// @notice author => intent id + 1 (0 means the author never posted).
    mapping(address => uint256) public intentRefOf;

    /// @notice user => last check-in day number (block.timestamp / 1 days).
    mapping(address => uint64) public lastCheckInDayOf;
    /// @notice user => current consecutive-day check-in streak.
    mapping(address => uint32) public streakOf;
    /// @notice user => lifetime check-in count.
    mapping(address => uint32) public totalCheckInsOf;

    /// @notice intent id => voter => already vouched.
    mapping(uint256 => mapping(address => bool)) public hasVouched;

    /// @notice user => has interacted with the board at least once.
    mapping(address => bool) public hasInteracted;
    /// @notice Count of distinct Agent ID holders that have ever interacted.
    uint256 public uniqueInteractors;

    // ------------------------------------------------------------------
    // Events
    // ------------------------------------------------------------------
    event IntentPosted(address indexed author, uint256 indexed intentId, string text);
    event IntentUpdated(address indexed author, uint256 indexed intentId, string text);
    event IntentDeactivated(address indexed author, uint256 indexed intentId);
    event CheckedIn(address indexed user, uint64 indexed day, uint32 streak);
    event Vouched(address indexed voter, uint256 indexed intentId, address indexed author);
    event FirstInteraction(address indexed user);

    // ------------------------------------------------------------------
    // Construction & gate
    // ------------------------------------------------------------------
    /// @param agentId_ Address of the Agent ID (ERC-721) contract.
    constructor(address agentId_) {
        require(agentId_ != address(0), "agentId is zero address");
        agentId = IAgentId(agentId_);
    }

    /// @notice True when `user` currently holds an Agent ID.
    function isHolder(address user) public view returns (bool) {
        return agentId.balanceOf(user) > 0;
    }

    modifier onlyHolder() {
        if (!isHolder(msg.sender)) revert NotAgentIdHolder();
        _;
    }

    // ------------------------------------------------------------------
    // Intents
    // ------------------------------------------------------------------
    /// @notice Post your intent. One active intent per holder.
    /// @param text Short public text (1–280 bytes): what your agent does,
    ///        or what you are looking for.
    /// @return intentId The id of the new intent.
    function postIntent(string calldata text) external onlyHolder returns (uint256 intentId) {
        _validateText(text);
        uint256 ref = intentRefOf[msg.sender];
        if (ref != 0 && _intents[ref - 1].active) revert IntentAlreadyActive();

        intentId = _intents.length;
        _intents.push(
            Intent({
                author: msg.sender,
                text: text,
                createdAt: uint64(block.timestamp),
                updatedAt: uint64(block.timestamp),
                active: true,
                vouchCount: 0
            })
        );
        intentRefOf[msg.sender] = intentId + 1;
        _markInteraction();
        emit IntentPosted(msg.sender, intentId, text);
    }

    /// @notice Replace the text of your active intent.
    function updateIntent(string calldata text) external onlyHolder {
        _validateText(text);
        uint256 id = _activeIntentIdOf(msg.sender);
        Intent storage intent = _intents[id];
        intent.text = text;
        intent.updatedAt = uint64(block.timestamp);
        _markInteraction();
        emit IntentUpdated(msg.sender, id, text);
    }

    /// @notice Take your intent down. It stays in history, marked inactive,
    ///         and can no longer receive vouches. You may post a fresh one.
    function deactivateIntent() external onlyHolder {
        uint256 id = _activeIntentIdOf(msg.sender);
        _intents[id].active = false;
        _markInteraction();
        emit IntentDeactivated(msg.sender, id);
    }

    // ------------------------------------------------------------------
    // Daily check-in
    // ------------------------------------------------------------------
    /// @notice Check in for today (UTC). Builds a consecutive-day streak;
    ///         a missed day restarts the streak at 1.
    /// @return streak The caller's streak after this check-in.
    function checkIn() external onlyHolder returns (uint32 streak) {
        uint64 today = uint64(block.timestamp / 1 days);
        uint64 last = lastCheckInDayOf[msg.sender];
        if (last == today) revert AlreadyCheckedInToday();

        streak = (last == today - 1) ? streakOf[msg.sender] + 1 : 1;
        streakOf[msg.sender] = streak;
        lastCheckInDayOf[msg.sender] = today;
        totalCheckInsOf[msg.sender] += 1;
        _markInteraction();
        emit CheckedIn(msg.sender, today, streak);
    }

    /// @notice True when `user` has already checked in for the current UTC day.
    function hasCheckedInToday(address user) external view returns (bool) {
        return lastCheckInDayOf[user] == uint64(block.timestamp / 1 days);
    }

    // ------------------------------------------------------------------
    // Vouching
    // ------------------------------------------------------------------
    /// @notice Vouch for another holder's active intent. One vouch per
    ///         holder per intent; you cannot vouch for your own intent.
    function vouch(uint256 intentId) external onlyHolder {
        if (intentId >= _intents.length) revert IntentNotFound(intentId);
        Intent storage intent = _intents[intentId];
        if (!intent.active) revert IntentInactive(intentId);
        if (intent.author == msg.sender) revert CannotVouchOwnIntent();
        if (hasVouched[intentId][msg.sender]) revert AlreadyVouched(intentId);

        hasVouched[intentId][msg.sender] = true;
        intent.vouchCount += 1;
        _markInteraction();
        emit Vouched(msg.sender, intentId, intent.author);
    }

    // ------------------------------------------------------------------
    // Views
    // ------------------------------------------------------------------
    /// @notice Total intents ever posted (including deactivated ones).
    function intentCount() external view returns (uint256) {
        return _intents.length;
    }

    /// @notice Read one intent by id.
    function getIntent(uint256 intentId) external view returns (Intent memory) {
        if (intentId >= _intents.length) revert IntentNotFound(intentId);
        return _intents[intentId];
    }

    /// @notice The intent id of `author`'s current intent, if any.
    /// @return found Whether the author has an intent record at all.
    /// @return intentId The intent id (valid only when `found` is true).
    /// @return active Whether that intent is currently active.
    function intentOf(address author) external view returns (bool found, uint256 intentId, bool active) {
        uint256 ref = intentRefOf[author];
        if (ref == 0) return (false, 0, false);
        intentId = ref - 1;
        return (true, intentId, _intents[intentId].active);
    }

    // ------------------------------------------------------------------
    // Internals
    // ------------------------------------------------------------------
    function _validateText(string calldata text) internal pure {
        uint256 len = bytes(text).length;
        if (len == 0) revert EmptyText();
        if (len > MAX_TEXT_BYTES) revert TextTooLong(len, MAX_TEXT_BYTES);
    }

    function _activeIntentIdOf(address author) internal view returns (uint256) {
        uint256 ref = intentRefOf[author];
        if (ref == 0 || !_intents[ref - 1].active) revert NoActiveIntent();
        return ref - 1;
    }

    function _markInteraction() internal {
        if (!hasInteracted[msg.sender]) {
            hasInteracted[msg.sender] = true;
            uniqueInteractors += 1;
            emit FirstInteraction(msg.sender);
        }
    }
}
