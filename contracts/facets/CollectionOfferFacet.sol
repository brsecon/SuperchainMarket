// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

// Custom Errors
error CollectionOfferFacet__ZeroAddress();
error CollectionOfferFacet__InvalidAmountWETH();
error CollectionOfferFacet__WETHAddressNotSet();
error CollectionOfferFacet__WETHTransferFailed(); // Note: SafeERC20 already reverts on failure
error CollectionOfferFacet__OfferNotFound();
error CollectionOfferFacet__NotOfferer();
error CollectionOfferFacet__OfferNotPending();
error CollectionOfferFacet__NotNFTOwner();
error CollectionOfferFacet__NFTTransferFailed(); // Note: transferFrom reverts on failure or if caller is not approved/owner
error CollectionOfferFacet__RoyaltyPaymentFailed(); // Note: SafeERC20 already reverts on failure
error CollectionOfferFacet__AlreadyProcessed();
error CollectionOfferFacet__CallerIsOfferer();
error CollectionOfferFacet__OfferExpired();
error CollectionOfferFacet__InvalidExpirationTimestamp();

// Royalty hataları için yeni eventler
event CollectionOfferRoyaltyInfoFailed(uint256 indexed collectionOfferId, address indexed nftContractAddress, uint256 tokenId, string reason);
event CollectionOfferRoyaltyExceedsPrice(uint256 indexed collectionOfferId, address indexed nftContractAddress, uint256 tokenId, uint256 price, uint256 royaltyAmount);

contract CollectionOfferFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event CollectionOfferMade(
        uint256 indexed collectionOfferId,
        address indexed nftContractAddress, // Target Collection
        address offerer,
        uint256 offeredAmountWETH,
        uint256 expirationTimestamp
    );

    event CollectionOfferCancelled(
        uint256 indexed collectionOfferId
    );

    event CollectionOfferAccepted(
        uint256 indexed collectionOfferId,
        address indexed nftContractAddress, // Target Collection
        uint256 indexed tokenIdSold,      // NFT sold to fulfill the offer
        address seller,                   // Who accepted and sold the NFT
        address buyer,                    // The original offerer
        uint256 priceWETH,                // WETH amount paid
        address royaltyRecipient,
        uint256 royaltyAmountPaid
    );

    /// @notice Make a collection offer (floor offer) for any ERC721 token from a specific collection using WETH.
    function makeCollectionOffer(
        address _nftContractAddress, // Target ERC721 collection
        uint256 _offeredAmountWETH,
        uint256 _expirationTimestamp
    ) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();

        // --- Checks ---
        if (ms.wethTokenAddress == address(0)) {
            revert CollectionOfferFacet__WETHAddressNotSet();
        }
        if (_nftContractAddress == address(0)) {
            revert CollectionOfferFacet__ZeroAddress();
        }
        if (_offeredAmountWETH == 0) {
            revert CollectionOfferFacet__InvalidAmountWETH();
        }
        if (_expirationTimestamp <= block.timestamp) {
            revert CollectionOfferFacet__InvalidExpirationTimestamp();
        }
        // Check WETH balance and allowance of msg.sender (implicitly handled by safeTransferFrom)

        // --- Effects ---
        uint256 collectionOfferId = ms.nextCollectionOfferId++;
        ms.collectionOffers[collectionOfferId] = MarketplaceStorage.CollectionOffer({
            collectionOfferId: collectionOfferId,
            nftContractAddress: _nftContractAddress,
            offerer: payable(msg.sender),
            offeredAmountWETH: _offeredAmountWETH,
            status: MarketplaceStorage.OfferStatus.Pending,
            acceptedTokenId: 0,
            acceptedBy: payable(address(0)),
            expirationTimestamp: _expirationTimestamp
        });

        emit CollectionOfferMade(collectionOfferId, _nftContractAddress, msg.sender, _offeredAmountWETH, _expirationTimestamp);

        // --- Interactions ---
        IERC20 weth = IERC20(ms.wethTokenAddress);
        // SafeERC20 will revert if transfer fails (e.g. insufficient balance or allowance)
        weth.safeTransferFrom(msg.sender, address(this), _offeredAmountWETH); // Escrow WETH
    }

    /// @notice Cancel a pending collection offer made by the caller.
    function cancelCollectionOffer(uint256 _collectionOfferId) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.CollectionOffer storage cOffer = ms.collectionOffers[_collectionOfferId];

        // --- Checks ---
        if (cOffer.offerer == address(0)) {
            revert CollectionOfferFacet__OfferNotFound();
        }
        if (cOffer.offerer != msg.sender) {
            revert CollectionOfferFacet__NotOfferer();
        }
        if (cOffer.status != MarketplaceStorage.OfferStatus.Pending) {
            revert CollectionOfferFacet__OfferNotPending();
        }
        if (ms.wethTokenAddress == address(0)) { // Check before potential interaction
            revert CollectionOfferFacet__WETHAddressNotSet();
        }

        // --- Effects ---
        cOffer.status = MarketplaceStorage.OfferStatus.Cancelled;
        emit CollectionOfferCancelled(_collectionOfferId);

        // --- Interactions ---
        if (cOffer.offeredAmountWETH > 0) { // Only attempt transfer if there's WETH to return
            IERC20 weth = IERC20(ms.wethTokenAddress);
            // SafeERC20 will revert if transfer fails
            weth.safeTransfer(cOffer.offerer, cOffer.offeredAmountWETH); // Return escrowed WETH
        }
    }

    /// @notice Accept a pending collection offer by selling an ERC721 token from that collection.
    /// @param _collectionOfferId The ID of the collection offer to accept.
    /// @param _tokenIdToSell The ID of the ERC721 token from the collection that the caller wishes to sell.
    /// @dev The caller (msg.sender) must be the owner of `_tokenIdToSell` and must have approved this contract (the Diamond) to transfer the token.
    function acceptCollectionOffer(
        uint256 _collectionOfferId,
        uint256 _tokenIdToSell
    ) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.CollectionOffer storage cOffer = ms.collectionOffers[_collectionOfferId];

        // --- Checks ---
        if (cOffer.offerer == address(0)) {
            revert CollectionOfferFacet__OfferNotFound();
        }
        if (cOffer.status != MarketplaceStorage.OfferStatus.Pending) {
            revert CollectionOfferFacet__AlreadyProcessed();
        }
        if (cOffer.expirationTimestamp != 0 && block.timestamp >= cOffer.expirationTimestamp) {
            revert CollectionOfferFacet__OfferExpired();
        }
        if (cOffer.offerer == msg.sender) {
            revert CollectionOfferFacet__CallerIsOfferer(); // Seller cannot be the offerer
        }
        if (ms.wethTokenAddress == address(0)) {
            revert CollectionOfferFacet__WETHAddressNotSet();
        }

        IERC721 nftContract = IERC721(cOffer.nftContractAddress);
        // ownerOf will revert if token does not exist or nftContractAddress is not an ERC721
        if (nftContract.ownerOf(_tokenIdToSell) != msg.sender) {
            revert CollectionOfferFacet__NotNFTOwner(); // Caller must own the token they are trying to sell
        }
        // msg.sender must have approved this contract to transfer the NFT
        // (implicitly checked by transferFrom during Interactions)

        uint256 priceWETH = cOffer.offeredAmountWETH;
        address royaltyRecipient = address(0);
        uint256 royaltyAmountPaid = 0;

        // EIP-2981 Royalty Check
        try IERC165(cOffer.nftContractAddress).supportsInterface(type(IERC2981).interfaceId) returns (bool supportsRoyalty) {
            if (supportsRoyalty) {
                (address recipient, uint256 amount) = IERC2981(cOffer.nftContractAddress).royaltyInfo(_tokenIdToSell, priceWETH);
                if (recipient != address(0) && amount > 0) {
                    if (amount < priceWETH) { // Royalty cannot exceed price and must be positive
                        royaltyRecipient = recipient;
                        royaltyAmountPaid = amount;
                    } else { // amount >= priceWETH
                        emit CollectionOfferRoyaltyExceedsPrice(_collectionOfferId, cOffer.nftContractAddress, _tokenIdToSell, priceWETH, amount);
                        // royaltyAmountPaid 0 olarak kalır
                    }
                }
            }
        } catch Error(string memory reason) {
            emit CollectionOfferRoyaltyInfoFailed(_collectionOfferId, cOffer.nftContractAddress, _tokenIdToSell, reason);
            // royaltyAmountPaid 0 olarak kalır
        } catch {
            emit CollectionOfferRoyaltyInfoFailed(_collectionOfferId, cOffer.nftContractAddress, _tokenIdToSell, "Unknown reason for royalty failure");
            // royaltyAmountPaid 0 olarak kalır
        }

        uint256 remainingWETHAfterRoyalty = priceWETH - royaltyAmountPaid;
        uint256 marketplaceFee = 0;
        if (ms.marketplaceFeePercent > 0) {
             marketplaceFee = (priceWETH * ms.marketplaceFeePercent) / 10000; // Fee on total WETH before royalty
        }

        if (marketplaceFee > remainingWETHAfterRoyalty) { // Fee cannot be more than what's left after royalty
            marketplaceFee = remainingWETHAfterRoyalty;
        }
        uint256 sellerProceeds = remainingWETHAfterRoyalty - marketplaceFee;
        // WETH for the offer is already escrowed in this contract.

        // --- Effects ---
        cOffer.status = MarketplaceStorage.OfferStatus.Accepted;
        cOffer.acceptedTokenId = _tokenIdToSell;
        cOffer.acceptedBy = payable(msg.sender); // The seller

        emit CollectionOfferAccepted(
            _collectionOfferId,
            cOffer.nftContractAddress,
            _tokenIdToSell,
            msg.sender, // seller
            cOffer.offerer, // buyer
            priceWETH,
            royaltyRecipient,
            royaltyAmountPaid
        );

        // --- Interactions ---
        IERC20 weth = IERC20(ms.wethTokenAddress);

        // 1. Pay Royalty
        if (royaltyAmountPaid > 0 && royaltyRecipient != address(0)) {
            // SafeERC20 will revert if transfer fails
            weth.safeTransfer(royaltyRecipient, royaltyAmountPaid);
        }

        // 2. Pay Marketplace Fee
        if (marketplaceFee > 0 && ms.feeRecipient != address(0)) {
            // SafeERC20 will revert if transfer fails
            weth.safeTransfer(ms.feeRecipient, marketplaceFee);
        }

        // 3. Pay Seller (msg.sender)
        if (sellerProceeds > 0) { // Check added to prevent sending 0 WETH
            // SafeERC20 will revert if transfer fails
            weth.safeTransfer(msg.sender, sellerProceeds);
        }

        // 4. Transfer NFT from seller (msg.sender) to offerer (cOffer.offerer)
        // Assumes msg.sender has approved this contract (the Diamond Proxy) for _tokenIdToSell.
        // transferFrom will revert if not approved, or if other conditions fail.
        nftContract.transferFrom(msg.sender, cOffer.offerer, _tokenIdToSell);
        
        // Note: Cancellation of other offers for _tokenIdToSell (e.g., specific item offers)
        // is not handled here to keep facets decoupled. Seller should manage their listings.
    }

    function getCollectionOffer(uint256 _collectionOfferId) external view returns (MarketplaceStorage.CollectionOffer memory) {
        return MarketplaceStorage.marketplaceStorage().collectionOffers[_collectionOfferId];
    }
} 