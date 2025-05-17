// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from './libraries/LibDiamond.sol';
import {IDiamondCut} from './interfaces/IDiamondCut.sol';

// Custom errors
error Diamond__FunctionNotFound(bytes4 _functionSelector);

contract Diamond {
    // The layout of diamond storage can be seen in LibDiamond.sol
    // It is defining a struct -- DiamondStorage
    // and a constant bytes32 -- DIAMOND_STORAGE_POSITION
    // You can see where DIAMOND_STORAGE_POSITION is used in LibDiamond.diamondStorage()

    // The EIP-2535 Diamond Standard requires a constructor that takes two arguments:
    //  1. The contract owner.
    //  2. The address of the DiamondCutFacet.
    // This constructor is optional, but is recommended.
    // IMPORTANT: This constructor only adds the DiamondCutFacet. Standard diamonds typically also
    // require DiamondLoupeFacet to be added for EIP-2535 introspection (and IERC165 support).
    // Additionally, if IERC173 (ownership) is supported, an OwnershipFacet should be added.
    // These facets must be added using diamondCut in a subsequent step (e.g., during deployment or via DiamondInit).
    constructor(address _contractOwner, address _diamondCutFacet) payable {
        LibDiamond.setContractOwner(_contractOwner);

        // Add the diamondCut external function from the diamondCutFacet
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        bytes4[] memory functionSelectors = new bytes4[](1);
        functionSelectors[0] = IDiamondCut.diamondCut.selector;
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: _diamondCutFacet,
            action: IDiamondCut.FacetCutAction.Add,
            functionSelectors: functionSelectors
        });
        LibDiamond.diamondCut(cut, address(0), "");

        // add support for DiamondLoupeFacet -- Not required but more user friendly
        // bytes4(keccak256("facets()")) == 0x7a0ed627
        // bytes4(keccak256("facetFunctionSelectors(address)")) == 0x52ef6b2c
        // bytes4(keccak256("facetAddresses()")) == 0xcdffacc6
        // bytes4(keccak256("facetAddress(bytes4)")) == 0xadfca15e
        // bytes4(keccak256("supportsInterface(bytes4)")) == 0x01ffc9a7
        // LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        // ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        // ds.supportedInterfaces[type(IERC165).interfaceId] = true;
    }

    // Find facet for function that is called and execute the
    // function if a facet is found and return any value.
    // Otherwise, throw an error indicating that the function was not found.
    fallback() external payable {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        // get facet from function selector
        bytes32 facetData = ds.facets[msg.sig];
        address facet = address(bytes20(facetData));
        if (facet == address(0)) {
            revert Diamond__FunctionNotFound(msg.sig);
        }
        // Execute external function from facet using delegatecall and return any value.
        assembly {
            // copy function selector and any arguments
            calldatacopy(0, 0, calldatasize())
            // execute function call using the facet
            let result := delegatecall(gas(), facet, 0, calldatasize(), 0, 0)
            // get any return value
            returndatacopy(0, 0, returndatasize())
            // return any return value or error back to the caller
            switch result
            case 0 {
                revert(0, returndatasize())
            }
            default {
                return(0, returndatasize())
            }
        }
    }

    receive() external payable {}
} 