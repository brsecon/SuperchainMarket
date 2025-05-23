// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDiamondLoupe {
    /// @notice Gets all facets and their selectors.
    /// @return facets_ Facet
    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }
    function facets() external view returns (Facet[] memory facets_);

    /// @notice Gets all the function selectors supported by a specific facet.
    /// @param _facet The facet address.
    /// @return facetFunctionSelectors_ Facet function selectors.
    function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory facetFunctionSelectors_);

    /// @notice Get all the facet addresses used by a diamond.
    /// @return facetAddresses_ Facet addresses.
    function facetAddresses() external view returns (address[] memory facetAddresses_);

    /// @notice Gets the facet that supports the given selector.
    /// @dev If facet is not found return address(0).
    /// @param _functionSelector The function selector.
    /// @return facetAddress_ The facet address.
    function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
} 