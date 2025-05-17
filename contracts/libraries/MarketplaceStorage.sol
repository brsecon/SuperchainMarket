// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

library MarketplaceStorage {
    bytes32 constant MARKETPLACE_STORAGE_POSITION = keccak256("diamond.standard.marketplace.storage.v7"); // v6 -> v7 (new offer tracking)

    enum TokenStandard { ERC721, ERC1155 }
    enum OfferStatus { Pending, Accepted, Rejected, Cancelled, Expired } // Expired daha sonra eklenebilir
    enum OfferType { WETH, NFT } // Yeni enum: Teklif tipini belirtir

    struct Listing {
        address nftContractAddress;
        uint256 tokenId;
        TokenStandard standard; // ERC721 veya ERC1155
        uint256 amount; // ERC1155 için listelenen miktar, ERC721 için her zaman 1 olmalı
        address payable seller;
        uint256 price; // ETH veya paymentToken cinsinden toplam fiyat (ERC1155 için listelenen tüm amount için)
        address paymentToken; // address(0) for ETH
        bool isActive;
    }

    struct Offer {
        uint256 offerId;
        address nftContractAddress; // Hedeflenen NFT
        uint256 tokenId;            // Hedeflenen NFT
        MarketplaceStorage.TokenStandard tokenStandard; // Hedeflenen NFT'nin standardı
        uint256 amountToBuy;        // Hedeflenen ERC1155 NFT'den alınmak istenen miktar (ERC721 için 1)
        address payable offerer;
        OfferStatus status;
        uint256 expirationTimestamp; // Opsiyonel

        OfferType offerType;        // Teklifin türü: WETH mi, NFT mi?

        // WETH ile teklif için
        uint256 offeredAmountWETH;

        // NFT ile teklif için
        address offeredNftContractAddress; // Teklif olarak sunulan NFT
        uint256 offeredNftTokenId;         // Teklif olarak sunulan NFT
        TokenStandard offeredNftStandard;  // Teklif olarak sunulan NFT'nin standardı
        uint256 offeredNftAmount;          // Teklif olarak sunulan ERC1155 NFT miktarı (ERC721 için 1)
    }

    // New struct for Collection Offers (Floor Offers for ERC721 collections)
    struct CollectionOffer {
        uint256 collectionOfferId;
        address nftContractAddress; // Target ERC721 collection address
        address payable offerer;
        uint256 offeredAmountWETH;
        OfferStatus status; // Pending, Accepted, Cancelled
        uint256 acceptedTokenId; // TokenId that fulfilled the offer (0 if not accepted)
        address payable acceptedBy; // Seller who accepted the offer (address(0) if not accepted)
        uint256 expirationTimestamp; // Optional for future use
    }

    // Struct to define an item within a bundle
    struct NFTItem {
        address nftContractAddress;
        uint256 tokenId;
        TokenStandard standard;
        uint256 amount; // For ERC1155, should be 1 for ERC721
    }

    // Struct for Bundle Listings
    struct BundleListing {
        uint256 bundleId;
        address payable seller;
        NFTItem[] items; // Array of NFTs in the bundle
        uint256 price; // Total price for the bundle
        address paymentToken; // address(0) for ETH
        bool isActive;
        uint256 creationTime; // Optional
    }

    struct Storage {
        // NFT kontrat adresi -> Token ID -> Listeleme Detayları
        // ERC1155 için aynı token ID'si birden fazla kez listelenemez (bu modelde)
        // Eğer aynı kullanıcı aynı ERC1155 tokenID'den farklı miktarlarda listelemek isterse, bu yapı yetersiz kalır.
        // Daha karmaşık senaryolar için listingId tabanlı bir yapı daha uygun olabilir.
        // Şimdilik (nftContractAddress, tokenId) çiftini anahtar olarak kullanmaya devam ediyoruz.
        mapping(address => mapping(uint256 => Listing)) listings;
        
        // Teklifler
        mapping(uint256 => Offer) offers; // offerId => Offer
        // Bir NFT için aktif teklif ID'lerini tutmak için (opsiyonel, temizlik için faydalı olabilir)
        mapping(address => mapping(uint256 => uint256[])) activeOfferIdsForItem; 
        mapping(uint256 => uint256) offerIdToArrayIndex; // offerId -> index in activeOfferIdsForItem array
        uint256 nextOfferId;
        uint256 nextListingId; // Eklendi

        mapping(uint256 => CollectionOffer) collectionOffers; // Collection offers
        uint256 nextCollectionOfferId; // Counter for collection offer IDs

        mapping(uint256 => BundleListing) bundleListings; // Bundle listings
        uint256 nextBundleId; // Counter for bundle listing IDs

        uint256 marketplaceFeePercent;
        address payable feeRecipient;
        address wethTokenAddress; // WETH kontrat adresi
    }

    function marketplaceStorage() internal pure returns (Storage storage ms) {
        bytes32 position = MARKETPLACE_STORAGE_POSITION;
        assembly {
            ms.slot := position
        }
    }
} 