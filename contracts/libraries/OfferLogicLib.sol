// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {MarketplaceStorage} from "./MarketplaceStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";

// Forward declaration for MarketplaceOfferFacet event
contract MarketplaceOfferFacet {
    event OfferCancelled(uint256 indexed offerId, MarketplaceStorage.OfferType offerType);
}

library OfferLogicLib {
    using SafeERC20 for IERC20;

    event OfferProcessingError(uint256 indexed offerId, address nftContract, uint256 tokenId, string reason);

    function addOfferToActiveForItem(
        MarketplaceStorage.Storage storage ms,
        uint256 offerId,
        address nftContract,
        uint256 tokenId
    ) internal {
        ms.activeOfferIdsForItem[nftContract][tokenId].push(offerId);
        ms.offerIdToArrayIndex[offerId] = ms.activeOfferIdsForItem[nftContract][tokenId].length - 1;
    }

    function removeOfferFromActiveForItem(
        MarketplaceStorage.Storage storage ms,
        uint256 offerId,
        address nftContract,
        uint256 tokenId
    ) internal {
        uint256[] storage offerIdsArray = ms.activeOfferIdsForItem[nftContract][tokenId];
        uint256 indexToRemove = ms.offerIdToArrayIndex[offerId];

        if (indexToRemove >= offerIdsArray.length || offerIdsArray[indexToRemove] != offerId) {
            delete ms.offerIdToArrayIndex[offerId]; // Defensive cleanup
            return;
        }

        uint256 lastOfferIdInArray = offerIdsArray[offerIdsArray.length - 1];

        if (offerId != lastOfferIdInArray) {
            offerIdsArray[indexToRemove] = lastOfferIdInArray;
            ms.offerIdToArrayIndex[lastOfferIdInArray] = indexToRemove;
        }
        
        offerIdsArray.pop();
        delete ms.offerIdToArrayIndex[offerId];
    }

    function cancelSpecificOffer(
        MarketplaceStorage.Storage storage ms,
        uint256 offerId,
        address expectedOfferer // Pass msg.sender here for cancellation by offerer
    ) internal {
        MarketplaceStorage.Offer storage offer = ms.offers[offerId];

        if (offer.offerer == address(0)) {
            emit OfferProcessingError(offerId, offer.nftContractAddress, offer.tokenId, "OfferNotFound");
            return; // Or revert with specific error
        }
        if (expectedOfferer != address(0) && offer.offerer != expectedOfferer) { // address(0) means system cancellation
             emit OfferProcessingError(offerId, offer.nftContractAddress, offer.tokenId, "NotOfferer");
            return; // Or revert
        }
        if (offer.status != MarketplaceStorage.OfferStatus.Pending) {
            emit OfferProcessingError(offerId, offer.nftContractAddress, offer.tokenId, "OfferNotPending");
            return; // Or revert
        }

        MarketplaceStorage.OfferType offerType = offer.offerType;
        address nftContractForRemoval = offer.nftContractAddress; 
        uint256 tokenIdForRemoval = offer.tokenId;

        offer.status = MarketplaceStorage.OfferStatus.Cancelled;
        removeOfferFromActiveForItem(ms, offerId, nftContractForRemoval, tokenIdForRemoval);

        // Return escrowed assets
        if (offerType == MarketplaceStorage.OfferType.WETH) {
            if (ms.wethTokenAddress == address(0)) {
                emit OfferProcessingError(offerId, nftContractForRemoval, tokenIdForRemoval, "WETHAddressNotSet");
                return; // Or revert
            }
            if(offer.offeredAmountWETH > 0) {
                IERC20(ms.wethTokenAddress).safeTransfer(offer.offerer, offer.offeredAmountWETH);
            }
        } else if (offerType == MarketplaceStorage.OfferType.NFT) {
            if (offer.offeredNftContractAddress == address(0)) { // Ensure offered NFT address is valid
                 emit OfferProcessingError(offerId, nftContractForRemoval, tokenIdForRemoval, "OfferedNFTAddressZero");
                return; // Or revert
            }
            if (offer.offeredNftStandard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721 offeredNft = IERC721(offer.offeredNftContractAddress);
                // Check if Diamond holds the token before transferring
                if (offeredNft.ownerOf(offer.offeredNftTokenId) == address(this)) {
                    offeredNft.transferFrom(address(this), offer.offerer, offer.offeredNftTokenId);
                } else {
                     emit OfferProcessingError(offerId, nftContractForRemoval, tokenIdForRemoval, "OfferedERC721NotHeldByContract");
                }
            } else { // ERC1155
                IERC1155 offeredNft = IERC1155(offer.offeredNftContractAddress);
                if (offeredNft.balanceOf(address(this), offer.offeredNftTokenId) >= offer.offeredNftAmount) {
                    offeredNft.safeTransferFrom(address(this), offer.offerer, offer.offeredNftTokenId, offer.offeredNftAmount, "");
                } else {
                    emit OfferProcessingError(offerId, nftContractForRemoval, tokenIdForRemoval, "InsufficientOfferedERC1155ByContract");
                }
            }
        }
        // Emit the standard OfferCancelled event via the MarketplaceOfferFacet contract
        // This requires the calling facet to have knowledge of MarketplaceOfferFacet or for this event to be defined more globally.
        // For simplicity, we will rely on the calling facet to emit this if needed, or use the OfferProcessingError for now.
        // A more robust solution would be to pass a callback or use a global event bus if strict event sourcing from Lib is needed.
        // For this refactor, we assume the main facet `MarketplaceOfferFacet` or `MarketplaceBuyingFacet` will emit its own specific cancellation event.
        // However, for clarity that a cancellation processed by the lib occurred:
        emit MarketplaceOfferFacet.OfferCancelled(offerId, offerType); // This specific event might need to be made more generic or handled carefully
    }


    function cancelAllPendingOffersForItem(
        MarketplaceStorage.Storage storage ms,
        address nftContractAddress,
        uint256 tokenId
    ) internal {
        IERC20 weth = (ms.wethTokenAddress == address(0)) ? IERC20(address(0)) : IERC20(ms.wethTokenAddress);
        uint256[] storage offerIdArray = ms.activeOfferIdsForItem[nftContractAddress][tokenId];
      
        for (uint256 i = offerIdArray.length; i > 0; i--) {
            // Iterating backwards because removeOfferFromActiveForItem modifies the array
            uint256 currentOfferId = offerIdArray[i-1]; 
            MarketplaceStorage.Offer storage currentOffer = ms.offers[currentOfferId];

            if (currentOffer.status == MarketplaceStorage.OfferStatus.Pending) { 
                // Call the more detailed cancelSpecificOffer logic.
                // Pass address(0) as expectedOfferer to signify a system-level cancellation.
                cancelSpecificOffer(ms, currentOfferId, address(0)); 
                // cancelSpecificOffer already handles removeOfferFromActiveForItem and emits OfferCancelled
            } else if (currentOffer.status != MarketplaceStorage.OfferStatus.Accepted) {
                // If not pending and not accepted (e.g. already cancelled or expired), just remove from active list.
                // This check is important to avoid trying to cancel an already processed offer again.
                removeOfferFromActiveForItem(ms, currentOfferId, nftContractAddress, tokenId);
            }
            // If Accepted, it should remain in the 'offers' mapping for record-keeping
            // but should have already been removed from 'activeOfferIdsForItem' by acceptOffer logic.
        }
    }
} 