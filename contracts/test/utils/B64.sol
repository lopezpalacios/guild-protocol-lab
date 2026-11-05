// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

/// @title B64
/// @notice Test-only base64 decoder. OZ 5.1 ships `encode` but not `decode`, and the badge test
///         needs to prove the data URI actually round-trips to the SVG we think we wrote.
library B64 {
    function decode(string memory input) internal pure returns (bytes memory) {
        bytes memory data = bytes(input);
        require(data.length % 4 == 0, "b64: bad length");

        uint256 pad;
        if (data[data.length - 1] == "=") pad++;
        if (data[data.length - 2] == "=") pad++;

        uint256 outLen = (data.length / 4) * 3 - pad;
        bytes memory out = new bytes(outLen);

        uint256 j;
        for (uint256 i = 0; i < data.length; i += 4) {
            uint256 a = _val(data[i]);
            uint256 b = _val(data[i + 1]);
            uint256 c = _val(data[i + 2]);
            uint256 d = _val(data[i + 3]);
            uint256 triple = (a << 18) | (b << 12) | (c << 6) | d;

            if (j < outLen) out[j++] = bytes1(uint8(triple >> 16));
            if (j < outLen) out[j++] = bytes1(uint8(triple >> 8));
            if (j < outLen) out[j++] = bytes1(uint8(triple));
        }
        return out;
    }

    function _val(bytes1 ch) private pure returns (uint256) {
        uint8 c = uint8(ch);
        if (c >= 65 && c <= 90) return c - 65; // A-Z
        if (c >= 97 && c <= 122) return c - 97 + 26; // a-z
        if (c >= 48 && c <= 57) return c - 48 + 52; // 0-9
        if (c == 43) return 62; // +
        if (c == 47) return 63; // /
        if (c == 61) return 0; // =
        revert("b64: bad char");
    }
}
