// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ERC-173 Contract Ownership Standard
/// @dev See https://eips.ethereum.org/EIPS/eip-173
/// @author Zainan Victor Zhou <zainanvictor@gmail.com>, James Therien <james@peter.me>, RicMoo <ricmoo@me.com>
interface IERC173 {
    /// @dev This event is emitted when ownership of a contract is transferred.
    /// @param previousOwner The address of the previous owner.
    /// @param newOwner The address of the new owner.
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @notice Get the address of the owner
    /// @return The address of the owner.
    function owner() external view returns (address);

    /// @notice Set the address of the new owner of the contract
    /// @dev Set `newOwner` to `address(0)` to renounce current ownership.
    /// @param newOwner The address of the new owner of the contract
    function transferOwnership(address newOwner) external;
} 