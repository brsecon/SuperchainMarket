// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC1155} from "@openzeppelin/contracts/token/ERC1155/IERC1155.sol"; // ERC1155 için import
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol"; // Eklendi

// Custom Errors
error MarketplaceListingFacet__NotTokenOwner();
error MarketplaceListingFacet__PriceMustBeGreaterThanZero();
error MarketplaceListingFacet__ItemNotListed();
error MarketplaceListingFacet__NotSeller();
error MarketplaceListingFacet__AlreadyListed();
error MarketplaceListingFacet__TransferFailed(); // Bu hata NFT transferleri için de kullanılabilir veya daha spesifik hatalar eklenebilir
error MarketplaceListingFacet__InvalidAmount();
error MarketplaceListingFacet__UnsupportedStandard();
error MarketplaceListingFacet__ApprovalMissing(); // Yeni Hata

contract MarketplaceListingFacet is ReentrancyGuard { // ReentrancyGuard miras alındı
    event ItemListed(
        address indexed nftContractAddress,
        uint256 indexed tokenId,
        MarketplaceStorage.TokenStandard standard,
        uint256 amount, // ERC1155 için, ERC721 için 1
        address seller,
        uint256 price,
        address paymentToken
    );

    event ItemCancelled(
        address indexed nftContractAddress,
        uint256 indexed tokenId,
        MarketplaceStorage.TokenStandard standard,
        uint256 amount, // ERC1155 için, ERC721 için 1
        address seller
    );

    /// @notice List an NFT (ERC721 or ERC1155) for sale
    /// @param _nftContractAddress Address of the NFT contract
    /// @param _tokenId ID of the NFT to list
    /// @param _standard Token standard (0 for ERC721, 1 for ERC1155)
    /// @param _amount Amount of tokens to list (for ERC1155, should be 1 for ERC721)
    /// @param _price Sale price for the total amount (in ETH or paymentToken decimals)
    /// @param _paymentToken Address of the ERC20 token for payment (address(0) for ETH)
    function listItem(
        address _nftContractAddress,
        uint256 _tokenId,
        MarketplaceStorage.TokenStandard _standard,
        uint256 _amount,
        uint256 _price,
        address _paymentToken
    ) external nonReentrant { // nonReentrant eklendi
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        
        // --- Checks ---
        if (_price == 0) {
            revert MarketplaceListingFacet__PriceMustBeGreaterThanZero();
        }
        if (ms.listings[_nftContractAddress][_tokenId].isActive) {
            revert MarketplaceListingFacet__AlreadyListed();
        }

        if (_standard == MarketplaceStorage.TokenStandard.ERC721) {
            if (_amount != 1) {
                revert MarketplaceListingFacet__InvalidAmount();
            }
            IERC721 nftContract = IERC721(_nftContractAddress);
            if (nftContract.ownerOf(_tokenId) != msg.sender) {
                revert MarketplaceListingFacet__NotTokenOwner();
            }
            // Onay (approval) kontrolü eklendi
            if (nftContract.getApproved(_tokenId) != address(this) && !nftContract.isApprovedForAll(msg.sender, address(this))) {
                revert MarketplaceListingFacet__ApprovalMissing();
            }
        } else if (_standard == MarketplaceStorage.TokenStandard.ERC1155) {
            if (_amount == 0) {
                revert MarketplaceListingFacet__InvalidAmount();
            }
            IERC1155 nftContract = IERC1155(_nftContractAddress);
            if (nftContract.balanceOf(msg.sender, _tokenId) < _amount) {
                revert MarketplaceListingFacet__NotTokenOwner();
            }
            // Onay (approval) kontrolü eklendi
            if (!nftContract.isApprovedForAll(msg.sender, address(this))) {
                revert MarketplaceListingFacet__ApprovalMissing();
            }
        } else {
            revert MarketplaceListingFacet__UnsupportedStandard();
        }

        // --- Effects ---
        ms.listings[_nftContractAddress][_tokenId] = MarketplaceStorage.Listing({
            nftContractAddress: _nftContractAddress,
            tokenId: _tokenId,
            standard: _standard,
            amount: _amount,
            seller: payable(msg.sender),
            price: _price,
            paymentToken: _paymentToken,
            isActive: true
        });

        emit ItemListed(_nftContractAddress, _tokenId, _standard, _amount, msg.sender, _price, _paymentToken);

        // --- Interactions ---
        if (_standard == MarketplaceStorage.TokenStandard.ERC721) {
            IERC721(_nftContractAddress).transferFrom(msg.sender, address(this), _tokenId);
        } else if (_standard == MarketplaceStorage.TokenStandard.ERC1155) {
            IERC1155(_nftContractAddress).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, "");
        }
        // UnsupportedStandard durumu zaten yukarıda kontrol edildiği için buraya tekrar eklemeye gerek yok.
    }

    /// @notice Cancel an active listing
    /// @param _nftContractAddress Address of the NFT contract
    /// @param _tokenId ID of the NFT to cancel listing for
    function cancelItem(address _nftContractAddress, uint256 _tokenId) external nonReentrant { // nonReentrant eklendi
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        MarketplaceStorage.Listing storage listing = ms.listings[_nftContractAddress][_tokenId];

        // Checks
        if (!listing.isActive) {
            revert MarketplaceListingFacet__ItemNotListed();
        }
        if (listing.seller != msg.sender) {
            revert MarketplaceListingFacet__NotSeller();
        }

        // Effects
        listing.isActive = false;
        MarketplaceStorage.TokenStandard standard = listing.standard;
        uint256 amount = listing.amount;

        // Emit event before interactions
        emit ItemCancelled(_nftContractAddress, _tokenId, standard, amount, msg.sender);

        // Interactions
        if (standard == MarketplaceStorage.TokenStandard.ERC721) {
            IERC721 nftContract = IERC721(_nftContractAddress);
            // Check if contract still owns the token (it should, unless there's a bug elsewhere or direct manipulation)
            if (nftContract.ownerOf(_tokenId) == address(this)) {
                nftContract.transferFrom(address(this), listing.seller, _tokenId);
            }
        } else if (standard == MarketplaceStorage.TokenStandard.ERC1155) {
            IERC1155 nftContract = IERC1155(_nftContractAddress);
            // Check if contract still has the balance
            if (nftContract.balanceOf(address(this), _tokenId) >= amount) {
                nftContract.safeTransferFrom(address(this), listing.seller, _tokenId, amount, "");
            }
        } else {
             // This case should ideally not be reached if _standard was validated upon listing
             // but as a defensive measure, revert.
             revert MarketplaceListingFacet__UnsupportedStandard(); // Eklendi
        }
    }

    function getListing(address _nftContractAddress, uint256 _tokenId) external view returns (MarketplaceStorage.Listing memory) {
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        return ms.listings[_nftContractAddress][_tokenId];
    }
} 