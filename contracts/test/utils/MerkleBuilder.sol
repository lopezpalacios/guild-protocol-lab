// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title MerkleBuilder
/// @notice Test/script-only helper. Builds a balanced tree and returns every proof, so the
///         deploy script and the tests agree on leaf encoding without duplicating the logic.
/// @dev Leaf encoding must match MerkleDistributor: keccak256(abi.encodePacked(index, account, amount)).
library MerkleBuilder {
    function leaf(uint256 index, address account, uint256 amount) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(index, account, amount));
    }

    function hashPair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encodePacked(a, b)) : keccak256(abi.encodePacked(b, a));
    }

    function build(bytes32[] memory leaves)
        internal
        pure
        returns (bytes32 root, bytes32[][] memory proofs)
    {
        uint256 n = leaves.length;
        require(n > 0, "empty tree");

        bytes32[] memory padded = _pad(leaves);
        uint256 levelsCount = _log2(padded.length) + 1;

        bytes32[][] memory levels = new bytes32[][](levelsCount);
        levels[0] = padded;

        for (uint256 l = 1; l < levelsCount; l++) {
            uint256 prevLen = levels[l - 1].length;
            levels[l] = new bytes32[](prevLen / 2);
            for (uint256 i = 0; i < prevLen / 2; i++) {
                levels[l][i] = hashPair(levels[l - 1][2 * i], levels[l - 1][2 * i + 1]);
            }
        }

        root = levels[levelsCount - 1][0];

        proofs = new bytes32[][](n);
        for (uint256 i = 0; i < n; i++) {
            proofs[i] = new bytes32[](levelsCount - 1);
            uint256 idx = i;
            for (uint256 l = 0; l < levelsCount - 1; l++) {
                proofs[i][l] = levels[l][idx ^ 1];
                idx = idx / 2;
            }
        }
    }

    function _pad(bytes32[] memory leaves) private pure returns (bytes32[] memory) {
        uint256 n = leaves.length;
        uint256 target = 1;
        while (target < n) target <<= 1;
        if (target == n) return leaves;

        bytes32[] memory out = new bytes32[](target);
        for (uint256 i = 0; i < target; i++) {
            // Padding leaves are hash-derived, so they cannot collide with a real (index, account,
            // amount) triple. They are unclaimable by construction, not by policy.
            out[i] = i < n ? leaves[i] : keccak256(abi.encodePacked("pad", i));
        }
        return out;
    }

    function _log2(uint256 x) private pure returns (uint256 r) {
        while (x > 1) {
            x >>= 1;
            r++;
        }
    }
}
