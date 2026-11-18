// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PokterBoard, IAgentId, IAgenticCommerce} from "../src/PokterBoard.sol";

contract MockAgentId is IAgentId {
    mapping(address => uint256) public balances;

    function give(address owner) external {
        balances[owner] = 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return balances[owner];
    }
}

contract MockEscrow is IAgenticCommerce {
    mapping(uint256 => Job) internal jobs;

    function put(uint256 id, address client, address provider, uint256 budget, uint8 status, uint256 submittedAt)
        external
    {
        jobs[id] = Job({
            id: id,
            client: client,
            provider: provider,
            evaluator: address(0xE),
            description: '{"task":"a brief long enough to be a real one"}',
            budget: budget,
            expiredAt: 2_000_000_000,
            status: status,
            hook: address(0),
            submittedAt: submittedAt,
            deliverable: keccak256("delivery")
        });
    }

    function getJob(uint256 jobId) external view returns (Job memory) {
        return jobs[jobId];
    }
}

contract PokterBoardTest is Test {
    uint8 constant OPEN = 0;
    uint8 constant FUNDED = 1;
    uint8 constant SUBMITTED = 2;
    uint8 constant COMPLETED = 3;
    uint8 constant REJECTED = 4;
    uint8 constant EXPIRED = 5;

    address buyer = address(0xB0);
    address stranger = address(0x51);
    address agent = address(0xA6);
    uint256 constant PRICE = 0.01 ether;

    MockAgentId ids;
    MockEscrow escrow;
    PokterBoard board;

    event Reviewed(
        uint256 indexed jobId,
        address indexed provider,
        address indexed reviewer,
        uint8 rating,
        uint8 flags,
        bytes32 reviewHash
    );
    event RequestPosted(uint256 indexed requestId, address indexed poster, bytes32 briefHash, uint64 expiresAt);
    event RequestClosed(uint256 indexed requestId);

    function setUp() public {
        ids = new MockAgentId();
        escrow = new MockEscrow();
        board = new PokterBoard(ids, escrow);
        ids.give(buyer);
        escrow.put(1, buyer, agent, PRICE, COMPLETED, 1_700_000_100);
    }

    function test_aFundedBuyerReviewsACompletedJob() public {
        vm.expectEmit(address(board));
        emit Reviewed(1, agent, buyer, 5, 0x0b, keccak256("review document"));
        vm.prank(buyer);
        board.review(1, 5, 0x0b, keccak256("review document"));
        assertTrue(board.reviewed(1));
        assertEq(board.ratingFrom(agent, buyer), 5);
        (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
        assertEq(reviewers, 1);
        assertEq(stars, 5);
    }

    function test_aHolderCountsOncePerAgentHoweverOftenTheyHire() public {
        // Ten cheap hires from one person are still one person's opinion.
        vm.startPrank(buyer);
        board.review(1, 5, 0, bytes32(0));
        for (uint256 id = 2; id <= 10; id++) {
            escrow.put(id, buyer, agent, PRICE, COMPLETED, 1_700_000_000 + id);
            board.review(id, 5, 0, bytes32(0));
        }
        vm.stopPrank();
        (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
        assertEq(reviewers, 1);
        assertEq(stars, 5);
    }

    function test_aHoldersLatestReviewIsTheirRating() public {
        escrow.put(2, buyer, agent, PRICE, REJECTED, 1_700_000_200);
        vm.startPrank(buyer);
        board.review(1, 5, 0, bytes32(0));
        board.review(2, 2, 0, bytes32(0));
        vm.stopPrank();
        assertEq(board.ratingFrom(agent, buyer), 2);
        (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
        assertEq(reviewers, 1);
        assertEq(stars, 2);
    }

    function test_eachHolderCountsOnce() public {
        address second = address(0xB1);
        ids.give(second);
        escrow.put(2, second, agent, PRICE, COMPLETED, 1_700_000_300);
        vm.prank(buyer);
        board.review(1, 4, 0, bytes32(0));
        vm.prank(second);
        board.review(2, 2, 0, bytes32(0));
        (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
        assertEq(reviewers, 2);
        assertEq(stars, 6);
    }

    function test_aHoldersRatingsAreKeptPerAgent() public {
        address otherAgent = address(0xA7);
        escrow.put(2, buyer, otherAgent, PRICE, COMPLETED, 1_700_000_400);
        vm.startPrank(buyer);
        board.review(1, 5, 0, bytes32(0));
        board.review(2, 1, 0, bytes32(0));
        vm.stopPrank();
        assertEq(board.ratingFrom(agent, buyer), 5);
        assertEq(board.ratingFrom(otherAgent, buyer), 1);
        (uint64 reviewers, uint64 stars) = board.ratingOf(otherAgent);
        assertEq(reviewers, 1);
        assertEq(stars, 1);
    }

    function test_onlyAnAgentIdHolderMayReview() public {
        escrow.put(3, stranger, agent, PRICE, COMPLETED, 1);
        vm.prank(stranger);
        vm.expectRevert(PokterBoard.NotAgentIdHolder.selector);
        board.review(3, 5, 0, bytes32(0));
    }

    function test_onlyTheJobsFunderMayReview() public {
        address other = address(0x07);
        ids.give(other);
        vm.prank(other);
        vm.expectRevert(PokterBoard.NotJobClient.selector);
        board.review(1, 1, 0, bytes32(0));
    }

    function test_aJobIsReviewedOnce() public {
        vm.startPrank(buyer);
        board.review(1, 5, 0, bytes32(0));
        vm.expectRevert(PokterBoard.AlreadyReviewed.selector);
        board.review(1, 1, 0, bytes32(0));
        vm.stopPrank();
    }

    function test_anAgentCannotReviewItself() public {
        escrow.put(4, buyer, buyer, PRICE, COMPLETED, 1);
        vm.prank(buyer);
        vm.expectRevert(PokterBoard.SelfReview.selector);
        board.review(4, 5, 0, bytes32(0));
    }

    function test_aFreeJobIsNotReviewable() public {
        escrow.put(5, buyer, agent, 0, COMPLETED, 1);
        vm.prank(buyer);
        vm.expectRevert(PokterBoard.UnpaidJob.selector);
        board.review(5, 5, 0, bytes32(0));
    }

    function test_onlyAnEndedJobIsReviewable() public {
        uint8[3] memory live = [OPEN, FUNDED, SUBMITTED];
        for (uint256 i = 0; i < live.length; i++) {
            escrow.put(10 + i, buyer, agent, PRICE, live[i], live[i] == SUBMITTED ? 1 : 0);
            vm.prank(buyer);
            vm.expectRevert(abi.encodeWithSelector(PokterBoard.JobNotEnded.selector, live[i]));
            board.review(10 + i, 3, 0, bytes32(0));
        }
    }

    function test_aJobTheAgentNeverDeliveredToIsNotReviewable() public {
        // A client can fund a job naming any agent, let it lapse and take the money back; the agent
        // may never have seen it. A client can also reject an open job it never funded.
        uint8[3] memory ended = [COMPLETED, REJECTED, EXPIRED];
        for (uint256 i = 0; i < ended.length; i++) {
            escrow.put(20 + i, buyer, agent, PRICE, ended[i], 0);
            vm.prank(buyer);
            vm.expectRevert(PokterBoard.NothingDelivered.selector);
            board.review(20 + i, 1, 0, bytes32(0));
        }
        (uint64 reviewers,) = board.ratingOf(agent);
        assertEq(reviewers, 0);
    }

    function test_aRejectionOrRefundAfterADeliveryIsReviewable() public {
        escrow.put(23, buyer, agent, PRICE, REJECTED, 1_700_000_200);
        escrow.put(24, buyer, address(0xA8), PRICE, EXPIRED, 1_700_000_300);
        vm.startPrank(buyer);
        board.review(23, 1, 0x00, bytes32(0));
        board.review(24, 2, 0x0c, bytes32(0));
        vm.stopPrank();
        assertTrue(board.reviewed(23));
        assertTrue(board.reviewed(24));
    }

    function testFuzz_starsAreOneToFive(uint8 rating) public {
        vm.prank(buyer);
        if (rating == 0 || rating > 5) {
            vm.expectRevert(PokterBoard.RatingOutOfRange.selector);
            board.review(1, rating, 0, bytes32(0));
        } else {
            board.review(1, rating, 0, bytes32(0));
            (, uint64 stars) = board.ratingOf(agent);
            assertEq(stars, rating);
        }
    }

    function testFuzz_flagsUseFourBits(uint8 flags) public {
        vm.prank(buyer);
        if (flags > 0x0f) {
            vm.expectRevert(PokterBoard.FlagsOutOfRange.selector);
            board.review(1, 3, flags, bytes32(0));
        } else {
            board.review(1, 3, flags, bytes32(0));
        }
    }

    function testFuzz_aRepeatBuyersRatingIsTheirLastReview(uint8[6] memory ratings) public {
        vm.startPrank(buyer);
        for (uint256 i = 0; i < ratings.length; i++) {
            uint8 rating = uint8(bound(ratings[i], 1, 5));
            uint256 id = 100 + i;
            escrow.put(id, buyer, agent, PRICE, COMPLETED, 1_700_000_000 + id);
            board.review(id, rating, 0, bytes32(0));
            (uint64 reviewers, uint64 stars) = board.ratingOf(agent);
            assertEq(reviewers, 1);
            assertEq(stars, rating);
        }
        vm.stopPrank();
    }

    function test_aHolderPostsAndClosesARequest() public {
        uint64 expiresAt = uint64(block.timestamp + 3 days);
        vm.expectEmit(address(board));
        emit RequestPosted(1, buyer, keccak256("brief"), expiresAt);
        vm.prank(buyer);
        uint256 id = board.postRequest(keccak256("brief"), expiresAt);
        assertEq(id, 1);
        assertEq(board.requestCount(), 1);
        (address poster, uint64 storedExpiry, bool closed) = board.requests(id);
        assertEq(poster, buyer);
        assertEq(storedExpiry, expiresAt);
        assertFalse(closed);

        vm.expectEmit(address(board));
        emit RequestClosed(1);
        vm.prank(buyer);
        board.closeRequest(id);
        (,, closed) = board.requests(id);
        assertTrue(closed);
    }

    function test_requestsNeedAnAgentIdABriefAndAFutureExpiry() public {
        vm.prank(stranger);
        vm.expectRevert(PokterBoard.NotAgentIdHolder.selector);
        board.postRequest(keccak256("brief"), uint64(block.timestamp + 1));

        vm.startPrank(buyer);
        vm.expectRevert(PokterBoard.EmptyBrief.selector);
        board.postRequest(bytes32(0), uint64(block.timestamp + 1));
        vm.expectRevert(PokterBoard.ExpiryNotInFuture.selector);
        board.postRequest(keccak256("brief"), uint64(block.timestamp));
        vm.stopPrank();
    }

    function test_onlyThePosterClosesARequestAndOnlyOnce() public {
        vm.prank(buyer);
        uint256 id = board.postRequest(keccak256("brief"), uint64(block.timestamp + 1 days));
        vm.prank(stranger);
        vm.expectRevert(PokterBoard.NotRequestPoster.selector);
        board.closeRequest(id);
        vm.startPrank(buyer);
        board.closeRequest(id);
        vm.expectRevert(PokterBoard.RequestAlreadyClosed.selector);
        board.closeRequest(id);
        vm.stopPrank();
    }

    function test_holdsNoFundsAndHasNoOwner() public {
        // Plain BNB sent to the board is refused: it has no receive or fallback.
        vm.deal(buyer, 1 ether);
        vm.prank(buyer);
        (bool ok,) = address(board).call{value: 1 wei}("");
        assertFalse(ok);
        assertEq(address(board).balance, 0);
        // The only state-changing entry points are review, postRequest and closeRequest; there is no owner().
        (bool hasOwner,) = address(board).staticcall(abi.encodeWithSignature("owner()"));
        assertFalse(hasOwner);
    }
}
