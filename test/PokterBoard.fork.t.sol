// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PokterBoard, IAgentId, IAgenticCommerce} from "../src/PokterBoard.sol";

/// @notice Against BNB Chain mainnet as it is: the deployed escrow's `getJob` layout and the real
/// Agent ID registry. Runs when BSC_RPC_URL is set (`forge test --fork-url` is not needed); skipped otherwise.
/// The jobs used are settled or refunded, and an Agent ID cannot move, so the facts below do not change.
contract PokterBoardForkTest is Test {
    IAgentId constant AGENT_ID = IAgentId(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    IAgenticCommerce constant ESCROW = IAgenticCommerce(0xEa4DAa3100A767e86FDed867729ae7446476EBA6);

    /// @dev Holds an Agent ID and funded jobs 57067-57069, each completed with a delivery.
    address constant HOLDER = 0x7751bE7B2BA4141D5E32Ef14e9E5cc73e9D7bf0C;
    address constant PROVIDER_57067 = 0x81762d5214fCB6fB3b102beF9D69d13A56c1a2d0;
    /// @dev Funded job 57206, completed; holds no Agent ID.
    address constant NON_HOLDER = 0xC5A17B5295Fc50BAdB1F9f9C09b412fE5e84F7d3;

    PokterBoard board;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        board = new PokterBoard(AGENT_ID, ESCROW);
    }

    function test_theDeployedEscrowReturnsJobsInTheLayoutTheBoardReads() public view {
        IAgenticCommerce.Job memory job = ESCROW.getJob(57067);
        assertEq(job.id, 57067);
        assertEq(job.client, HOLDER);
        assertEq(job.provider, PROVIDER_57067);
        assertEq(job.budget, 0.01 ether);
        assertEq(job.status, 3, "completed");
        assertEq(job.submittedAt, 1792844269);

        IAgenticCommerce.Job memory rejected = ESCROW.getJob(56879);
        assertEq(rejected.status, 4, "rejected");
        assertEq(rejected.submittedAt, 0, "with nothing delivered");
        assertEq(rejected.budget, 0.15 ether);
    }

    function test_aRealHolderReviewsARealJobItFunded() public {
        assertGt(AGENT_ID.balanceOf(HOLDER), 0);
        vm.prank(HOLDER);
        board.review(57067, 5, 0x0b, bytes32(0));
        (uint64 reviews, uint64 stars) = board.ratingOf(PROVIDER_57067);
        assertEq(reviews, 1);
        assertEq(stars, 5);

        vm.prank(HOLDER);
        vm.expectRevert(PokterBoard.AlreadyReviewed.selector);
        board.review(57067, 1, 0, bytes32(0));
    }

    function test_aFunderWithoutAnAgentIdCannotReview() public {
        assertEq(AGENT_ID.balanceOf(NON_HOLDER), 0);
        vm.prank(NON_HOLDER);
        vm.expectRevert(PokterBoard.NotAgentIdHolder.selector);
        board.review(57206, 5, 0, bytes32(0));
    }

    function test_aHolderCannotReviewSomeoneElsesJob() public {
        vm.prank(HOLDER);
        vm.expectRevert(PokterBoard.NotJobClient.selector);
        board.review(57206, 1, 0, bytes32(0));
    }
}
