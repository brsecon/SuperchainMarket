// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC1155Receiver} from "@openzeppelin/contracts/token/ERC1155/IERC1155Receiver.sol";
import {IERC165} from "../diamond/interfaces/IERC165.sol"; // supportsInterface için
import {LibDiamond} from "../diamond/libraries/LibDiamond.sol"; // supportedInterfaces kaydı için

/**
 * @title ERC1155ReceiverFacet
 * @dev Implementation of the {IERC1155Receiver} interface. This facet allows
 * the Diamond to receive ERC1155 tokens.
 */
contract ERC1155ReceiverFacet is IERC1155Receiver, IERC165 {

    /**
     * @dev Handles the receipt of a single ERC1155 token type.
     * See {IERC1155Receiver-onERC1155Received}.
     *
     * Always returns `IERC1155Receiver.onERC1155Received.selector`.
     */
    function onERC1155Received(
        address _operator,
        address _from,
        uint256 _id,
        uint256 _value,
        bytes calldata _data
    ) public view virtual override returns (bytes4) {
        // Burada gelen token ile ilgili özel bir mantık işletmek gerekirse eklenebilir.
        // Örneğin, sadece belirli kontratlardan gelen tokenları kabul etme vs.
        // Şimdilik sadece kabul ettiğimizi belirtiyoruz.
        return this.onERC1155Received.selector;
    }

    /**
     * @dev Handles the receipt of multiple ERC1155 token types.
     * See {IERC1155Receiver-onERC1155BatchReceived}.
     *
     * Always returns `IERC1155Receiver.onERC1155BatchReceived.selector`.
     */
    function onERC1155BatchReceived(
        address _operator,
        address _from,
        uint256[] calldata _ids,
        uint256[] calldata _values,
        bytes calldata _data
    ) public view virtual override returns (bytes4) {
        // Aynı şekilde, batch transferler için de özel mantıklar eklenebilir.
        return this.onERC1155BatchReceived.selector;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     * This facet anons itself as supporting IERC1155Receiver.
     * This function is automatically registered with DiamondInit during deployment usually.
     */
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        // LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        // return ds.supportedInterfaces[interfaceId] || interfaceId == type(IERC1155Receiver).interfaceId;
        // Veya doğrudan true döndürülür ve DiamondInit'te kaydedilir:
        return interfaceId == type(IERC1155Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    // Bu facet deploy edilirken, DiamondInit içinde veya deploy script'inde
    // ds.supportedInterfaces[type(IERC1155Receiver).interfaceId] = true;
    // çağrısının yapılması iyi olur, böylece DiamondLoupeFacet doğru raporlar.
    // supportsInterface fonksiyonu da bunu yansıtabilir veya sadece kendi desteklediği arayüzü dönebilir.
} 