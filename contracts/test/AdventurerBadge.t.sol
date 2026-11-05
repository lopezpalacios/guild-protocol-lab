// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Test} from "forge-std/Test.sol";
import {AdventurerBadge} from "../src/AdventurerBadge.sol";
import {B64} from "./utils/B64.sol";

/// @notice Encounter E3/E9. The souvenir must be self-contained.
contract AdventurerBadgeTest is Test {
    AdventurerBadge badge;

    address alice = address(0xA11CE);

    function setUp() public {
        badge = new AdventurerBadge(address(this));
    }

    function test_claim() public {
        vm.prank(alice);
        uint256 id = badge.claim(7, hex"0102050709");

        assertEq(id, 1);
        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.guildOf(1), 7);
        assertTrue(badge.hasClaimed(alice));
    }

    function test_onePerAddress() public {
        vm.startPrank(alice);
        badge.claim(7, hex"01");
        vm.expectRevert(AdventurerBadge.AlreadyClaimed.selector);
        badge.claim(7, hex"01");
        vm.stopPrank();
    }

    function test_tokenUriIsSelfContained() public {
        vm.prank(alice);
        badge.claim(3, hex"0102030405");

        string memory uri = badge.tokenURI(1);

        // data URI, no ipfs://, no https:// anywhere.
        assertTrue(_startsWith(uri, "data:application/json;base64,"));
        assertFalse(_contains(uri, "ipfs"));
        assertFalse(_contains(uri, "https"));

        // Decode the JSON and prove the image is inlined SVG.
        string memory json = string(B64.decode(_stripPrefix(uri, 29)));
        assertTrue(_contains(json, '"name":"Guild Protocol Adventurer #1"'));
        assertTrue(_contains(json, '"trait_type":"Guild","value":3'));

        string memory svg = _extractSvg(json);
        assertTrue(_contains(svg, "<svg"));
        assertTrue(_contains(svg, "G03"));
    }

    function test_routeAffectsMetadata() public {
        vm.prank(alice);
        badge.claim(3, hex"0102");
        string memory a = badge.tokenURI(1);

        vm.prank(address(0xB0B));
        badge.claim(3, hex"0102030405");
        string memory b = badge.tokenURI(2);

        assertTrue(keccak256(bytes(a)) != keccak256(bytes(b)));
    }

    function test_operatorCanMintOnBehalf() public {
        uint256 id = badge.claimFor(address(0xB0B), 4, hex"0102");
        assertEq(id, 1);
        assertEq(badge.ownerOf(1), address(0xB0B));
        assertTrue(badge.hasClaimed(address(0xB0B)));
    }

    function test_nonOperatorCannotMintOnBehalf() public {
        vm.prank(address(0xB0B));
        vm.expectRevert(AdventurerBadge.NotOperator.selector);
        badge.claimFor(address(0xB0B), 4, hex"0102");
    }

    function test_rejectsOverlongRoute() public {
        vm.prank(alice);
        vm.expectRevert(AdventurerBadge.RouteTooLong.selector);
        badge.claim(1, hex"0102030405060708090a0b0c0d");
    }

    function test_supplyCap() public {
        for (uint256 i = 0; i < 250; i++) {
            vm.prank(address(uint160(i + 1000)));
            badge.claim(uint8((i % 25) + 1), hex"0102");
        }
        assertEq(badge.nextId(), 251);

        vm.prank(address(0xDEAD));
        vm.expectRevert(AdventurerBadge.SoldOut.selector);
        badge.claim(1, hex"01");
    }

    // ------------------------------------------------------------------ helpers

    function _startsWith(string memory s, string memory prefix) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(prefix);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i < b.length; i++) {
            if (a[i] != b[i]) return false;
        }
        return true;
    }

    function _contains(string memory s, string memory needle) internal pure returns (bool) {
        bytes memory a = bytes(s);
        bytes memory b = bytes(needle);
        if (b.length > a.length) return false;
        for (uint256 i = 0; i <= a.length - b.length; i++) {
            bool ok = true;
            for (uint256 j = 0; j < b.length; j++) {
                if (a[i + j] != b[j]) {
                    ok = false;
                    break;
                }
            }
            if (ok) return true;
        }
        return false;
    }

    function _stripPrefix(string memory s, uint256 n) internal pure returns (string memory) {
        bytes memory a = bytes(s);
        bytes memory out = new bytes(a.length - n);
        for (uint256 i = 0; i < out.length; i++) {
            out[i] = a[i + n];
        }
        return string(out);
    }

    function _extractSvg(string memory json) internal pure returns (string memory) {
        bytes memory d = bytes(json);
        uint256 start;
        bool found;
        for (uint256 i = 0; i + 7 < d.length; i++) {
            if (
                d[i] == "b" && d[i + 1] == "a" && d[i + 2] == "s" && d[i + 3] == "e"
                    && d[i + 4] == "6" && d[i + 5] == "4" && d[i + 6] == ","
            ) {
                start = i + 7;
                found = true;
                break;
            }
        }
        require(found, "no base64 marker");

        uint256 end = start;
        while (end < d.length && d[end] != '"') end++;

        bytes memory b64 = new bytes(end - start);
        for (uint256 i = 0; i < b64.length; i++) {
            b64[i] = d[start + i];
        }
        return string(B64.decode(string(b64)));
    }
}
