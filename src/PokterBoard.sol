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
/// A review is the verdict of someone who funded an agent's work, received a
/// delivery, and either paid for it or won a dispute over it: only the wallet that
/// funded an escrow job may review it, once, and only while that wallet holds an
/// Agent ID. The job must have been settled to the agent, or rejected by the
/// escrow router's dispute policy. A job its funder took back (refunded after the
/// deadline, or rejected by a client that named itself evaluator) is not reviewable:
/// either way the funder got their money back with nobody deciding against the agent.
///
/// An Agent ID is one per Binance Wallet user and cannot be passed on, so each
/// holder is one distinct person. A rating belongs to the job's provider wallet:
/// each holder counts once per wallet, and a holder's latest review of a wallet is
/// their rating of it, replacing any earlier one. Agents that share a provider
/// wallet share a rating, so a reader should attribute it to an agent only when
/// that agent is the wallet's only one.
///
/// A request is a need an Agent ID holder posts for agents to answer: the brief
/// itself lives off chain, and its hash binds the post to that text. Requests are
/// advisory: their expiry is not enforced, and a holder may post any number.
///
/// The contract has no owner and no admin. It holds no funds and moves no
/// tokens: it reads the escrow and the Agent ID registry, and records.
///
/// What it trusts, which it cannot check:
/// - The ERC-8183 escrow and its router are upgradeable proxies, pausable, owned by
///   a 2-of-3 Safe that also chooses the payment tokens. An upgrade could change what
///   `getJob` returns; one that changes the job layout would leave this board unable
///   to read jobs, and a new board would be needed, with no ratings carried over.
/// - The Agent ID registry is not upgradeable, but its owner, a single wallet, can
///   register an ID to any address and replace the signer that approves new IDs.
/// - "Funded" has no minimum: a job of any non-zero budget qualifies.
contract PokterBoard {
    uint8 internal constant COMPLETED = 3;
    uint8 internal constant REJECTED = 4;
    uint8 internal constant EXPIRED = 5;

    /// @dev Bit 0: delivered as promised. Bit 1: would hire again. Bits 2-3: speed (0 not said, 1 early, 2 on time, 3 late).
    uint8 internal constant FLAGS_MASK = 0x0f;

    /// @param reviewers Distinct Agent ID holders who have reviewed the agent.
    /// @param stars The sum of each reviewer's current rating, so `stars / reviewers` is the average.
    struct Rating {
        uint64 reviewers;
        uint64 stars;
    }

    struct Request {
        address poster;
        uint64 expiresAt;
        bool closed;
    }

    IAgentId public immutable agentId;
    IAgenticCommerce public immutable escrow;
    /// @notice The escrow's router: the evaluator on jobs hired through BNB's agent stack, whose dispute
    /// policy decides a rejection. A rejection by any other evaluator, such as the client itself, is not a verdict.
    address public immutable router;

    /// @notice Whether a job has been reviewed. A job has one funder, so one review.
    mapping(uint256 jobId => bool) public reviewed;
    /// @notice Each provider wallet's rating, for any contract to read.
    mapping(address provider => Rating) public ratingOf;
    /// @notice A reviewer's current rating of a provider, 1 to 5, or 0 if they have not reviewed it.
    mapping(address provider => mapping(address reviewer => uint8)) public ratingFrom;

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
    error NothingDelivered();
    error RefundedAfterDeadline();
    error RejectedOutsidePolicy();
    error EmptyBrief();
    error ExpiryNotInFuture();
    error NotRequestPoster();
    error RequestAlreadyClosed();

    constructor(IAgentId agentId_, IAgenticCommerce escrow_, address router_) {
        agentId = agentId_;
        escrow = escrow_;
        router = router_;
    }

    modifier onlyAgentIdHolder() {
        if (agentId.balanceOf(msg.sender) == 0) revert NotAgentIdHolder();
        _;
    }

    /// @notice Review a job you funded, once the agent has delivered and was paid, or lost a dispute decided by the router.
    /// @param rating 1 to 5 stars. It becomes your rating of the job's provider wallet, replacing any earlier one.
    /// @param flags See FLAGS_MASK; zero says nothing beyond the stars.
    /// @param commentHash keccak256 of the written comment's UTF-8 text, kept off chain, or zero for none.
    /// The rating and flags are here; the hash lets anyone attach the text later and prove it is the reviewer's.
    function review(uint256 jobId, uint8 rating, uint8 flags, bytes32 commentHash) external onlyAgentIdHolder {
        if (rating == 0 || rating > 5) revert RatingOutOfRange();
        if (flags & ~FLAGS_MASK != 0) revert FlagsOutOfRange();
        if (reviewed[jobId]) revert AlreadyReviewed();

        IAgenticCommerce.Job memory job = escrow.getJob(jobId);
        if (job.client != msg.sender) revert NotJobClient();
        if (job.provider == msg.sender) revert SelfReview();
        if (job.budget == 0) revert UnpaidJob();
        if (!_ended(job.status)) revert JobNotEnded(job.status);
        // A client can name any provider and fund a job without its agreement, so a job the agent
        // never delivered to may be one it never saw. A missed deadline stays on the escrow's own record.
        if (job.submittedAt == 0) revert NothingDelivered();
        // The funder took the money back with nobody deciding against the agent: after the deadline, any wallet
        // may refund an unsettled job, and a client that named itself evaluator may reject a delivery it received.
        // Either would let a holder review for the price of gas.
        if (job.status == EXPIRED) revert RefundedAfterDeadline();
        if (job.status == REJECTED && job.evaluator != router) revert RejectedOutsidePolicy();

        reviewed[jobId] = true;
        Rating storage stats = ratingOf[job.provider];
        uint8 previous = ratingFrom[job.provider][msg.sender];
        if (previous == 0) stats.reviewers += 1;
        stats.stars = stats.stars - previous + rating;
        ratingFrom[job.provider][msg.sender] = rating;
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

    /// @dev Settled, rejected by its evaluator, or refunded after its deadline: the job can no longer move. A client can
    /// also reject an open job it never funded; `review` refuses that through its delivery check, and refuses a refund or
    /// a rejection outside the router's policy after it.
    function _ended(uint8 status) internal pure returns (bool) {
        return status == COMPLETED || status == REJECTED || status == EXPIRED;
    }
}
