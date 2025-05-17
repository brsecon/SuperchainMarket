// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IDiamondCut} from '../interfaces/IDiamondCut.sol';

// It is expected that this library is used with a diamond proxy
// https://eips.ethereum.org/EIPS/eip-2535
// It is expected that the diamond proxy inherits from "DiamondStorage"
library LibDiamond {
    bytes32 constant DIAMOND_STORAGE_POSITION = keccak256("diamond.standard.diamond.storage");

    struct DiamondStorage {
        // maps function selector to the facet address and function selector position in selectors array
        mapping(bytes4 => bytes32) facets;
        // maps facet addresses to function selectors
        mapping(address => bytes4[]) functionSelectors;
        // facet addresses
        address[] facetAddresses;
        // Used to query if a contract implements an interface. See ERC165.
        mapping(bytes4 => bool) supportedInterfaces;
        // owner of the contract
        address contractOwner;
    }

    function diamondStorage() internal pure returns (DiamondStorage storage ds) {
        bytes32 position = DIAMOND_STORAGE_POSITION;
        assembly {
            ds.slot := position
        }
    }

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /// @dev Sets the contract owner.
    /// @param _newOwner The address of the new owner.
    function setContractOwner(address _newOwner) internal {
        require(_newOwner != address(0), "LibDiamond: New owner cannot be zero address");
        DiamondStorage storage ds = diamondStorage();
        address previousOwner = ds.contractOwner;
        ds.contractOwner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }

    /// @dev Gets the contract owner.
    /// @return contractOwner_ The address of the contract owner.
    function contractOwner() internal view returns (address contractOwner_) {
        contractOwner_ = diamondStorage().contractOwner;
    }

    /// @dev Throws an error if an attempt is made to call this function by any account other than the owner.
    function enforceIsContractOwner() internal view {
        require(msg.sender == diamondStorage().contractOwner, "LibDiamond: Must be contract owner");
    }

    event DiamondCut(IDiamondCut.FacetCut[] _diamondCut, address _init, bytes _calldata);

    // Internal function version of diamondCut
    // This is more flexible because it does not have parameter size limits.
    // RECOMMENDED: Add a reentrancy guard (e.g., OpenZeppelin's ReentrancyGuard) to this function
    // to prevent reentrancy attacks, especially due to the _init delegatecall.
    /// @dev Executes diamondCut operations: Add, Replace, or Remove facets and their functions.
    ///      It can also initialize state using `_init` and `_calldata`.
    /// @param _diamondCut An array of FacetCut structs specifying the cut operations.
    /// @param _init The address of the contract to call for initialization (optional, can be address(0)).
    /// @param _calldata The data to pass to the initialization call (optional, can be empty).
    function diamondCut(IDiamondCut.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) internal {
        DiamondStorage storage ds = diamondStorage();
        uint256 originalFacetAddressesLength = ds.facetAddresses.length;
        for (uint256 i = 0; i < _diamondCut.length; i++) {
            IDiamondCut.FacetCutAction action = _diamondCut[i].action;
            address facetAddress = _diamondCut[i].facetAddress;
            bytes4[] memory functionSelectors = _diamondCut[i].functionSelectors;
            if (action == IDiamondCut.FacetCutAction.Add) {
                addFunctions(facetAddress, functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Replace) {
                replaceFunctions(facetAddress, functionSelectors);
            } else if (action == IDiamondCut.FacetCutAction.Remove) {
                removeFunctions(facetAddress, functionSelectors);
            } else {
                revert("LibDiamondCut: Incorrect FacetCutAction");
            }
        }
        emit DiamondCut(_diamondCut, _init, _calldata);
        initializeDiamondCut(_init, _calldata);
        // cleanupDiamondCut(originalFacetAddressesLength); // Audited: Removed as removeFunctions handles cleaning up facetAddresses for emptied facets.
    }

    /// @dev Adds new functions to a facet. 
    ///      The facet address is added to `ds.facetAddresses` if it's not already there.
    ///      Function selectors are mapped to the facet address.
    /// @param _facetAddress The address of the facet to add functions to.
    /// @param _functionSelectors An array of function selectors to add.
    function addFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        // Check if facet is already added
        require(!isFacetAdded(_facetAddress), "LibDiamondCut: Facet already added");
        // Add facet to facetAddresses array if it's not already there
        ds.facetAddresses.push(_facetAddress);
        // Add function selectors to functionSelectors mapping
        ds.functionSelectors[_facetAddress] = _functionSelectors;
        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            bytes32 currentFacet = ds.facets[selector];
            require(address(bytes20(currentFacet)) == address(0), "LibDiamondCut: Selector already exists in diamond");
            // Add function selector to facets mapping
            // selectorPosition is the index of the selector in the facetFunctionSelectors.functionSelectors array
            ds.facets[selector] = bytes20(_facetAddress) | (bytes32(i) << 160);
        }
    }

    /// @dev Replaces existing functions of a facet with new ones.
    ///      The facet must already be added.
    ///      Old function selectors are removed and new ones are added.
    /// @param _facetAddress The address of the facet to replace functions in.
    /// @param _functionSelectors An array of new function selectors.
    function replaceFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        // Check if facet is added
        require(isFacetAdded(_facetAddress), "LibDiamondCut: Facet not added");
        // Get existing function selectors for the facet
        bytes4[] storage oldFunctionSelectors = ds.functionSelectors[_facetAddress];
        // Remove old function selectors from facets mapping
        for (uint256 i = 0; i < oldFunctionSelectors.length; i++) {
            delete ds.facets[oldFunctionSelectors[i]];
        }
        // Add new function selectors to functionSelectors mapping
        ds.functionSelectors[_facetAddress] = _functionSelectors;
        // Add new function selectors to facets mapping
        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            bytes32 currentFacet = ds.facets[selector];
            require(address(bytes20(currentFacet)) == address(0), "LibDiamondCut: Selector already exists in diamond");
            ds.facets[selector] = bytes20(_facetAddress) | (bytes32(i) << 160);
        }
    }

    /// @dev Removes functions from a facet. 
    ///      If all functions of a facet are removed, the facet itself is removed from `ds.facetAddresses`.
    /// @param _facetAddress The address of the facet to remove functions from.
    /// @param _functionSelectors An array of function selectors to remove.
    function removeFunctions(address _facetAddress, bytes4[] memory _functionSelectors) internal {
        require(_functionSelectors.length > 0, "LibDiamondCut: No selectors in facet to cut");
        DiamondStorage storage ds = diamondStorage();
        // Check if facet is added
        require(isFacetAdded(_facetAddress), "LibDiamondCut: Facet not added");
        // Get existing function selectors for the facet
        bytes4[] storage facetFunctionSelectorsFromStorage = ds.functionSelectors[_facetAddress];
        // Check that all selectors to remove are in the set of existing selectors for this facet
        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            bytes4 selector = _functionSelectors[i];
            bool found = false;
            for (uint256 j = 0; j < facetFunctionSelectorsFromStorage.length; j++) {
                if (selector == facetFunctionSelectorsFromStorage[j]) {
                    found = true;
                    break;
                }
            }
            require(found, "LibDiamondCut: Trying to remove selector that is not in facet");
        }

        // Create a new array for the remaining function selectors
        bytes4[] memory newFunctionSelectors = new bytes4[](facetFunctionSelectorsFromStorage.length - _functionSelectors.length);
        uint256 newFunctionSelectorsIndex = 0;
        for (uint256 i = 0; i < facetFunctionSelectorsFromStorage.length; i++) {
            bytes4 selector = facetFunctionSelectorsFromStorage[i];
            bool toBeRemoved = false;
            for (uint256 j = 0; j < _functionSelectors.length; j++) {
                if (selector == _functionSelectors[j]) {
                    toBeRemoved = true;
                    break;
                }
            }
            if (!toBeRemoved) {
                newFunctionSelectors[newFunctionSelectorsIndex] = selector;
                newFunctionSelectorsIndex++;
            }
        }

        // Remove function selectors from facets mapping
        for (uint256 i = 0; i < _functionSelectors.length; i++) {
            delete ds.facets[_functionSelectors[i]];
        }

        // Update functionSelectors mapping with the new array of selectors
        // If all selectors are removed then delete the facet from the functionSelectors mapping and facetAddresses array
        if (newFunctionSelectors.length == 0) {
            delete ds.functionSelectors[_facetAddress];
            // Remove facetAddress from facetAddresses array
            uint256 facetAddressPosition = 0;
            for (uint256 i = 0; i < ds.facetAddresses.length; i++) {
                if (ds.facetAddresses[i] == _facetAddress) {
                    facetAddressPosition = i;
                    break;
                }
            }
            // If it is not the last facet address then overwrite it with the last facet address and reduce the length of the array by one.
            // If it is the last facet address then just reduce the length of the array by one.
            if (facetAddressPosition < ds.facetAddresses.length - 1) {
                ds.facetAddresses[facetAddressPosition] = ds.facetAddresses[ds.facetAddresses.length - 1];
            }
            ds.facetAddresses.pop();
        } else {
            ds.functionSelectors[_facetAddress] = newFunctionSelectors;
        }
    }

    /// @dev Checks if a facet has already been added to the diamond.
    /// @param _facetAddress The address of the facet to check.
    /// @return bool True if the facet is added, false otherwise.
    function isFacetAdded(address _facetAddress) internal view returns (bool) {
        DiamondStorage storage ds = diamondStorage();
        for (uint i = 0; i < ds.facetAddresses.length; i++) {
            if (ds.facetAddresses[i] == _facetAddress) {
                return true;
            }
        }
        return false;
    }

    // WARNING: This function uses delegatecall. It is critical that this function is only callable
    // from the 'diamondCut' function and that '_init' and '_calldata' are fully trusted,
    // as a malicious '_init' contract could take over the diamond or alter its state unexpectedly.
    // Ensure the calling context ('diamondCut') properly restricts access and validates inputs.
    /// @dev Executes an initialization call using delegatecall if `_init` is not the zero address.
    /// @param _init The address of the contract to call for initialization.
    /// @param _calldata The data to pass to the initialization call.
    function initializeDiamondCut(address _init, bytes memory _calldata) internal {
        if (_init == address(0)) {
            require(_calldata.length == 0, "LibDiamondCut: _init is address(0) but_calldata is not empty");
        } else {
            require(_calldata.length > 0, "LibDiamondCut: _calldata is empty but _init is not address(0)");
            // delegatecall _init function call
            (bool success, ) = _init.delegatecall(_calldata);
            require(success, "LibDiamondCut: _init call failed");
        }
    }

    /* // Audited: Removed cleanupDiamondCut function.
    // The removeFunctions internal function already handles removing a facet from ds.facetAddresses
    // when all of its functions are removed. This makes cleanupDiamondCut redundant
    // and removing it saves gas.
    function cleanupDiamondCut(uint256 _originalFacetAddressesLength) internal {
        DiamondStorage storage ds = diamondStorage();
        if (ds.facetAddresses.length > _originalFacetAddressesLength) {
            return;
        }
        // Remove any facet addresses that no longer have any function selectors in them
        // This is to prevent unused facet addresses from being stored in ds.facetAddresses
        // and from being returned by the loupe functions.
        // Starting from the end of the array because elements are being removed.
        for (uint256 i = ds.facetAddresses.length; i > 0; i--) {
            address facetAddress = ds.facetAddresses[i - 1];
            if (ds.functionSelectors[facetAddress].length == 0) {
                // Remove facetAddress from facetAddresses array
                uint256 facetAddressPosition = 0;
                for (uint256 j = 0; j < ds.facetAddresses.length; j++) {
                    if (ds.facetAddresses[j] == facetAddress) {
                        facetAddressPosition = j;
                        break;
                    }
                }
                // If it is not the last facet address then overwrite it with the last facet address and reduce the length of the array by one.
                // If it is the last facet address then just reduce the length of the array by one.
                if (facetAddressPosition < ds.facetAddresses.length - 1) {
                    ds.facetAddresses[facetAddressPosition] = ds.facetAddresses[ds.facetAddresses.length - 1];
                }
                ds.facetAddresses.pop();
            }
        }
    }
    */
} 