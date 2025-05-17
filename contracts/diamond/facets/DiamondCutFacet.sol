// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from '../libraries/LibDiamond.sol';
import {IDiamondCut} from '../interfaces/IDiamondCut.sol';
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

contract DiamondCutFacet is IDiamondCut, ReentrancyGuard {
    /// @notice Add/replace/remove any number of functions in a diamond
    /// @param _diamondCut Contains the facet addresses and function selectors
    /// @param _init The address of the contract or facet to execute _calldata
    /// @param _calldata A function call to execute in the context of the diamond
    function diamondCut(
        FacetCut[] calldata _diamondCut,
        address _init,
        bytes calldata _calldata
    ) external override nonReentrant {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(_diamondCut, _init, _calldata);
    }
} 