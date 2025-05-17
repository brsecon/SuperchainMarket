// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC165} from "../diamond/interfaces/IERC165.sol";

/**
 * @title ERC721ReceiverFacet
 * @dev This facet implements the IERC721Receiver interface, allowing the Diamond
 * to receive ERC721 tokens. It also declares support for IERC165.
 */
contract ERC721ReceiverFacet is IERC721Receiver, IERC165 {
    /**
     * @dev See {IERC721Receiver-onERC721Received}.
     *
     * Always returns `IERC721Receiver.onERC721Received.selector`.
     */
    function onERC721Received(
        address, // operator - The address which called `safeTransferFrom` function
        address, // from - The address which previously owned the token
        uint256, // tokenId - The NFT identifier which is being transferred
        bytes memory // data - Additional data with no specified format
    ) public view override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) external view virtual override returns (bool) {
        return interfaceId == type(IERC721Receiver).interfaceId || interfaceId == type(IERC165).interfaceId;
    }
} 