// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IDiamondCut {
    enum FacetCutAction {Add, Replace, Remove}
    // Add=0, Replace=1, Remove=2

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    /// @notice Add/replace/remove any number of functions in a diamond
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call to execute in the context of the diamond
    /// @dev This function can only be called by the owner of the diamond.
    /// @dev This function can accept any number of FacetCut structs.
    /// @dev It is recommended to override the implementation of this function to include access control to functions.
    /// @dev Instead of passing address(0) in _init and no _calldata pass address(0) and "".
    /// @dev Consider using an array of FacetCutStructs[] instead of FacetCut[] if you need to pass in cyclic structs.
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external;

    event DiamondCut(FacetCut[] _diamondCut, address _init, bytes _calldata);
} 