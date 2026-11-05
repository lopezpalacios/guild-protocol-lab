// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title LabToken
/// @notice One contract, three deployments: Loot (the airdrop), Gold and Silver (the AMM pair).
/// @dev Deliberately minimal. No permit, no votes, no hooks — every extra feature is one more
///      thing that can fail on stage, and the lab's job is to be legible, not complete.
contract LabToken is ERC20 {
    /// @notice Hard cap. A testnet token with a cap teaches supply better than one without.
    uint256 public immutable cap;

    /// @notice The only address allowed to mint. Set once, by the treasury, at deploy time.
    address public immutable minter;

    error NotMinter();
    error CapExceeded();

    constructor(string memory name_, string memory symbol_, uint256 cap_, address minter_)
        ERC20(name_, symbol_)
    {
        cap = cap_;
        minter = minter_;
    }

    /// @notice Mint new tokens. Callable only by the minter (the MerkleDistributor or the treasury).
    /// @dev No owner backdoor: the minter is immutable. If the mint key is lost, supply is frozen.
    ///      That is a real tradeoff and it is the correct one for a lab — nobody can quietly
    ///      re-mint loot mid-session.
    function mint(address to, uint256 amount) external {
        if (msg.sender != minter) revert NotMinter();
        if (totalSupply() + amount > cap) revert CapExceeded();
        _mint(to, amount);
    }
}
