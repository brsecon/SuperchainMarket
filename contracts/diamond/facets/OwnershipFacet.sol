// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../libraries/LibDiamond.sol";
import {IERC173} from "@openzeppelin/contracts/interfaces/IERC173.sol";

error OwnershipFacet__NotContractOwner(); // Custom error for more gas efficiency

contract OwnershipFacet is IERC173 {
    /// @notice Get the owner of the contract
    /// @return The address of the owner
    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }

    /// @notice Transfer ownership of the contract to a new owner
    /// @param _newOwner The address of the new owner
    function transferOwnership(address _newOwner) external override {
        // Replaced LibDiamond.enforceIsContractOwner() with direct check for custom error
        if (msg.sender != LibDiamond.contractOwner()) {
            revert OwnershipFacet__NotContractOwner();
        }
        LibDiamond.setContractOwner(_newOwner);
    }
} 