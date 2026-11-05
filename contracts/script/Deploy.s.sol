// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {LabToken} from "../src/LabToken.sol";
import {MerkleDistributor} from "../src/MerkleDistributor.sol";
import {AdventurerBadge} from "../src/AdventurerBadge.sol";
import {Ballot} from "../src/Ballot.sol";
import {LabPair} from "../src/LabPair.sol";
import {MerkleBuilder} from "../test/utils/MerkleBuilder.sol";

/// @notice Full deployment. Reads data/participants.json, writes deployments/<chainId>.json,
///         data/merkle.json and web/config.js. One command, one source of truth.
///
///   forge script script/Deploy.s.sol --rpc-url $BASE_SEPOLIA_RPC --broadcast --verify
///
/// @dev participants.json:
///      { "addresses": ["0x...", ...], "amounts": [1000000000000000000000, ...] }
///      Guild addresses must be derived from data/guild-keys.txt so the printed cards match.
contract Deploy is Script {
    uint256 constant SEED = 50_000e18;
    uint256 constant LOOT_PER_HEAD = 1_000e18;
    uint256 constant MAX_TRADE = 200e18;
    uint256 constant LOOT_CAP = 1_000_000e18;

    bytes32 constant POLL_1 = keccak256("E5vsE6");
    bytes32 constant POLL_2 = keccak256("E7vsE8");

    struct Cfg {
        uint256 chainId;
        string chainName;
        string rpcUrl;
        string explorer;
        address loot;
        address gold;
        address silver;
        address pair;
        address ballot;
        address badge;
        address distributor;
        bytes32 root;
    }

    function run() external {
        uint256 pk = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(pk);

        string memory pjson = vm.readFile("../data/participants.json");
        address[] memory addrs = vm.parseJsonAddressArray(pjson, ".addresses");
        uint256[] memory amounts = vm.parseJsonUintArray(pjson, ".amounts");
        require(addrs.length == amounts.length, "participants: length mismatch");

        bytes32[] memory leaves = new bytes32[](addrs.length);
        for (uint256 i = 0; i < addrs.length; i++) {
            leaves[i] = MerkleBuilder.leaf(i, addrs[i], amounts[i]);
        }
        (bytes32 root, bytes32[][] memory proofs) = MerkleBuilder.build(leaves);

        Cfg memory c;
        c.chainId = block.chainid;
        c.root = root;
        // Where browsers should send RPC calls. On a hosted lab this is the tunnel hostname,
        // not the sepolia default, so it must be supplied at deploy time.
        c.chainName = vm.envOr("PUBLIC_CHAIN_NAME", string("Base Sepolia"));
        c.rpcUrl = vm.envOr("PUBLIC_RPC", string("https://sepolia.base.org"));
        c.explorer = vm.envOr("PUBLIC_EXPLORER", string("https://sepolia.basescan.org"));

        vm.startBroadcast(pk);

        c.loot = address(new LabToken("Loot", "LOOT", LOOT_CAP, deployer));
        c.gold = address(new LabToken("Gold", "GOLD", LOOT_CAP, deployer));
        c.silver = address(new LabToken("Silver", "SILVER", LOOT_CAP, deployer));

        c.pair = address(new LabPair(c.gold, c.silver, deployer));
        LabToken(c.gold).mint(deployer, SEED);
        LabToken(c.silver).mint(deployer, SEED);
        LabToken(c.gold).approve(c.pair, type(uint256).max);
        LabToken(c.silver).approve(c.pair, type(uint256).max);
        LabPair(c.pair).seed(SEED, SEED);
        LabPair(c.pair).setMaxTrade(MAX_TRADE);

        c.ballot = address(new Ballot(deployer));
        Ballot(c.ballot).setWeightToken(c.loot);

        c.badge = address(new AdventurerBadge(deployer));

        c.distributor = address(new MerkleDistributor(LabToken(c.loot), root, block.timestamp + 30 days));
        LabToken(c.loot).mint(c.distributor, addrs.length * LOOT_PER_HEAD);

        uint64 opens = uint64(block.timestamp);
        Ballot(c.ballot).createPoll(POLL_1, "Which encounter next?", 2, Ballot.Mode.Equal, opens, opens + 3600);
        Ballot(c.ballot).createPoll(POLL_2, "Which encounter next?", 2, Ballot.Mode.Equal, opens, opens + 7200);

        vm.stopBroadcast();

        _writeDeployments(c);
        _writeMerkle(c, addrs, amounts, proofs);
        _writeWebConfig(c);

        console2.log("chainId      ", c.chainId);
        console2.log("loot         ", c.loot);
        console2.log("pair         ", c.pair);
        console2.log("ballot       ", c.ballot);
        console2.log("badge        ", c.badge);
        console2.log("distributor  ", c.distributor);
        console2.log("merkle root  ", vm.toString(c.root));
    }

    // ------------------------------------------------------------------ writers

    function _writeDeployments(Cfg memory c) internal {
        vm.writeFile(
            string.concat("../deployments/", vm.toString(c.chainId), ".json"),
            string.concat(
                '{"chainId":', vm.toString(c.chainId),
                ',"loot":"', vm.toString(c.loot),
                '","gold":"', vm.toString(c.gold),
                '","silver":"', vm.toString(c.silver),
                '","pair":"', vm.toString(c.pair),
                '","ballot":"', vm.toString(c.ballot),
                '","badge":"', vm.toString(c.badge),
                '","distributor":"', vm.toString(c.distributor),
                '","merkleRoot":"', vm.toString(c.root),
                '","poll1":"', vm.toString(POLL_1),
                '","poll2":"', vm.toString(POLL_2),
                '"}'
            )
        );
    }

    function _writeMerkle(
        Cfg memory c,
        address[] memory addrs,
        uint256[] memory amounts,
        bytes32[][] memory proofs
    ) internal {
        string memory claims;
        for (uint256 i = 0; i < addrs.length; i++) {
            claims = string.concat(
                claims,
                i == 0 ? "" : ",",
                '"', vm.toString(addrs[i]),
                '":{"index":', vm.toString(i),
                ',"amount":"', vm.toString(amounts[i]),
                '","proof":[', _proofJson(proofs[i]),
                "]}"
            );
        }
        string memory merkleJson =
            string.concat('{"root":"', vm.toString(c.root), '","claims":{', claims, "}}");

        // Two copies on purpose: `data/` is the operator record, `web/` is what the static site
        // fetches. They must never diverge, so they are written from the same string.
        vm.writeFile("../data/merkle.json", merkleJson);
        vm.writeFile("../web/merkle.json", merkleJson);
    }

    function _writeWebConfig(Cfg memory c) internal {
        vm.writeFile(
            "../web/config.js",
            string.concat(
                "// generated by script/Deploy.s.sol - do not edit\n",
                "export const CONFIG = {\n",
                "  chainId: ", vm.toString(c.chainId), ",\n",
                "  chainName: '", c.chainName, "',\n",
                "  rpcUrl: '", c.rpcUrl, "',\n",
                "  explorer: '", c.explorer, "',\n",
                "  loot: '", vm.toString(c.loot), "',\n",
                "  gold: '", vm.toString(c.gold), "',\n",
                "  silver: '", vm.toString(c.silver), "',\n",
                "  pair: '", vm.toString(c.pair), "',\n",
                "  ballot: '", vm.toString(c.ballot), "',\n",
                "  badge: '", vm.toString(c.badge), "',\n",
                "  distributor: '", vm.toString(c.distributor), "',\n",
                "  poll1: '", vm.toString(POLL_1), "',\n",
                "  poll2: '", vm.toString(POLL_2), "',\n",
                "};\n"
            )
        );
    }

    // ------------------------------------------------------------------ helpers

    function _proofJson(bytes32[] memory p) internal pure returns (string memory out) {
        for (uint256 i = 0; i < p.length; i++) {
            out = string.concat(out, i == 0 ? '"' : ',"', _toHex(p[i]), '"');
        }
    }

    function _toHex(bytes32 h) internal pure returns (string memory) {
        bytes memory alphabet = "0123456789abcdef";
        bytes memory out = new bytes(66);
        out[0] = "0";
        out[1] = "x";
        for (uint256 i = 0; i < 32; i++) {
            out[2 + i * 2] = alphabet[uint8(h[i] >> 4)];
            out[3 + i * 2] = alphabet[uint8(h[i] & 0x0f)];
        }
        return string(out);
    }
}
