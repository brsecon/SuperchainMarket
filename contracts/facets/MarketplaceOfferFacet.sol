// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {OfferLogicLib} from "../libraries/OfferLogicLib.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";

// Custom Errors
error MarketplaceOfferFacet__ZeroAddress();
error MarketplaceOfferFacet__InvalidAmount();
error MarketplaceOfferFacet__WETHTransferFailed();
error MarketplaceOfferFacet__OfferNotFound();
error MarketplaceOfferFacet__NotOfferer();
error MarketplaceOfferFacet__OfferNotPending();
error MarketplaceOfferFacet__NotNFTOwnerOrApproved();
error MarketplaceOfferFacet__NFTTransferFailed();
error MarketplaceOfferFacet__ListingNotFoundOrInactive();
error MarketplaceOfferFacet__CallerNotSellerOrApproved();
error MarketplaceOfferFacet__WETHAddressNotSet();
error MarketplaceOfferFacet__AlreadyProcessed();
error MarketplaceOfferFacet__ERC1155AmountMismatch();
error MarketplaceOfferFacet__SelfOffer();
error MarketplaceOfferFacet__OfferTypeMismatch();
error MarketplaceOfferFacet__InsufficientOfferedNFTBalance();
error MarketplaceOfferFacet__OfferedNFTTransferFailed();
error MarketplaceOfferFacet__TargetNFTTransferFailed();
error MarketplaceOfferFacet__MarketplaceNotApprovedForOfferedNFT();
error MarketplaceOfferFacet__MarketplaceNotApprovedForTargetNFT();
error MarketplaceOfferFacet__RoyaltyPaymentFailed();
error MarketplaceOfferFacet__UnsupportedNFTContractForRoyalty();
error MarketplaceOfferFacet__OfferExpired();
error MarketplaceOfferFacet__InvalidExpirationTimestamp();

// Royalty hataları için yeni eventler (MarketplaceBuyingFacet'ten kopyalandı, gerekirse ortak bir yere taşınabilir)
event RoyaltyInfoRetrievalFailed(address indexed nftContractAddress, uint256 indexed tokenId, string reason);
event RoyaltyExceedsPrice(address indexed nftContractAddress, uint256 indexed tokenId, uint256 price, uint256 royaltyAmount);

contract MarketplaceOfferFacet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    event WETHOfferMade(
        uint256 indexed offerId,
        address indexed nftContractAddress,
        uint256 indexed tokenId,
        MarketplaceStorage.TokenStandard tokenStandard,
        uint256 amountToBuy,
        address offerer,
        uint256 offeredAmountWETH,
        uint256 expirationTimestamp
    );

    event NFTOfferMade(
        uint256 indexed offerId,
        address indexed targetNftContractAddress,
        uint256 indexed targetNftTokenId,
        MarketplaceStorage.TokenStandard targetTokenStandard,
        uint256 targetAmountToBuy,
        address offerer,
        address offeredNftContractAddress,
        uint256 offeredNftTokenId,
        MarketplaceStorage.TokenStandard offeredTokenStandard,
        uint256 offeredAmount,
        uint256 expirationTimestamp
    );

    event OfferCancelled(
        uint256 indexed offerId,
        MarketplaceStorage.OfferType offerType
    );

    event OfferAccepted(
        uint256 indexed offerId,
        MarketplaceStorage.OfferType offerType,
        address indexed nftContractAddress,
        uint256 indexed tokenId,
        address seller,
        address buyer,
        uint256 price,
        address royaltyRecipient,
        uint256 royaltyAmountPaid
    );

    /// @notice Make an offer for an NFT using WETH.
    /// @dev User must have approved WETH to this contract.
    function makeWETHOffer(
        address _nftContractAddress,
        uint256 _tokenId,
        MarketplaceStorage.TokenStandard _tokenStandard,
        uint256 _amountToBuy,
        uint256 _offeredAmountWETH,
        uint256 _expirationTimestamp
    ) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        if (ms.wethTokenAddress == address(0)) revert MarketplaceOfferFacet__WETHAddressNotSet();
        if (_nftContractAddress == address(0)) revert MarketplaceOfferFacet__ZeroAddress();
        if (_offeredAmountWETH == 0) revert MarketplaceOfferFacet__InvalidAmount();
        if (_tokenStandard == MarketplaceStorage.TokenStandard.ERC721 && _amountToBuy != 1) revert MarketplaceOfferFacet__InvalidAmount();
        if (_tokenStandard == MarketplaceStorage.TokenStandard.ERC1155 && _amountToBuy == 0) revert MarketplaceOfferFacet__InvalidAmount();
        if (_expirationTimestamp <= block.timestamp) revert MarketplaceOfferFacet__InvalidExpirationTimestamp();

        IERC20(ms.wethTokenAddress).safeTransferFrom(msg.sender, address(this), _offeredAmountWETH);

        uint256 offerId = ms.nextOfferId++;
        ms.offers[offerId] = MarketplaceStorage.Offer({
            offerId: offerId,
            nftContractAddress: _nftContractAddress,
            tokenId: _tokenId,
            tokenStandard: _tokenStandard,
            amountToBuy: _amountToBuy,
            offerer: payable(msg.sender),
            status: MarketplaceStorage.OfferStatus.Pending,
            expirationTimestamp: _expirationTimestamp,
            offerType: MarketplaceStorage.OfferType.WETH,
            offeredAmountWETH: _offeredAmountWETH,
            offeredNftContractAddress: address(0),
            offeredNftTokenId: 0,
            offeredNftStandard: MarketplaceStorage.TokenStandard.ERC721, 
            offeredNftAmount: 0
        });
        
        OfferLogicLib.addOfferToActiveForItem(ms, offerId, _nftContractAddress, _tokenId);
        emit WETHOfferMade(offerId, _nftContractAddress, _tokenId, _tokenStandard, _amountToBuy, msg.sender, _offeredAmountWETH, _expirationTimestamp);
    }

    /// @notice Make an offer for a target NFT by offering another NFT (barter/swap).
    /// @dev User must have approved their NFT to this contract for transfer.
    function makeNFTOffer(
        address _targetNftContractAddress,
        uint256 _targetNftTokenId,
        MarketplaceStorage.TokenStandard _targetNftStandard,
        uint256 _targetAmountToBuy, 
        address _offeredNftContractAddress,
        uint256 _offeredNftTokenId,
        MarketplaceStorage.TokenStandard _offeredNftStandard,
        uint256 _offeredNftAmount,
        uint256 _expirationTimestamp
    ) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        if (_targetNftContractAddress == address(0) || _offeredNftContractAddress == address(0)) revert MarketplaceOfferFacet__ZeroAddress();
        if ((_targetNftStandard == MarketplaceStorage.TokenStandard.ERC721 && _targetAmountToBuy != 1) ||
            (_targetNftStandard == MarketplaceStorage.TokenStandard.ERC1155 && _targetAmountToBuy == 0)) revert MarketplaceOfferFacet__InvalidAmount();
        if ((_offeredNftStandard == MarketplaceStorage.TokenStandard.ERC721 && _offeredNftAmount != 1) ||
            (_offeredNftStandard == MarketplaceStorage.TokenStandard.ERC1155 && _offeredNftAmount == 0)) revert MarketplaceOfferFacet__InvalidAmount(); 
        if (_expirationTimestamp <= block.timestamp) revert MarketplaceOfferFacet__InvalidExpirationTimestamp();

        if (_offeredNftStandard == MarketplaceStorage.TokenStandard.ERC721) {
            IERC721 offeredNft = IERC721(_offeredNftContractAddress);
            if (offeredNft.ownerOf(_offeredNftTokenId) != msg.sender) revert MarketplaceOfferFacet__NotNFTOwnerOrApproved(); 
            // Ensure marketplace is approved for the offered NFT
            if (offeredNft.getApproved(_offeredNftTokenId) != address(this) && !offeredNft.isApprovedForAll(msg.sender, address(this))) {
                revert MarketplaceOfferFacet__MarketplaceNotApprovedForOfferedNFT();
            }
            offeredNft.transferFrom(msg.sender, address(this), _offeredNftTokenId);
        } else { 
            IERC1155 offeredNft = IERC1155(_offeredNftContractAddress);
            if (offeredNft.balanceOf(msg.sender, _offeredNftTokenId) < _offeredNftAmount) revert MarketplaceOfferFacet__InsufficientOfferedNFTBalance();
            // Ensure marketplace is approved for the offered NFT
            if (!offeredNft.isApprovedForAll(msg.sender, address(this))) {
                revert MarketplaceOfferFacet__MarketplaceNotApprovedForOfferedNFT();
            }
            offeredNft.safeTransferFrom(msg.sender, address(this), _offeredNftTokenId, _offeredNftAmount, "");
        }

        uint256 offerId = ms.nextOfferId++;
        ms.offers[offerId] = MarketplaceStorage.Offer({
            offerId: offerId,
            nftContractAddress: _targetNftContractAddress,
            tokenId: _targetNftTokenId,
            tokenStandard: _targetNftStandard,
            amountToBuy: _targetAmountToBuy,
            offerer: payable(msg.sender),
            status: MarketplaceStorage.OfferStatus.Pending,
            expirationTimestamp: _expirationTimestamp,
            offerType: MarketplaceStorage.OfferType.NFT,
            offeredAmountWETH: 0,
            offeredNftContractAddress: _offeredNftContractAddress,
            offeredNftTokenId: _offeredNftTokenId,
            offeredNftStandard: _offeredNftStandard,
            offeredNftAmount: _offeredNftAmount
        });

        OfferLogicLib.addOfferToActiveForItem(ms, offerId, _targetNftContractAddress, _targetNftTokenId);
        emit NFTOfferMade(offerId, _targetNftContractAddress, _targetNftTokenId, _targetNftStandard, _targetAmountToBuy, msg.sender, _offeredNftContractAddress, _offeredNftTokenId, _offeredNftStandard, _offeredNftAmount, _expirationTimestamp);
    }

    /// @notice Cancels a pending offer made by the caller.
    function cancelOffer(uint256 _offerId) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        OfferLogicLib.cancelSpecificOffer(ms, _offerId, msg.sender);
    }

    /// @notice Accepts a pending offer for an NFT.
    /// @dev If the target NFT is not listed, the caller (msg.sender) must be the owner and must have approved the Diamond contract for the NFT transfer.
    function acceptOffer(uint256 _offerId) external nonReentrant {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.Offer storage offer = ms.offers[_offerId];

        if (offer.offerer == address(0)) revert MarketplaceOfferFacet__OfferNotFound();
        if (offer.status != MarketplaceStorage.OfferStatus.Pending) revert MarketplaceOfferFacet__AlreadyProcessed();
        if (offer.expirationTimestamp != 0 && block.timestamp >= offer.expirationTimestamp) {
            revert MarketplaceOfferFacet__OfferExpired();
        }
        if (offer.offerer == msg.sender) revert MarketplaceOfferFacet__SelfOffer(); 

        MarketplaceStorage.Listing storage listing = ms.listings[offer.nftContractAddress][offer.tokenId];
        bool isListed = listing.isActive && listing.seller != address(0);
        address payable sellerOrTargetOwner; 

        if (isListed) {
            if (listing.seller != msg.sender) revert MarketplaceOfferFacet__CallerNotSellerOrApproved();
            sellerOrTargetOwner = listing.seller;
        } else {
            if (offer.tokenStandard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721 targetNftContract = IERC721(offer.nftContractAddress);
                if (targetNftContract.ownerOf(offer.tokenId) != msg.sender) revert MarketplaceOfferFacet__NotNFTOwnerOrApproved();
                if (targetNftContract.getApproved(offer.tokenId) != address(this) && !targetNftContract.isApprovedForAll(msg.sender, address(this))) {
                    revert MarketplaceOfferFacet__MarketplaceNotApprovedForTargetNFT();
                }
            } else { 
                IERC1155 targetNftContract = IERC1155(offer.nftContractAddress);
                if (targetNftContract.balanceOf(msg.sender, offer.tokenId) < offer.amountToBuy) revert MarketplaceOfferFacet__NotNFTOwnerOrApproved();
                if (!targetNftContract.isApprovedForAll(msg.sender, address(this))) revert MarketplaceOfferFacet__MarketplaceNotApprovedForTargetNFT();
            }
            sellerOrTargetOwner = payable(msg.sender);
        }
        
        address offerNftContractAddress_cache = offer.nftContractAddress; 
        uint256 offerTokenId_cache = offer.tokenId;

        offer.status = MarketplaceStorage.OfferStatus.Accepted;
        OfferLogicLib.removeOfferFromActiveForItem(ms, _offerId, offerNftContractAddress_cache, offerTokenId_cache); // Remove accepted offer from active list

        MarketplaceStorage.OfferType offerType = offer.offerType;
        uint256 priceForEvent = 0;
        address royaltyRecipient = address(0);
        uint256 royaltyAmountPaid = 0;

        // --- Interactions & Payments --- 
        if (offerType == MarketplaceStorage.OfferType.WETH) {
            if (ms.wethTokenAddress == address(0)) revert MarketplaceOfferFacet__WETHAddressNotSet();
            uint256 offeredWETH = offer.offeredAmountWETH;
            priceForEvent = offeredWETH;

            try IERC165(offer.nftContractAddress).supportsInterface(type(IERC2981).interfaceId) returns (bool supportsRoyalty) {
                if (supportsRoyalty) {
                    (address recipient, uint256 amount) = IERC2981(offer.nftContractAddress).royaltyInfo(offer.tokenId, offeredWETH);
                    if (recipient != address(0) && amount > 0 && amount < offeredWETH) {
                        royaltyRecipient = recipient;
                        royaltyAmountPaid = amount;
                    } else if (amount >= offeredWETH) {
                        emit RoyaltyExceedsPrice(offer.nftContractAddress, offer.tokenId, offeredWETH, amount);
                        // royaltyAmountPaid 0 kalır
                    }
                }
            } catch Error(string memory reason) {
                emit RoyaltyInfoRetrievalFailed(offer.nftContractAddress, offer.tokenId, reason);
                // royaltyAmountPaid 0 kalır
            } catch {
                emit RoyaltyInfoRetrievalFailed(offer.nftContractAddress, offer.tokenId, "Unknown reason");
                // royaltyAmountPaid 0 kalır
            }

            uint256 remainingWETHAfterRoyalty = offeredWETH - royaltyAmountPaid;
            uint256 marketplaceFee = (offeredWETH * ms.marketplaceFeePercent) / 10000;
            if (marketplaceFee > remainingWETHAfterRoyalty) marketplaceFee = remainingWETHAfterRoyalty;
            uint256 sellerProceeds = remainingWETHAfterRoyalty - marketplaceFee;

            IERC20 weth = IERC20(ms.wethTokenAddress);
            if (royaltyAmountPaid > 0 && royaltyRecipient != address(0)) weth.safeTransfer(royaltyRecipient, royaltyAmountPaid);
            if (marketplaceFee > 0 && ms.feeRecipient != address(0)) weth.safeTransfer(ms.feeRecipient, marketplaceFee);
            if (sellerProceeds > 0) weth.safeTransfer(sellerOrTargetOwner, sellerProceeds);

            // Transfer Target NFT to Offerer (Buyer)
            if (offer.tokenStandard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721(offer.nftContractAddress).transferFrom(isListed ? address(this) : sellerOrTargetOwner, offer.offerer, offer.tokenId);
            } else { 
                IERC1155(offer.nftContractAddress).safeTransferFrom(isListed ? address(this) : sellerOrTargetOwner, offer.offerer, offer.tokenId, offer.amountToBuy, "");
            }
        } else if (offerType == MarketplaceStorage.OfferType.NFT) {
            // Transfer Target NFT to Offerer (Buyer)
            if (offer.tokenStandard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721(offer.nftContractAddress).transferFrom(isListed ? address(this) : sellerOrTargetOwner, offer.offerer, offer.tokenId);
            } else { 
                IERC1155(offer.nftContractAddress).safeTransferFrom(isListed ? address(this) : sellerOrTargetOwner, offer.offerer, offer.tokenId, offer.amountToBuy, "");
            }
            // Transfer Offered NFT (from Diamond's escrow) to sellerOrTargetOwner (Seller of Target NFT)
            if (offer.offeredNftStandard == MarketplaceStorage.TokenStandard.ERC721) {
                IERC721 offeredNft = IERC721(offer.offeredNftContractAddress);
                if(offeredNft.ownerOf(offer.offeredNftTokenId) == address(this)){
                    offeredNft.transferFrom(address(this), sellerOrTargetOwner, offer.offeredNftTokenId);
                }
            } else { 
                IERC1155 offeredNft = IERC1155(offer.offeredNftContractAddress);
                 if(offeredNft.balanceOf(address(this), offer.offeredNftTokenId) >= offer.offeredNftAmount){
                    offeredNft.safeTransferFrom(address(this), sellerOrTargetOwner, offer.offeredNftTokenId, offer.offeredNftAmount, "");
                }
            }
        }

        if (isListed) listing.isActive = false; 

        emit OfferAccepted(_offerId, offerType, offer.nftContractAddress, offer.tokenId, sellerOrTargetOwner, offer.offerer, priceForEvent, royaltyRecipient, royaltyAmountPaid);
        OfferLogicLib.cancelAllPendingOffersForItem(ms, offerNftContractAddress_cache, offerTokenId_cache);
    }

    function getOffer(uint256 _offerId) external view returns (MarketplaceStorage.Offer memory) {
        return MarketplaceStorage.marketplaceStorage().offers[_offerId];
    }
} 