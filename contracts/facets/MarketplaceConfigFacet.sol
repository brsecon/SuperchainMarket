// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";

// Custom Errors
error MarketplaceConfigFacet__FeePercentTooHigh(uint256 givenPercent, uint256 maxPercent);
error MarketplaceConfigFacet__ZeroAddress();

// Note: WETH Token address is set in DiamondInit.sol during initialization.
// If you need to update WETH address post-deployment, a new function
// similar to setFeeRecipient would be required here.
contract MarketplaceConfigFacet {
    uint256 constant MAX_FEE_PERCENT = 10000; // %100.00, örneğin 250 = %2.50

    event MarketplaceFeePercentUpdated(uint256 oldFeePercent, uint256 newFeePercent);
    event FeeRecipientUpdated(address oldFeeRecipient, address newFeeRecipient);
    event WethTokenAddressUpdated(address oldWethTokenAddress, address newWethTokenAddress);

    /// @notice Sets the percentage of the sale price that goes to the marketplace.
    /// @param _feePercent The new fee percentage (e.g., 250 for 2.5%). Max 10000 (100%).
    /// @dev Only callable by the contract owner.
    function setMarketplaceFeePercent(uint256 _feePercent) external {
        LibDiamond.enforceIsContractOwner();
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();

        if (_feePercent > MAX_FEE_PERCENT) {
            revert MarketplaceConfigFacet__FeePercentTooHigh(_feePercent, MAX_FEE_PERCENT);
        }

        uint256 oldFeePercent = ms.marketplaceFeePercent;
        ms.marketplaceFeePercent = _feePercent;
        emit MarketplaceFeePercentUpdated(oldFeePercent, _feePercent);
    }

    /// @notice Sets the address that receives the marketplace fees.
    /// @param _feeRecipient The new address for receiving fees.
    /// @dev Only callable by the contract owner.
    function setFeeRecipient(address payable _feeRecipient) external {
        LibDiamond.enforceIsContractOwner();
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();

        if (_feeRecipient == address(0)) {
            revert MarketplaceConfigFacet__ZeroAddress();
        }

        address oldFeeRecipient = ms.feeRecipient;
        ms.feeRecipient = _feeRecipient;
        emit FeeRecipientUpdated(oldFeeRecipient, _feeRecipient);
    }

    /// @notice Gets the current marketplace fee percentage.
    /// @return The fee percentage (e.g., 250 for 2.5%).
    function getMarketplaceFeePercent() external view returns (uint256) {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        return ms.marketplaceFeePercent;
    }

    /// @notice Gets the current address that receives marketplace fees.
    /// @return The address of the fee recipient.
    function getFeeRecipient() external view returns (address) {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        return ms.feeRecipient;
    }

    /// @notice Sets the WETH token address for the marketplace.
    /// @param _wethTokenAddress The new address of the WETH token.
    /// @dev Only callable by the contract owner.
    function setWethTokenAddress(address _wethTokenAddress) external {
        LibDiamond.enforceIsContractOwner();
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();

        if (_wethTokenAddress == address(0)) {
            revert MarketplaceConfigFacet__ZeroAddress();
        }

        address oldWethTokenAddress = ms.wethTokenAddress;
        ms.wethTokenAddress = _wethTokenAddress;
        emit WethTokenAddressUpdated(oldWethTokenAddress, _wethTokenAddress);
    }

    /// @notice Gets the current WETH token address used by the marketplace.
    /// @return The address of the WETH token.
    function getWethTokenAddress() external view returns (address) {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        return ms.wethTokenAddress;
    }
} 