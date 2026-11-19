// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/AgentBadges.sol";

/// @notice Minimal mock of the Agent ID ERC-721: balanceOf + mint only.
///         Deliberately does NOT implement ERC721Enumerable, like the real
///         Agent ID contract (tokenOfOwnerByIndex / totalSupply revert there).
contract MockAgentId {
    mapping(address => uint256) private _bal;

    function mint(address to) external {
        _bal[to] += 1;
    }

    function balanceOf(address owner) external view returns (uint256) {
        return _bal[owner];
    }
}

contract AgentBadgesTest is Test {
    AgentBadges public badges;
    MockAgentId public agentId;

    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA901);

    // Realistic "today": 2026-11-19 00:00 UTC.
    uint256 public constant DAY0 = 1795065600;

    function setUp() public {
        agentId = new MockAgentId();
        badges = new AgentBadges(address(agentId));
        agentId.mint(alice);
        agentId.mint(bob);
        // carol is NOT an Agent ID holder.
        vm.deal(alice, 10 ether);
        vm.deal(bob, 10 ether);
        vm.deal(carol, 10 ether);
        vm.warp(DAY0);
    }

    // ------------------------------------------------------------------------
    // Gating: non-holders cannot do anything
    // ------------------------------------------------------------------------
    function testNonHolderCannotGm() public {
        vm.prank(carol);
        vm.expectRevert(AgentBadges.NotAgentIdHolder.selector);
        badges.gm();
    }

    function testNonHolderCannotClaim() public {
        vm.prank(carol);
        vm.expectRevert(AgentBadges.NotAgentIdHolder.selector);
        badges.claimBadge(1);
    }

    function testNonHolderCannotTip() public {
        vm.prank(carol);
        vm.expectRevert(AgentBadges.NotAgentIdHolder.selector);
        badges.tip{value: 0.001 ether}(alice);
    }

    // ------------------------------------------------------------------------
    // GM + streaks
    // ------------------------------------------------------------------------
    function testGmOncePerDayOnly() public {
        vm.prank(alice);
        badges.gm();
        assertEq(badges.gmStreak(alice), 1);

        vm.prank(alice);
        vm.expectRevert(AgentBadges.AlreadyCheckedInToday.selector);
        badges.gm();
    }

    function testStreakCountsDistinctDays() public {
        vm.prank(alice);
        badges.gm();
        vm.warp(DAY0 + 1 days);
        vm.prank(alice);
        badges.gm();
        vm.warp(DAY0 + 2 days);
        vm.prank(alice);
        badges.gm();
        assertEq(badges.gmStreak(alice), 3);
        assertEq(badges.totalGmDays(alice), 3);
    }

    function testStreakResetsAfterMissedDay() public {
        vm.prank(alice);
        badges.gm(); // day 0, streak 1
        vm.warp(DAY0 + 2 days); // skipped a day
        vm.prank(alice);
        badges.gm();
        assertEq(badges.gmStreak(alice), 1);
        assertEq(badges.totalGmDays(alice), 2);
    }

    function testGmEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(badges));
        emit AgentBadges.GM(alice, DAY0 / 1 days, 1);
        badges.gm();
    }

    // ------------------------------------------------------------------------
    // Badge 1-3 (GM quests)
    // ------------------------------------------------------------------------
    function testClaimFirstGmAfterOneGm() public {
        vm.prank(alice);
        badges.gm();
        vm.prank(alice);
        badges.claimBadge(1);
        assertTrue(badges.hasBadge(alice, 1));
        assertEq(badges.balanceOf(alice), 1);
    }

    function testClaimFirstGmRequiresGm() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.QuestNotComplete.selector);
        badges.claimBadge(1);
    }

    function testClaimStreak3AfterThreeDays() public {
        _gmDays(alice, 3);
        vm.prank(alice);
        badges.claimBadge(2);
        assertTrue(badges.hasBadge(alice, 2));
    }

    function testClaimStreak3FailsAtTwoDays() public {
        _gmDays(alice, 2);
        vm.prank(alice);
        vm.expectRevert(AgentBadges.QuestNotComplete.selector);
        badges.claimBadge(2);
    }

    function testClaimStreak7AfterSevenDays() public {
        _gmDays(alice, 7);
        vm.prank(alice);
        badges.claimBadge(3);
        assertTrue(badges.hasBadge(alice, 3));
    }

    function testClaimStreak7FailsAtSixDays() public {
        _gmDays(alice, 6);
        vm.prank(alice);
        vm.expectRevert(AgentBadges.QuestNotComplete.selector);
        badges.claimBadge(3);
    }

    // ------------------------------------------------------------------------
    // Tips (badge 4)
    // ------------------------------------------------------------------------
    function testTipForwardsExactAmount() public {
        uint256 bobBefore = bob.balance;
        vm.prank(alice);
        badges.tip{value: 0.001 ether}(bob);
        assertEq(bob.balance - bobBefore, 0.001 ether);
        assertEq(address(badges).balance, 0, "contract must keep nothing");
        assertTrue(badges.hasTipped(alice));
    }

    function testTipMinimumAmount() public {
        vm.prank(alice);
        badges.tip{value: 0.0001 ether}(bob);
        assertTrue(badges.hasTipped(alice));
    }

    function testTipBelowMinimumReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.TipTooSmall.selector);
        badges.tip{value: 0.000099 ether}(bob);
    }

    function testTipOnlyToAgentIdHolders() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.RecipientNotAgentIdHolder.selector);
        badges.tip{value: 0.001 ether}(carol);
    }

    function testTipCannotTipSelf() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.CannotTipSelf.selector);
        badges.tip{value: 0.001 ether}(alice);
    }

    function testClaimFirstTipAfterTipping() public {
        vm.prank(alice);
        badges.tip{value: 0.001 ether}(bob);
        vm.prank(alice);
        badges.claimBadge(4);
        assertTrue(badges.hasBadge(alice, 4));
    }

    function testClaimFirstTipRequiresTip() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.QuestNotComplete.selector);
        badges.claimBadge(4);
    }

    function testTipEmitsEvent() public {
        vm.prank(alice);
        vm.expectEmit(true, true, false, true, address(badges));
        emit AgentBadges.Tip(alice, bob, 0.001 ether);
        badges.tip{value: 0.001 ether}(bob);
    }

    // ------------------------------------------------------------------------
    // Collector (badge 5) + one-claim rule
    // ------------------------------------------------------------------------
    function testCollectorRequiresThreeBadges() public {
        _gmDays(alice, 3);
        vm.prank(alice);
        badges.claimBadge(1);
        vm.prank(alice);
        badges.claimBadge(2);
        // Only 2 badges so far.
        vm.prank(alice);
        vm.expectRevert(AgentBadges.QuestNotComplete.selector);
        badges.claimBadge(5);

        vm.prank(alice);
        badges.tip{value: 0.001 ether}(bob);
        vm.prank(alice);
        badges.claimBadge(4);
        // Now 3 badges -> Collector works.
        vm.prank(alice);
        badges.claimBadge(5);
        assertTrue(badges.hasBadge(alice, 5));
        assertEq(badges.badgeCount(alice), 4);
    }

    function testEachBadgeClaimableOnce() public {
        vm.prank(alice);
        badges.gm();
        vm.prank(alice);
        badges.claimBadge(1);
        vm.prank(alice);
        vm.expectRevert(AgentBadges.BadgeAlreadyClaimed.selector);
        badges.claimBadge(1);
    }

    function testInvalidBadgeIdReverts() public {
        vm.prank(alice);
        vm.expectRevert(AgentBadges.InvalidBadge.selector);
        badges.claimBadge(0);
        vm.prank(alice);
        vm.expectRevert(AgentBadges.InvalidBadge.selector);
        badges.claimBadge(6);
    }

    // ------------------------------------------------------------------------
    // Soulbound
    // ------------------------------------------------------------------------
    function testTransferReverts() public {
        vm.prank(alice);
        badges.gm();
        vm.prank(alice);
        badges.claimBadge(1);
        uint256 tokenId = 1;

        vm.prank(alice);
        vm.expectRevert(AgentBadges.Soulbound.selector);
        badges.transferFrom(alice, bob, tokenId);

        vm.prank(alice);
        vm.expectRevert(AgentBadges.Soulbound.selector);
        badges.safeTransferFrom(alice, bob, tokenId);
    }

    function testApproveReverts() public {
        vm.prank(alice);
        badges.gm();
        vm.prank(alice);
        badges.claimBadge(1);

        vm.prank(alice);
        vm.expectRevert(AgentBadges.Soulbound.selector);
        badges.approve(bob, 1);

        vm.prank(alice);
        vm.expectRevert(AgentBadges.Soulbound.selector);
        badges.setApprovalForAll(bob, true);

        assertEq(badges.getApproved(1), address(0));
        assertFalse(badges.isApprovedForAll(alice, bob));
    }

    // ------------------------------------------------------------------------
    // Views + metadata
    // ------------------------------------------------------------------------
    function testBadgesOfAndViews() public {
        _gmDays(alice, 3);
        vm.prank(alice);
        badges.claimBadge(1);
        vm.prank(alice);
        badges.claimBadge(2);

        uint256[] memory owned = badges.badgesOf(alice);
        assertEq(owned.length, 2);
        assertEq(owned[0], 1);
        assertEq(owned[1], 2);
        assertEq(badges.badgeCount(alice), 2);
        assertEq(badges.ownerOf(1), alice);
        assertEq(badges.tokenBadge(1), 1);
        assertEq(badges.tokenBadge(2), 2);
        assertTrue(badges.isAgentIdHolder(alice));
        assertFalse(badges.isAgentIdHolder(carol));
    }

    function testTokenUriIsDataUri() public {
        vm.prank(alice);
        badges.gm();
        vm.prank(alice);
        badges.claimBadge(1);
        string memory uri = badges.tokenURI(1);
        bytes memory prefix = bytes("data:application/json;base64,");
        bytes memory uriBytes = bytes(uri);
        for (uint256 i = 0; i < prefix.length; i++) {
            assertEq(uriBytes[i], prefix[i]);
        }
        assertGt(uriBytes.length, prefix.length + 50);
    }

    function testTokenUriNonexistentReverts() public {
        vm.expectRevert(AgentBadges.NonexistentToken.selector);
        badges.tokenURI(999);
    }

    function testSupportsInterface() public view {
        assertTrue(badges.supportsInterface(0x01ffc9a7)); // ERC165
        assertTrue(badges.supportsInterface(0x80ac58cd)); // ERC721
        assertTrue(badges.supportsInterface(0x5b5e139f)); // ERC721Metadata
        assertFalse(badges.supportsInterface(0x12345678));
    }

    function testContractNeverHoldsTips() public {
        // 10 tips of various sizes: contract balance stays 0 throughout.
        for (uint256 i = 0; i < 10; i++) {
            vm.prank(alice);
            badges.tip{value: 0.0001 ether + i}(bob);
            assertEq(address(badges).balance, 0);
        }
    }

    // ------------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------------
    /// @notice GM for `user` on `n` consecutive days starting at DAY0.
    function _gmDays(address user, uint256 n) internal {
        for (uint256 i = 0; i < n; i++) {
            vm.warp(DAY0 + i * 1 days);
            vm.prank(user);
            badges.gm();
        }
    }
}
