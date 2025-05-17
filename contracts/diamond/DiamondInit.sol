// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {LibDiamond} from "./libraries/LibDiamond.sol";
import {MarketplaceStorage} from "../libraries/MarketplaceStorage.sol";
import {IDiamondLoupe} from "./interfaces/IDiamondLoupe.sol";
import {IERC165} from "./interfaces/IERC165.sol";
import {IERC173} from "./interfaces/IERC173.sol"; // Sahiplik için
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol"; // Ekledik
import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol"; // Yeni eklendi

contract DiamondInit {
    bool private _initialized;

    event InitialMarketplaceFeePercentInvalid(uint256 providedPercent, uint256 maxPercent);

    modifier initializer() {
        require(!_initialized, "DiamondInit: Already initialized");
        _initialized = true;
        _;
    }

    /// @notice Initializes the diamond contract and marketplace settings.
    /// @param _initialOwner The initial owner of the diamond and fee recipient.
    /// @param _initialMarketplaceFeePercent The initial marketplace fee (e.g., 250 for 2.5%).
    /// @param _wethTokenAddress Address of the WETH token contract.
    function init(
        address payable _initialOwner, // Hem diamond owner hem de ilk fee recipient olabilir
        uint256 _initialMarketplaceFeePercent,
        address _wethTokenAddress // Yeni parametre
    ) external initializer {
        // Set Diamond Owner (already done by Diamond constructor using LibDiamond.setContractOwner)
        // However, DiamondInit is called via delegatecall, so msg.sender would be the Diamond itself.
        // The owner is typically set in the Diamond's constructor.
        // If we need to ensure it here or change it, we'd need to pass the owner to LibDiamond.setContractOwner.
        // For now, we assume the Diamond constructor handles initial ownership set by LibDiamond.setContractOwner(deployer).

        // Initialize Marketplace Storage
        MarketplaceStorage.Storage storage ms = MarketplaceStorage.marketplaceStorage();
        require(_initialOwner != address(0), "DiamondInit: Initial owner cannot be zero address");
        require(_wethTokenAddress != address(0), "DiamondInit: WETH address cannot be zero address");
        ms.feeRecipient = _initialOwner; // Başlangıçta ücretler deploy eden kişiye gitsin
        
        uint256 MAX_FEE_PERCENT = 10000;
        if (_initialMarketplaceFeePercent > MAX_FEE_PERCENT) {
            emit InitialMarketplaceFeePercentInvalid(_initialMarketplaceFeePercent, MAX_FEE_PERCENT);
            revert("DiamondInit: Initial marketplace fee percent exceeds maximum");
        } else {
            ms.marketplaceFeePercent = _initialMarketplaceFeePercent;
        }
        ms.wethTokenAddress = _wethTokenAddress; // WETH adresini ayarla
        
        // Initialize ID counters
        ms.nextListingId = 1; 
        ms.nextOfferId = 1; 
        ms.nextBundleId = 1; 
        ms.nextCollectionOfferId = 1; 

        // Initialize supported interfaces for ERC165
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IERC173).interfaceId] = true; // Diamond sahipliğini destekler
        ds.supportedInterfaces[type(IERC721Receiver).interfaceId] = true; // ERC721ReceiverFacet eklendiğinde
        ds.supportedInterfaces[type(IERC1155Receiver).interfaceId] = true; // ERC1155ReceiverFacet eklendiğinde
        // Add other interfaces your diamond will support through its facets
        // ÖNEMLİ NOT: Facet eklemeleri (diamondCut) ve bunlara karşılık gelen 
        // ds.supportedInterfaces güncellemeleri genellikle bu init fonksiyonu dışında,
        // bir dağıtım (deployment) script'i veya sonraki bir sahiplik işlemi ile yapılır.
        // Bu init fonksiyonu genellikle temel depolama ve sahiplik ayarları için kullanılır.
        // Burada eklenen arayüzler, DiamondLoupeFacet'in doğru çalışması için temel olanlardır.
    }
} 