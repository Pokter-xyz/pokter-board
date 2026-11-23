// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PokterBoard} from "../src/PokterBoard.sol";
import {MockAgentId, MockEscrow} from "./PokterBoard.t.sol";

/// @notice Drives random hires and reviews from a few holders of a few agents, and keeps its own
/// tally of each holder's latest rating of each agent for the invariants to compare against.
contract ReviewHandler is Test {
    PokterBoard internal board;
    MockEscrow internal escrow;

    address[3] public holders = [address(0xB0), address(0xB1), address(0xB2)];
    address[2] public agents = [address(0xA6), address(0xA7)];

    mapping(address agent => mapping(address holder => uint8)) public latest;
    uint256 internal nextJob = 1;

    constructor(PokterBoard board_, MockEscrow escrow_) {
        board = board_;
        escrow = escrow_;
    }

    /// A holder hires an agent, the agent delivers, and the holder reviews the job.
    function hireAndReview(uint256 holderSeed, uint256 agentSeed, uint8 statusSeed, uint8 ratingSeed) external {
        address holder = holders[holderSeed % holders.length];
        address agent = agents[agentSeed % agents.length];
        uint8 status = uint8(3 + (statusSeed % 2)); // settled, or rejected under the router's policy
        uint8 rating = uint8(bound(ratingSeed, 1, 5));
        uint256 jobId = nextJob++;
        escrow.put(jobId, holder, agent, 0.01 ether, status, 1_700_000_000 + jobId);
        vm.prank(holder);
        board.review(jobId, rating, 0, bytes32(0));
        latest[agent][holder] = rating;
    }

    /// A holder funds a job the agent never delivered to; the review must be refused and change nothing.
    function reviewUndelivered(uint256 holderSeed, uint256 agentSeed, uint8 ratingSeed) external {
        address holder = holders[holderSeed % holders.length];
        address agent = agents[agentSeed % agents.length];
        uint256 jobId = nextJob++;
        escrow.put(jobId, holder, agent, 0.01 ether, 5, 0);
        vm.prank(holder);
        vm.expectRevert(PokterBoard.NothingDelivered.selector);
        board.review(jobId, uint8(bound(ratingSeed, 1, 5)), 0, bytes32(0));
    }

    /// A holder takes a delivery's money back, refunded after the deadline or rejected as its own evaluator;
    /// the review must be refused and change nothing.
    function reviewTakenBack(uint256 holderSeed, uint256 agentSeed, bool selfRejected, uint8 ratingSeed) external {
        address holder = holders[holderSeed % holders.length];
        address agent = agents[agentSeed % agents.length];
        uint256 jobId = nextJob++;
        escrow.put(jobId, holder, agent, 0.01 ether, selfRejected ? 4 : 5, 1_700_000_000 + jobId);
        if (selfRejected) escrow.evaluatedBy(jobId, holder);
        vm.prank(holder);
        vm.expectRevert(
            selfRejected ? PokterBoard.RejectedOutsidePolicy.selector : PokterBoard.RefundedAfterDeadline.selector
        );
        board.review(jobId, uint8(bound(ratingSeed, 1, 5)), 0, bytes32(0));
    }

    /// The same job reviewed a second time must be refused.
    function reviewAgain(uint256 jobSeed) external {
        if (nextJob == 1) return;
        uint256 jobId = 1 + (jobSeed % (nextJob - 1));
        if (!board.reviewed(jobId)) return;
        vm.prank(escrow.getJob(jobId).client);
        vm.expectRevert(PokterBoard.AlreadyReviewed.selector);
        board.review(jobId, 1, 0, bytes32(0));
    }
}

contract PokterBoardInvariantTest is Test {
    PokterBoard board;
    ReviewHandler handler;

    function setUp() public {
        MockAgentId ids = new MockAgentId();
        MockEscrow escrow = new MockEscrow();
        board = new PokterBoard(ids, escrow, escrow.ROUTER());
        handler = new ReviewHandler(board, escrow);
        for (uint256 i = 0; i < 3; i++) {
            ids.give(handler.holders(i));
        }
        targetContract(address(handler));
    }

    /// An agent's rating is exactly one current rating per holder who reviewed it.
    function invariant_eachHolderCountsOnceAtTheirLatestRating() public view {
        for (uint256 a = 0; a < 2; a++) {
            address agent = handler.agents(a);
            uint64 expectedReviewers;
            uint64 expectedStars;
            for (uint256 h = 0; h < 3; h++) {
                address holder = handler.holders(h);
                uint8 rating = handler.latest(agent, holder);
                assertEq(board.ratingFrom(agent, holder), rating);
                if (rating != 0) {
                    expectedReviewers += 1;
                    expectedStars += rating;
                }
            }
            (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
            assertEq(reviewers, expectedReviewers);
            assertEq(stars, expectedStars);
        }
    }
}
