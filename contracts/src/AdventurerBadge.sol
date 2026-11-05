// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Base64} from "@openzeppelin/contracts/utils/Base64.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

/// @title AdventurerBadge
/// @notice Encounter E3/E9. The souvenir, and the only artefact that proves which route *this*
///         room took. Two badges from two sessions are provably different objects.
///
/// @dev The metadata is fully on-chain: an SVG built in the contract and base64-encoded into a
///      data URI. No IPFS CID, no pinning service, no arweave endowment. That is the teaching
///      point of E3 — a token that points at a URL someone else controls is not the same asset
///      as a token that contains its own artwork, and the difference only shows up when the
///      someone else stops paying.
contract AdventurerBadge is ERC721 {
    uint256 public constant MAX_SUPPLY = 250;

    uint256 public nextId = 1;

    mapping(address => bool) public hasClaimed;
    mapping(uint256 => uint8) public guildOf;
    mapping(uint256 => bytes) public routeOf;

    /// @notice Cold-key fallback operator. Exists so that if sponsorship fails on the night,
    ///         one funded wallet can mint on behalf of the room instead of 200 people failing
    ///         in public. It is a centralisation we accept and state out loud.
    address public immutable operator;

    event BadgeClaimed(uint256 indexed tokenId, address indexed holder, uint8 guildId, bytes route);

    error AlreadyClaimed();
    error SoldOut();
    error RouteTooLong();
    error BadGuild();
    error NotOperator();

    constructor(address operator_) ERC721("Guild Protocol Adventurer", "GUILD") {
        operator = operator_;
    }

    /// @notice Claim your badge. One per address, first come, capped.
    /// @param guildId 1..25. Rendered on the badge.
    /// @param route Encounter ids visited by the room, in order, e.g. hex"0102050709".
    function claim(uint8 guildId, bytes calldata route) external returns (uint256 tokenId) {
        tokenId = _mintTo(msg.sender, guildId, route);
    }

    /// @notice Operator fallback: mint on behalf of an attendee whose sponsored claim failed.
    /// @dev Same rules, same cap, same one-per-address check. Only the caller differs.
    function claimFor(address to, uint8 guildId, bytes calldata route)
        external
        returns (uint256 tokenId)
    {
        if (msg.sender != operator) revert NotOperator();
        tokenId = _mintTo(to, guildId, route);
    }

    function _mintTo(address to, uint8 guildId, bytes calldata route)
        internal
        returns (uint256 tokenId)
    {
        if (hasClaimed[to]) revert AlreadyClaimed();
        if (nextId > MAX_SUPPLY) revert SoldOut();
        if (route.length > 12) revert RouteTooLong();
        if (guildId == 0) revert BadGuild();

        tokenId = nextId++;
        hasClaimed[to] = true;
        guildOf[tokenId] = guildId;
        routeOf[tokenId] = route;

        _safeMint(to, tokenId);

        emit BadgeClaimed(tokenId, to, guildId, route);
    }

    /// @notice Fully on-chain token URI. No external dependency of any kind.
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        _requireOwned(tokenId);

        string memory svg = _renderSVG(tokenId);
        string memory json = string.concat(
            '{"name":"Guild Protocol Adventurer #',
            Strings.toString(tokenId),
            '","description":"A 60-minute lab at ETH Zurich. This badge encodes the route the room actually took - no two sessions produce the same one. Testnet only.","image":"data:image/svg+xml;base64,',
            Base64.encode(bytes(svg)),
            '","attributes":[{"trait_type":"Guild","value":',
            Strings.toString(guildOf[tokenId]),
            '},{"trait_type":"Route","value":"',
            _routeString(tokenId),
            '"}]}'
        );

        return string.concat("data:application/json;base64,", Base64.encode(bytes(json)));
    }

    function _routeString(uint256 tokenId) internal view returns (string memory out) {
        bytes memory route = routeOf[tokenId];
        for (uint256 i = 0; i < route.length; i++) {
            out = string.concat(out, i == 0 ? "" : "-", Strings.toString(uint8(route[i])));
        }
    }

    function _renderSVG(uint256 tokenId) internal view returns (string memory) {
        bytes memory route = routeOf[tokenId];
        uint8 guild = guildOf[tokenId];

        // Route strip: one square per encounter visited, filled if visited.
        string memory strip;
        for (uint256 i = 0; i < 10; i++) {
            bool visited = i < route.length;
            uint256 x = 44 + i * 32;
            strip = string.concat(
                strip,
                '<rect x="',
                Strings.toString(x),
                '" y="352" width="20" height="20" rx="3" fill="',
                visited ? "#C8A24A" : "#0E1116",
                '" stroke="#C8A24A" stroke-width="1.5"/>'
            );
        }

        string memory guildLabel = string.concat("G", guild < 10 ? "0" : "", Strings.toString(guild));

        return string.concat(
            '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 480" width="400" height="480">',
            '<rect width="400" height="480" fill="#0E1116"/>',
            '<rect x="14" y="14" width="372" height="452" fill="none" stroke="#C8A24A" stroke-width="1.5"/>',
            '<text x="200" y="64" fill="#C8A24A" font-family="ui-monospace,monospace" font-size="13" letter-spacing="4" text-anchor="middle">THE GUILD PROTOCOL</text>',
            '<line x1="120" y1="82" x2="280" y2="82" stroke="#C8A24A" stroke-width="0.5"/>',
            '<text x="200" y="230" fill="#F2F0EA" font-family="ui-monospace,monospace" font-size="104" font-weight="300" text-anchor="middle">',
            guildLabel,
            "</text>",
            '<text x="200" y="272" fill="#8A8577" font-family="ui-monospace,monospace" font-size="12" letter-spacing="3" text-anchor="middle">ADVENTURER</text>',
            strip,
            '<text x="200" y="404" fill="#8A8577" font-family="ui-monospace,monospace" font-size="11" text-anchor="middle">',
            _routeString(tokenId),
            "</text>",
            '<text x="200" y="440" fill="#3D3A33" font-family="ui-monospace,monospace" font-size="9" letter-spacing="2" text-anchor="middle">BASE SEPOLIA - TESTNET ONLY</text>',
            "</svg>"
        );
    }
}
