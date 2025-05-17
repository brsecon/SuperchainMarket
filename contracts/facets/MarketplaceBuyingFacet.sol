// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {OfferLogicLib} from "../libraries/OfferLogicLib.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
// MarketplaceOfferFacet importu artık gerekmeyebilir, çünkü OfferCancelled eventi OfferLogicLib'den gelebilir veya merkezi olmayabilir.
// import {MarketplaceOfferFacet} from "./MarketplaceOfferFacet.sol"; 

// Custom Errors
error MarketplaceBuyingFacet__ItemNotListed();
error MarketplaceBuyingFacet__PriceNotMet();
error MarketplaceBuyingFacet__TransferFailed();
error MarketplaceBuyingFacet__PaymentTokenNotSupported();
error MarketplaceBuyingFacet__IncorrectOwnerOrBalance();
error MarketplaceBuyingFacet__RoyaltyPaymentFailed();
error MarketplaceBuyingFacet__UnsupportedNFTContractForRoyalty();
error MarketplaceBuyingFacet__RoyaltyCalculationOverflow();
// Yeni Event'ler Royalty Hataları İçin
event RoyaltyInfoRetrievalFailed(address indexed nftContractAddress, uint256 indexed tokenId, string reason);
event RoyaltyExceedsPrice(address indexed nftContractAddress, uint256 indexed tokenId, uint256 price, uint256 royaltyAmount);

contract MarketplaceBuyingFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event ItemSold(
        address indexed nftContractAddress,
        uint256 indexed tokenId,
        MarketplaceStorage.TokenStandard standard,
        uint256 amount,
        address seller,
        address buyer,
        uint256 price,
        address paymentToken,
        address royaltyRecipient,
        uint256 royaltyAmountPaid
    );

    // OfferCancelled event'i burada da emit edilebilir, ancak MarketplaceOfferFacet'te zaten var.
    // Çift emit yerine oradaki event'e güvenilebilir veya bu fonksiyon özel bir event emit edebilir.
    // event OfferCancelledAfterSale(uint256 indexed offerId, MarketplaceStorage.OfferType offerType);

    function buyItem(address _nftContractAddress, uint256 _tokenId) external payable nonReentrant {
        // --- Checks --- 
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.Listing storage listing = ms.listings[_nftContractAddress][_tokenId];

        if (!listing.isActive) {
            revert MarketplaceBuyingFacet__ItemNotListed();
        }

        uint256 price = listing.price;
        address paymentTokenAddress = listing.paymentToken;
        
        if (paymentTokenAddress == address(0)) { // ETH payment
            if (msg.value < price) {
                revert MarketplaceBuyingFacet__PriceNotMet();
            }
        } else { // ERC20 payment
            if (msg.value > 0) {
                revert MarketplaceBuyingFacet__PaymentTokenNotSupported(); // ETH should not be sent for ERC20 payment
            }
            // ERC20 balance/allowance check will be done by safeTransferFrom later
        }

        // --- Effects (Part 1 - Calculate amounts before interactions) ---
        address payable seller = listing.seller;
        address buyer = msg.sender;
        MarketplaceStorage.TokenStandard standard = listing.standard;
        uint256 amountToTransfer = listing.amount;

        address royaltyRecipient = address(0);
        uint256 royaltyAmount = 0;

        try IERC165(_nftContractAddress).supportsInterface(type(IERC2981).interfaceId) returns (bool supportsRoyalty) {
            if (supportsRoyalty) {
                (address recipient, uint256 rAmount) = IERC2981(_nftContractAddress).royaltyInfo(_tokenId, price);
                if (recipient != address(0) && rAmount > 0) {
                    if (rAmount >= price) {
                        // Royalty is too high or equals price.
                        emit RoyaltyExceedsPrice(_nftContractAddress, _tokenId, price, rAmount); // Event emit et
                        royaltyAmount = 0; // Önceki davranış korunuyor, royalty ödenmiyor.
                    } else {
                        royaltyRecipient = recipient;
                        royaltyAmount = rAmount;
                    }
                }
            }
        } catch Error(string memory reason) {
            emit RoyaltyInfoRetrievalFailed(_nftContractAddress, _tokenId, reason);
            // Royalty alınamazsa, royaltyAmount 0 olarak kalır, işlem devam eder.
        } catch {
            emit RoyaltyInfoRetrievalFailed(_nftContractAddress, _tokenId, "Unknown reason");
            // Royalty alınamazsa, royaltyAmount 0 olarak kalır, işlem devam eder.
        }
        
        uint256 remainingPriceAfterRoyalty = price - royaltyAmount; // Safe because royaltyAmount < price checked above
        uint256 marketplaceFee = (price * ms.marketplaceFeePercent) / 10000; 

        if (marketplaceFee > remainingPriceAfterRoyalty) { 
            marketplaceFee = remainingPriceAfterRoyalty; 
        }
        uint256 sellerProceeds = remainingPriceAfterRoyalty - marketplaceFee; // This can be 0

        // --- Effects (Part 2 - Update state and emit event) ---
        listing.isActive = false;

        emit ItemSold(
            _nftContractAddress, // Use parameter directly as listing storage might be cleared by another diamond call if not careful (though unlikely here)
            _tokenId,            // Use parameter directly
            standard,
            amountToTransfer,
            seller,
            buyer,
            price,
            paymentTokenAddress,
            royaltyRecipient,
            royaltyAmount
        );

        // --- Interactions ---
        if (paymentTokenAddress == address(0)) { // ETH Payment Distribution
            if (royaltyAmount > 0) {
                (bool successRoyalty, ) = payable(royaltyRecipient).call{value: royaltyAmount}("");
                if (!successRoyalty) revert MarketplaceBuyingFacet__RoyaltyPaymentFailed();
            }
            if (marketplaceFee > 0 && ms.feeRecipient != address(0)) {
                (bool successFee, ) = ms.feeRecipient.call{value: marketplaceFee}("");
                if (!successFee) revert MarketplaceBuyingFacet__TransferFailed();
            }
            if (sellerProceeds > 0) {
                (bool successSeller, ) = seller.call{value: sellerProceeds}("");
                if (!successSeller) revert MarketplaceBuyingFacet__TransferFailed();
            }
            if (msg.value > price) { // Refund excess ETH
                (bool successRefund, ) = payable(buyer).call{value: msg.value - price}("");
                if (!successRefund) { /* Optional: Log refund failure, but proceed */ }
            }
        } else { // ERC20 Payment Distribution
            IERC20 token = IERC20(paymentTokenAddress);
            token.safeTransferFrom(buyer, address(this), price); // 1. Collect full price from buyer to this contract

            if (royaltyAmount > 0) { // 2. Pay royalty from this contract
                token.safeTransfer(royaltyRecipient, royaltyAmount);
            }
            if (marketplaceFee > 0 && ms.feeRecipient != address(0)) { // 3. Pay fee from this contract
                token.safeTransfer(ms.feeRecipient, marketplaceFee);
            }
            if (sellerProceeds > 0) { // 4. Pay seller from this contract
                token.safeTransfer(seller, sellerProceeds);
            }
            // Any remaining ERC20 tokens (if price was miscalculated or due to dust) would stay in the contract.
            // This shouldn't happen with current logic if all transfers are successful.
        }

        // NFT Transfer to Buyer
        if (standard == MarketplaceStorage.TokenStandard.ERC721) {
            IERC721 nftContract = IERC721(_nftContractAddress);
            // Check if the marketplace (this contract) owns the NFT before transferring
            if (nftContract.ownerOf(_tokenId) != address(this)) {
                revert MarketplaceBuyingFacet__IncorrectOwnerOrBalance(); // Should have been escrowed
            }
            nftContract.transferFrom(address(this), buyer, _tokenId);
        } else if (standard == MarketplaceStorage.TokenStandard.ERC1155) {
            IERC1155 nftContract = IERC1155(_nftContractAddress);
            if (nftContract.balanceOf(address(this), _tokenId) < amountToTransfer) {
                revert MarketplaceBuyingFacet__IncorrectOwnerOrBalance(); // Should have been escrowed
            }
            nftContract.safeTransferFrom(address(this), buyer, _tokenId, amountToTransfer, "");
        } else {
            // This case should ideally not be reached due to prior validation when listing.
            // However, as a defensive measure, one might revert here.
            // For now, this path means no NFT transfer will occur if standard is unknown.
        }

        // Final internal interaction (also needs to be CEI compliant)
        OfferLogicLib.cancelAllPendingOffersForItem(ms, _nftContractAddress, _tokenId);
    }

    // **DUPLICATED FROM MarketplaceOfferFacet.sol - Consider moving to a shared library if possible**
    // function _removeOfferFromActiveForItem(MarketplaceStorage.Storage storage ms, uint256 offerId, address nftContract, uint256 tokenId) internal { // KALDIRILDI
    //     ...
    // }

    // function _cancelPendingOffersAfterSale( // KALDIRILDI
    //     address _nftContractAddress,
    //     uint256 _tokenId
    // ) internal {
    //     ...
    // }
}
