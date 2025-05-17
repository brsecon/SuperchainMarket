// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from '../libraries/LibDiamond.sol';
import {IDiamondLoupe} from '../interfaces/IDiamondLoupe.sol';
import {IERC165} from '../interfaces/IERC165.sol';

// The loupe functions are view functions and do not change state.
// The loupe functions are pure functions and do not read state.
// They are used to query the facets and functions of a diamond.
// They are used by Etherscan and other tools to display information about a diamond.
contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    /// @notice Gets all facets and their selectors.
    /// @return facets_ Facet
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 numFacets = ds.facetAddresses.length;
        facets_ = new Facet[](numFacets);
        for (uint256 i = 0; i < numFacets; i++) {
            address facetAddress_ = ds.facetAddresses[i];
            facets_[i].facetAddress = facetAddress_;
            facets_[i].functionSelectors = ds.functionSelectors[facetAddress_];
        }
    }

    /// @notice Gets all the function selectors supported by a specific facet.
    /// @param _facet The facet address.
    /// @return facetFunctionSelectors_ Facet function selectors.
    function facetFunctionSelectors(address _facet) external view override returns (bytes4[] memory facetFunctionSelectors_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetFunctionSelectors_ = ds.functionSelectors[_facet];
    }

    /// @notice Get all the facet addresses used by a diamond.
    /// @return facetAddresses_ Facet addresses.
    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        facetAddresses_ = ds.facetAddresses;
    }

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return facetAddress_ The facet address.
    function facetAddress(bytes4 _functionSelector) external view override returns (address facetAddress_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        bytes32 facetData = ds.facets[_functionSelector];
        facetAddress_ = address(bytes20(facetData));
    }

    // This implements ERC-165.
    function supportsInterface(bytes4 _interfaceId) external view override returns (bool) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        return ds.supportedInterfaces[_interfaceId];
    }
} 