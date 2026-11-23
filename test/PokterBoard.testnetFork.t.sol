// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {PokterBoard, IAgentId, IAgenticCommerce} from "../src/PokterBoard.sol";

/// @notice The take-it-back review, as it really happened on BNB Chain testnet: job 919's client named itself
/// evaluator, received a delivery, rejected it and was refunded in full. The board must refuse to let that
/// client review it. Runs when BSC_TESTNET_RPC_URL is set; skipped otherwise.
contract PokterBoardTestnetForkTest is Test {
    /// @dev The testnet escrow and router; its `getJob` layout is the mainnet one.
    IAgenticCommerce constant ESCROW = IAgenticCommerce(0xa206c0517B6371C6638CD9e4a42Cc9f02A33B0DE);
    address constant ROUTER = 0xD7d36D66d2F1B608A0F943f722D27e3744f66F25;
    /// @dev The Agent ID registry lives on mainnet only; here it is stood in, as if job 919's client held an ID.
    IAgentId constant AGENT_ID = IAgentId(address(0xA9E1D));
    address constant CLIENT_919 = 0x29BC3C8475eA9443D33D02032593C2087770EE62;

    PokterBoard board;

    function setUp() public {
        string memory rpc = vm.envOr("BSC_TESTNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            vm.skip(true);
            return;
        }
        vm.createSelectFork(rpc);
        board = new PokterBoard(AGENT_ID, ESCROW, ROUTER);
        vm.mockCall(
            address(AGENT_ID), abi.encodeWithSelector(IAgentId.balanceOf.selector, CLIENT_919), abi.encode(uint256(1))
        );
    }

    function test_aClientThatRejectedADeliveryAsItsOwnEvaluatorCannotReviewIt() public {
        IAgenticCommerce.Job memory job = ESCROW.getJob(919);
        assertEq(job.client, CLIENT_919);
        assertEq(job.evaluator, CLIENT_919, "the client named itself evaluator");
        assertEq(job.status, 4, "rejected");
        assertGt(job.submittedAt, 0, "after a delivery");
        assertGt(job.budget, 0);

        vm.prank(CLIENT_919);
        vm.expectRevert(PokterBoard.RejectedOutsidePolicy.selector);
        board.review(919, 1, 0, bytes32(0));
    }
}
