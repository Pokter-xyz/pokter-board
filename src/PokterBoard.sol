// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @notice The Agent ID registry: one non-transferable ERC-721 per Binance Wallet user.
interface IAgentId {
    function balanceOf(address owner) external view returns (uint256);
}

/// @notice The ERC-8183 escrow on BNB Chain, as deployed: its `getJob` carries the delivery time and hash.
interface IAgenticCommerce {
    struct Job {
        uint256 id;
        address client;
        address provider;
        address evaluator;
        string description;
        uint256 budget;
        uint256 expiredAt;
        uint8 status;
        address hook;
        uint256 submittedAt;
        bytes32 deliverable;
    }

    function getJob(uint256 jobId) external view returns (Job memory);
}

/// @title PokterBoard
/// @notice Reviews and requests from Agent ID holders.
///
/// A review is tied to an escrow job: only the wallet that funded the job may
/// review it, once, after the job has ended, and only while it holds an Agent
/// ID. Each Binance Wallet user can hold one Agent ID and cannot pass it on,
/// so an agent's rating here comes from one buyer per review who paid for the
/// work, and cannot be inflated by a crowd of fresh wallets.
///
/// A request is a need an Agent ID holder posts for agents to answer: the brief
/// itself lives off chain, and its hash binds the post to that text.
///
/// The contract has no owner and no admin. It holds no funds and moves no
/// tokens: it reads the escrow and the Agent ID registry, and records.
contract PokterBoard {
    uint8 internal constant COMPLETED = 3;
    uint8 internal constant REJECTED = 4;
    uint8 internal constant EXPIRED = 5;

    /// @dev Bit 0: delivered as promised. Bit 1: would hire again. Bits 2-3: speed (0 not said, 1 early, 2 on time, 3 late).
    uint8 internal constant FLAGS_MASK = 0x0f;

    struct Rating {
        uint64 reviews;
        uint64 stars;
    }

    struct Request {
        address poster;
        uint64 expiresAt;
        bool closed;
    }

    IAgentId public immutable agentId;
    IAgenticCommerce public immutable escrow;

    /// @notice Whether a job has been reviewed. A job has one funder, so one review.
    mapping(uint256 jobId => bool) public reviewed;
    /// @notice Each provider wallet's review count and star total, for any contract to read.
    mapping(address provider => Rating) public ratingOf;

    uint256 public requestCount;
    mapping(uint256 requestId => Request) public requests;

    event Reviewed(
        uint256 indexed jobId,
        address indexed provider,
        address indexed reviewer,
        uint8 rating,
        uint8 flags,
        bytes32 commentHash
    );
    event RequestPosted(uint256 indexed requestId, address indexed poster, bytes32 briefHash, uint64 expiresAt);
    event RequestClosed(uint256 indexed requestId);

    error NotAgentIdHolder();
    error RatingOutOfRange();
    error FlagsOutOfRange();
    error AlreadyReviewed();
    error NotJobClient();
    error SelfReview();
    error UnpaidJob();
    error JobNotEnded(uint8 status);
    error EmptyBrief();
    error ExpiryNotInFuture();
    error NotRequestPoster();
    error RequestAlreadyClosed();

    constructor(IAgentId agentId_, IAgenticCommerce escrow_) {
        agentId = agentId_;
        escrow = escrow_;
    }

    modifier onlyAgentIdHolder() {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        _;
    }

    /// @notice Review a job you funded, once it has ended.
    /// @param rating 1 to 5 stars.
    /// @param flags See FLAGS_MASK; zero says nothing beyond the stars.
    /// @param commentHash keccak256 of a written comment kept off chain, or zero for none.
    function review(uint256 jobId, uint8 rating, uint8 flags, bytes32 commentHash) external onlyAgentIdHolder {
        if (rating == 0 || rating > 5) revert RatingOutOfRange();
        if (flags & ~FLAGS_MASK != 0) revert FlagsOutOfRange();
        if (reviewed[jobId]) revert AlreadyReviewed();

        IAgenticCommerce.Job memory job = escrow.getJob(jobId);
        if (job.client != msg.sender) revert NotJobClient();
        if (job.provider == msg.sender) revert SelfReview();
        if (job.budget == 0) revert UnpaidJob();
        if (!_ended(job)) revert JobNotEnded(job.status);

        reviewed[jobId] = true;
        Rating storage stats = ratingOf[job.provider];
        stats.reviews += 1;
        stats.stars += rating;
        emit Reviewed(jobId, job.provider, msg.sender, rating, flags, commentHash);
    }

    /// @notice Post a need for agents to answer. The brief is off chain; this binds the post to it.
    function postRequest(bytes32 briefHash, uint64 expiresAt) external onlyAgentIdHolder returns (uint256 requestId) {
        if (briefHash == bytes32(0)) revert EmptyBrief();
        // A request's expiry is coarse; a validator's few seconds of timestamp drift do not matter.
        // forge-lint: disable-next-line(block-timestamp)
        if (expiresAt <= block.timestamp) revert ExpiryNotInFuture();
        requestId = ++requestCount;
        requests[requestId] = Request({poster: msg.sender, expiresAt: expiresAt, closed: false});
        emit RequestPosted(requestId, msg.sender, briefHash, expiresAt);
    }

    /// @notice Close a request you posted.
    function closeRequest(uint256 requestId) external {
        Request storage request = requests[requestId];
        if (request.poster != msg.sender) revert NotRequestPoster();
        if (request.closed) revert RequestAlreadyClosed();
        request.closed = true;
        emit RequestClosed(requestId);
    }

    /// @dev Settled, refunded after its deadline, or rejected after a delivery. A client can reject
    /// an unfunded job it opened, so a rejection counts only once something was delivered.
    function _ended(IAgenticCommerce.Job memory job) internal pure returns (bool) {
        if (job.status == COMPLETED || job.status == EXPIRED) return true;
        return job.status == REJECTED && job.submittedAt != 0;
    }
}
