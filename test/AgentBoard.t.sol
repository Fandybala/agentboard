// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AgentBoard} from "../src/AgentBoard.sol";
import {MockAgentId} from "./MockAgentId.sol";

contract AgentBoardTest is Test {
    MockAgentId internal agentId;
    AgentBoard internal board;

    address internal alice = address(0xA11CE);
    address internal bob = address(0xB0B);
    address internal carol = address(0xCA401);
    address internal stranger = address(0x57A9);

    function setUp() public {
        agentId = new MockAgentId();
        board = new AgentBoard(address(agentId));
        agentId.mint(alice);
        agentId.mint(bob);
        agentId.mint(carol);
        vm.warp(1_700_000_000); // a fixed "today"
    }

    // ---------------- gate ----------------

    function test_NonHolderCannotPost() public {
        vm.prank(stranger);
        vm.expectRevert(AgentBoard.NotAgentIdHolder.selector);
        board.postIntent("hello");
    }

    function test_NonHolderCannotCheckInOrVouch() public {
        vm.prank(alice);
        uint256 id = board.postIntent("alice intent");

        vm.prank(stranger);
        vm.expectRevert(AgentBoard.NotAgentIdHolder.selector);
        board.checkIn();

        vm.prank(stranger);
        vm.expectRevert(AgentBoard.NotAgentIdHolder.selector);
        board.vouch(id);
    }

    function test_IsHolder() public view {
        assertTrue(board.isHolder(alice));
        assertFalse(board.isHolder(stranger));
    }

    // ---------------- intents ----------------

    function test_PostAndReadIntent() public {
        vm.prank(alice);
        uint256 id = board.postIntent("My agent audits Solidity. Need: design help.");
        assertEq(id, 0);
        assertEq(board.intentCount(), 1);

        AgentBoard.Intent memory intent = board.getIntent(id);
        assertEq(intent.author, alice);
        assertEq(intent.text, "My agent audits Solidity. Need: design help.");
        assertTrue(intent.active);
        assertEq(intent.vouchCount, 0);

        (bool found, uint256 refId, bool active) = board.intentOf(alice);
        assertTrue(found);
        assertEq(refId, id);
        assertTrue(active);
    }

    function test_SecondActiveIntentReverts_ThenUpdateWorks() public {
        vm.startPrank(alice);
        board.postIntent("first");
        vm.expectRevert(AgentBoard.IntentAlreadyActive.selector);
        board.postIntent("second");
        board.updateIntent("first, revised");
        vm.stopPrank();

        assertEq(board.getIntent(0).text, "first, revised");
        assertEq(board.intentCount(), 1);
    }

    function test_DeactivateThenRepost() public {
        vm.startPrank(alice);
        board.postIntent("v1");
        board.deactivateIntent();
        (bool found,, bool active) = board.intentOf(alice);
        assertTrue(found);
        assertFalse(active);

        uint256 id2 = board.postIntent("v2");
        vm.stopPrank();
        assertEq(id2, 1);
        assertTrue(board.getIntent(id2).active);
    }

    function test_UpdateWithoutIntentReverts() public {
        vm.prank(bob);
        vm.expectRevert(AgentBoard.NoActiveIntent.selector);
        board.updateIntent("nothing to update");
    }

    function test_TextValidation() public {
        vm.startPrank(alice);
        vm.expectRevert(AgentBoard.EmptyText.selector);
        board.postIntent("");
        string memory tooLong = new string(281);
        vm.expectRevert(
            abi.encodeWithSelector(AgentBoard.TextTooLong.selector, 281, 280)
        );
        board.postIntent(tooLong);
        vm.stopPrank();
    }

    // ---------------- check-in ----------------

    function test_CheckInStreakAcrossDays() public {
        vm.startPrank(alice);
        assertEq(board.checkIn(), 1);
        vm.expectRevert(AgentBoard.AlreadyCheckedInToday.selector);
        board.checkIn();

        vm.warp(block.timestamp + 1 days);
        assertEq(board.checkIn(), 2);

        vm.warp(block.timestamp + 1 days);
        assertEq(board.checkIn(), 3);

        // Miss a day: streak restarts at 1, totals keep counting.
        vm.warp(block.timestamp + 2 days);
        assertEq(board.checkIn(), 1);
        vm.stopPrank();

        assertEq(board.streakOf(alice), 1);
        assertEq(board.totalCheckInsOf(alice), 4);
        assertTrue(board.hasCheckedInToday(alice));
    }

    // ---------------- vouch ----------------

    function test_VouchRules() public {
        vm.prank(alice);
        uint256 id = board.postIntent("vouch for me");

        vm.prank(alice);
        vm.expectRevert(AgentBoard.CannotVouchOwnIntent.selector);
        board.vouch(id);

        vm.prank(bob);
        board.vouch(id);
        assertEq(board.getIntent(id).vouchCount, 1);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(AgentBoard.AlreadyVouched.selector, id)
        );
        board.vouch(id);

        vm.prank(carol);
        board.vouch(id);
        assertEq(board.getIntent(id).vouchCount, 2);
    }

    function test_VouchInactiveOrMissingReverts() public {
        vm.prank(alice);
        uint256 id = board.postIntent("short lived");
        vm.prank(alice);
        board.deactivateIntent();

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(AgentBoard.IntentInactive.selector, id)
        );
        board.vouch(id);

        vm.prank(bob);
        vm.expectRevert(
            abi.encodeWithSelector(AgentBoard.IntentNotFound.selector, 99)
        );
        board.vouch(99);
    }

    // ---------------- unique interactors ----------------

    function test_UniqueInteractorsCountedOnce() public {
        assertEq(board.uniqueInteractors(), 0);

        vm.prank(alice);
        board.postIntent("a");
        assertEq(board.uniqueInteractors(), 1);

        vm.prank(alice);
        board.checkIn();
        assertEq(board.uniqueInteractors(), 1); // same holder, still 1

        vm.prank(bob);
        board.vouch(0);
        assertEq(board.uniqueInteractors(), 2);

        vm.prank(carol);
        board.checkIn();
        assertEq(board.uniqueInteractors(), 3);
        assertTrue(board.hasInteracted(carol));
        assertFalse(board.hasInteracted(stranger));
    }
}
