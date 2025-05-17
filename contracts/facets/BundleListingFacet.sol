// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

// Custom Errors
error BundleListingFacet__EmptyBundle();
error BundleListingFacet__ZeroAddress();
error BundleListingFacet__InvalidAmount();
error BundleListingFacet__PriceMustBeGreaterThanZero();
error BundleListingFacet__NotItemOwnerOrApproved();
error BundleListingFacet__TransferFailed(); // Covers general transfer issues, SafeERC20 and .call reverts provide more specifics
error BundleListingFacet__BundleNotFound();
error BundleListingFacet__NotBundleSeller();
error BundleListingFacet__BundleNotActive();
error BundleListingFacet__PriceNotMet();
error BundleListingFacet__PaymentTokenNotSupported(); // e.g. sending ETH for ERC20 listing
error BundleListingFacet__RoyaltyPaymentFailed(); // Specific for royalty .call failures
error BundleListingFacet__InsufficientBalanceOrAllowance(); // For ERC20 payments
error BundleListingFacet__ApprovalMissingForItem(address nftContract, uint256 tokenId); // Yeni Hata

// Royalty hataları için yeni eventler
event BundleItemRoyaltyInfoRetrievalFailed(uint256 indexed bundleId, address indexed nftContractAddress, uint256 indexed tokenId, string reason);
event BundleItemRoyaltyExceedsPriceShare(uint256 indexed bundleId, address indexed nftContractAddress, uint256 indexed tokenId, uint256 itemPriceShare, uint256 royaltyAmount);

contract BundleListingFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event BundleListed(
        uint256 indexed bundleId,
        address indexed seller,
        MarketplaceStorage.NFTItem[] items,
        uint256 price,
        address paymentToken
    );

    event BundleCancelled(
        uint256 indexed bundleId
    );

    event BundleSold(
        uint256 indexed bundleId,
        address seller,
        address indexed buyer,
        uint256 price,
        address paymentToken
        // Detailed royalty info per item could be an event if needed
    );

    /// @notice List a bundle of NFTs for sale.
    /// @dev The caller (msg.sender) must own all NFTs in the `_items` array and must have approved this contract (the Diamond) to transfer each of them.
    function listBundle(
        MarketplaceStorage.NFTItem[] calldata _items,
        uint256 _price,
        address _paymentToken // address(0) for ETH, specific ERC20 address otherwise
    ) external nonReentrant {
        // --- Checks ---
        if (_items.length == 0) {
            revert BundleListingFacet__EmptyBundle();
        }
        if (_price == 0) {
            revert BundleListingFacet__PriceMustBeGreaterThanZero();
        }

        MarketplaceStorage.NFTItem[] memory itemsToStore = new MarketplaceStorage.NFTItem[](_items.length);
        for (uint256 i = 0; i < _items.length; i++) {
            MarketplaceStorage.NFTItem calldata currentItem = _items[i];
            if (currentItem.nftContractAddress == address(0)) {
                revert BundleListingFacet__ZeroAddress();
            }

            if (currentItem.standard == MarketplaceStorage.TokenStandard.ERC721) {
                if (currentItem.amount != 1) revert BundleListingFacet__InvalidAmount();
                IERC721 nft = IERC721(currentItem.nftContractAddress);
                if (nft.ownerOf(currentItem.tokenId) != msg.sender) {
                    revert BundleListingFacet__NotItemOwnerOrApproved();
                }
                // Proaktif onay kontrolü
                if (nft.getApproved(currentItem.tokenId) != address(this) && !nft.isApprovedForAll(msg.sender, address(this))) {
                    revert BundleListingFacet__ApprovalMissingForItem(currentItem.nftContractAddress, currentItem.tokenId);
                }
            } else if (currentItem.standard == MarketplaceStorage.TokenStandard.ERC1155) {
                if (currentItem.amount == 0) revert BundleListingFacet__InvalidAmount();
                IERC1155 nft = IERC1155(currentItem.nftContractAddress);
                if (nft.balanceOf(msg.sender, currentItem.tokenId) < currentItem.amount) {
                    revert BundleListingFacet__NotItemOwnerOrApproved();
                }
                // Proaktif onay kontrolü
                if (!nft.isApprovedForAll(msg.sender, address(this))) {
                    revert BundleListingFacet__ApprovalMissingForItem(currentItem.nftContractAddress, currentItem.tokenId);
                }
            } else {
                revert BundleListingFacet__InvalidAmount(); // Unsupported standard
            }
            itemsToStore[i] = MarketplaceStorage.NFTItem({
                nftContractAddress: currentItem.nftContractAddress,
                tokenId: currentItem.tokenId,
                standard: currentItem.standard,
                amount: currentItem.amount
            });
        }

        // --- Effects ---
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        uint256 bundleId = ms.nextBundleId++;

        ms.bundleListings[bundleId] = MarketplaceStorage.BundleListing({
            bundleId: bundleId,
            seller: payable(msg.sender),
            items: itemsToStore, // Use the validated and structured data
            price: _price,
            paymentToken: _paymentToken,
            isActive: true,
            creationTime: block.timestamp // creationTime ayarlandı
        });

        emit BundleListed(bundleId, msg.sender, itemsToStore, _price, _paymentToken);

        // --- Interactions ---
        // Transfer all items in the bundle to this contract (escrow)
        for (uint256 i = 0; i < itemsToStore.length; i++) {
            MarketplaceStorage.NFTItem memory item = itemsToStore[i];
            if (item.standard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721(item.nftContractAddress).transferFrom(msg.sender, address(this), item.tokenId);
            } else if (item.standard == MarketplaceStorage.TokenStandard.ERC1155) {
                IERC1155(item.nftContractAddress).safeTransferFrom(msg.sender, address(this), item.tokenId, item.amount, "");
            }
        }
    }

    /// @notice Cancel an active bundle listing.
    function cancelBundleListing(uint256 _bundleId) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.BundleListing storage bundle = ms.bundleListings[_bundleId];

        // --- Checks ---
        if (bundle.seller == address(0)) {
            revert BundleListingFacet__BundleNotFound();
        }
        if (bundle.seller != msg.sender) {
            revert BundleListingFacet__NotBundleSeller();
        }
        if (!bundle.isActive) {
            revert BundleListingFacet__BundleNotActive();
        }

        // --- Effects ---
        bundle.isActive = false;
        emit BundleCancelled(_bundleId);

        // --- Interactions ---
        // Return all items in the bundle to the seller
        for (uint256 i = 0; i < bundle.items.length; i++) {
            MarketplaceStorage.NFTItem memory item = bundle.items[i];
            if (item.standard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721(item.nftContractAddress).transferFrom(address(this), bundle.seller, item.tokenId);
            } else if (item.standard == MarketplaceStorage.TokenStandard.ERC1155) {
                IERC1155(item.nftContractAddress).safeTransferFrom(address(this), bundle.seller, item.tokenId, item.amount, "");
            }
        }
    }

    /// @notice Buy a listed bundle of NFTs.
    /// @dev Royalty for each item is calculated based on an equal share of the total bundle price (totalPrice / numberOfItems).
    /// This is a simplification and may not accurately reflect individual item values or intended royalty distributions
    /// for bundles with disparately valued items. The marketplace fee is calculated on the total bundle price.
    function buyBundle(uint256 _bundleId) external payable nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.BundleListing storage bundle = ms.bundleListings[_bundleId]; // Load into storage to modify isActive

        // --- Checks ---
        if (bundle.seller == address(0)) {
            revert BundleListingFacet__BundleNotFound();
        }
        if (!bundle.isActive) {
            revert BundleListingFacet__BundleNotActive();
        }

        uint256 totalPrice = bundle.price;
        address paymentTokenAddress = bundle.paymentToken;
        address buyer = msg.sender; // Cache msg.sender

        if (paymentTokenAddress == address(0)) { // ETH payment
            if (msg.value < totalPrice) {
                revert BundleListingFacet__PriceNotMet();
            }
        } else { // ERC20 payment
            if (msg.value > 0) { // Should not send ETH for ERC20 listings
                revert BundleListingFacet__PaymentTokenNotSupported();
            }
            // ERC20 balance/allowance check will be done by safeTransferFrom in Interactions
        }
        
        // Clone items from storage to memory to avoid SLOADs in loop & modification issues
        MarketplaceStorage.NFTItem[] memory itemsInBundle = new MarketplaceStorage.NFTItem[](bundle.items.length);
        for(uint i = 0; i < bundle.items.length; i++){
            itemsInBundle[i] = bundle.items[i];
        }

        uint256 totalRoyaltyToPay = 0;
        // Using dynamic arrays for royalty details as not all items might have royalties
        address[] memory royaltyRecipients = new address[](itemsInBundle.length);
        uint256[] memory royaltyAmounts = new uint256[](itemsInBundle.length);
        uint256 actualRoyaltyCount = 0;
        uint256 totalNetPriceForSeller = 0; // Net price calculation after royalty for each item can be complex here

        if (itemsInBundle.length > 0) { // Avoid division by zero if bundle somehow has 0 items (though check exists in listBundle)
            uint256 itemPriceShare = totalPrice / itemsInBundle.length; 

            for (uint256 i = 0; i < itemsInBundle.length; i++) {
                MarketplaceStorage.NFTItem memory item = itemsInBundle[i];
                try IERC165(item.nftContractAddress).supportsInterface(type(IERC2981).interfaceId) returns (bool supportsRoyalty) {
                    if (supportsRoyalty) {
                        (address recipient, uint256 amount) = IERC2981(item.nftContractAddress).royaltyInfo(item.tokenId, itemPriceShare);
                        if (recipient != address(0) && amount > 0) {
                            if (amount <= itemPriceShare) { 
                                royaltyRecipients[actualRoyaltyCount] = recipient;
                                royaltyAmounts[actualRoyaltyCount] = amount;
                                totalRoyaltyToPay += amount;
                                actualRoyaltyCount++;
                            } else {
                                // Royalty amount exceeds the item's share of the price.
                                emit BundleItemRoyaltyExceedsPriceShare(_bundleId, item.nftContractAddress, item.tokenId, itemPriceShare, amount);
                                // Do not add this royalty; it effectively becomes 0 for this item.
                            }
                        }
                    }
                } catch Error(string memory reason) {
                    emit BundleItemRoyaltyInfoRetrievalFailed(_bundleId, item.nftContractAddress, item.tokenId, reason);
                    // Continue to next item, royalty for this item will be 0.
                } catch {
                    emit BundleItemRoyaltyInfoRetrievalFailed(_bundleId, item.nftContractAddress, item.tokenId, "Unknown reason");
                    // Continue to next item, royalty for this item will be 0.
                }
            }
        }

        uint256 marketplaceFee = 0;
        if (ms.marketplaceFeePercent > 0) {
            marketplaceFee = (totalPrice * ms.marketplaceFeePercent) / 10000; // Fee on total price before royalties
        }

        // Seller proceeds calculation needs to be careful if individual item royalties were capped
        // The `totalRoyaltyToPay` sums up actual royalties paid (which might be less than theoretical if capped)
        uint256 priceForFeeAndSeller = totalPrice - totalRoyaltyToPay;
        if (marketplaceFee > priceForFeeAndSeller) {
             marketplaceFee = priceForFeeAndSeller;
        }
        uint256 sellerProceeds = priceForFeeAndSeller - marketplaceFee;

        // --- Effects ---
        bundle.isActive = false; // Mark bundle as sold
        // Note: seller, buyer, price, paymentToken are read from bundle storage or msg
        emit BundleSold(_bundleId, bundle.seller, buyer, totalPrice, paymentTokenAddress);

        // --- Interactions ---
        if (paymentTokenAddress == address(0)) { // ETH payment
            // 1. Pay Royalties
            for (uint256 i = 0; i < actualRoyaltyCount; i++) {
                if (royaltyAmounts[i] > 0) { // Check just in case, though already filtered
                    (bool successRoyalty, ) = payable(royaltyRecipients[i]).call{value: royaltyAmounts[i]}("");
                    if (!successRoyalty) revert BundleListingFacet__RoyaltyPaymentFailed();
                }
            }
            // 2. Pay Marketplace Fee
            if (marketplaceFee > 0 && ms.feeRecipient != address(0)) {
                (bool successFee, ) = ms.feeRecipient.call{value: marketplaceFee}("");
                if (!successFee) revert BundleListingFacet__TransferFailed(); // Generic transfer fail
            }
            // 3. Pay Seller
            if (sellerProceeds > 0) { // Only send if there are proceeds
                (bool successSeller, ) = bundle.seller.call{value: sellerProceeds}("");
                if (!successSeller) revert BundleListingFacet__TransferFailed();
            }
            // 4. Refund excess ETH, if any
            if (msg.value > totalPrice) {
                (bool successRefund, ) = payable(buyer).call{value: msg.value - totalPrice}("");
                if (!successRefund) { /* Optional: Log or revert. For now, best effort refund. */ }
            }
        } else { // ERC20 payment
            IERC20 token = IERC20(paymentTokenAddress);
            // 1. Collect full price
            token.safeTransferFrom(buyer, address(this), totalPrice);

            // 2. Pay Royalties (Iterate through actual royalties stored)
            for (uint256 i = 0; i < actualRoyaltyCount; i++) {
                if (royaltyRecipients[i] != address(0) && royaltyAmounts[i] > 0) {
                    token.safeTransfer(royaltyRecipients[i], royaltyAmounts[i]);
                }
            }
            // 3. Pay Marketplace Fee
            if (marketplaceFee > 0 && ms.feeRecipient != address(0)) {
                token.safeTransfer(ms.feeRecipient, marketplaceFee);
            }
            // 4. Pay Seller
            if (sellerProceeds > 0) {
                token.safeTransfer(bundle.seller, sellerProceeds);
            }
        }

        // 5. Transfer all NFTs in the bundle from this contract to the buyer
        for (uint256 i = 0; i < itemsInBundle.length; i++) {
            MarketplaceStorage.NFTItem memory item = itemsInBundle[i];
            if (item.standard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721(item.nftContractAddress).transferFrom(address(this), buyer, item.tokenId);
            } else if (item.standard == MarketplaceStorage.TokenStandard.ERC1155) {
                IERC1155(item.nftContractAddress).safeTransferFrom(address(this), buyer, item.tokenId, item.amount, "");
            }
        }
    }

    // Read-only function to get bundle details
    function getBundleListing(uint256 _bundleId) external view returns (MarketplaceStorage.BundleListing memory) {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        return ms.bundleListings[_bundleId];
    }

    function getBundleItems(uint256 _bundleId) external view returns (MarketplaceStorage.NFTItem[] memory) {
        return MarketplaceStorage.marketplaceStorage().bundleListings[_bundleId].items;
    }
} 