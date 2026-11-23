// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Script, console} from "forge-std/Script.sol";
import {PokterBoard, IAgentId, IAgenticCommerce} from "../src/PokterBoard.sol";

/// @notice Deploys PokterBoard on BNB Chain mainnet against the Agent ID registry, the ERC-8183 escrow and its router.
/// The signer comes from the command line (`--account`, `--ledger`), never from this file or the environment.
contract Deploy is Script {
    IAgentId constant AGENT_ID = IAgentId(0x60B9262456dE011F7d15a54CdD8c48bAaa8B022F);
    IAgenticCommerce constant ESCROW = IAgenticCommerce(0xEa4DAa3100A767e86FDed867729ae7446476EBA6);
    /// @dev The escrow's router, the evaluator whose dispute policy decides a rejection.
    address constant ROUTER = 0x51895229E12F9876011789B04f8698af06cCD6DA;

    function run() external returns (PokterBoard board) {
        require(block.chainid == 56, "BNB Chain mainnet only: the Agent ID registry is there");
        vm.startBroadcast();
        board = new PokterBoard(AGENT_ID, ESCROW, ROUTER);
        vm.stopBroadcast();
        console.log("PokterBoard", address(board));
    }
}
