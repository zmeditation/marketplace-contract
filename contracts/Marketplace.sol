// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.6;

import "./NativeMetaTransaction.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";

interface ERC20Interface {
  function transferFrom(address from, address to, uint tokens) external returns (bool success);
}


/**
 * @title Interface for contracts conforming to ERC-721
 */
interface ERC721Interface {
  function ownerOf(uint256 _tokenId) external view returns (address _owner);
  function approve(address _to, uint256 _tokenId) external;
  function getApproved(uint256 _tokenId) external view returns (address);
  function isApprovedForAll(address _owner, address _operator) external view returns (bool);
  function safeTransferFrom(address _from, address _to, uint256 _tokenId) external;
  function supportsInterface(bytes4) external view returns (bool);
}


interface ERC721Verifiable is ERC721Interface {
  function verifyFingerprint(uint256, bytes memory) external view returns (bool);
}

contract Marketplace is Ownable , Pausable, NativeMetaTransaction {
    using SafeMath for uint256;
    using Address for address;

    struct Order {
        bytes32 id; // Order ID
        address seller; // Owner of the NFT
        address nftAddress; // NFT address
        uint256 price; // Price for the item
        uint256 expiresAt; // Time when this sale ends
    }

    // ============================================================
    //                           STORAGE
    // ============================================================

    ERC20Interface public acceptedToken;

    mapping (address => mapping(uint256 => Order)) public orderByAssetId;

    uint256 public ownerCutPerMillion;
    uint256 public publicationFeeInWei;

    bytes4 public constant InterfaceId_ValidateFingerprint = bytes4(keccak256("verifyFingerprint(uint256,bytes)"));

    bytes4 public constant ERC721_Interface = bytes4(0x80ac58cd);

    // ============================================================
    //                            EVENTS
    // ============================================================

    event OrderCreated(bytes32 id, uint256 indexed assetId, address indexed seller, address nftAddress, uint256 priceInWei, uint256 expiresAt);
    event OrderSuccessful(bytes32 id, uint256 indexed assetId, address indexed seller, address nftAddress, uint256 totalPrice, address indexed buyer);
    event OrderCancelled(bytes32 id, uint256 indexed assetId, address indexed seller, address nftAddress);
    event ChangedPublicationFee(uint256 publicationFee);
    event ChangedOwnerCutPerMillion(uint256 ownerCutPerMillion);

    // ============================================================
    //                           Functions
    // ============================================================

    constructor (address _acceptedToken, uint256 _ownerCutPerMillion, address _owner) {
        require(_owner != address(0), "UNICIAL: Invalid owner");
        require(_acceptedToken.isContract(), "UNICIAL: The accepted token address must be a contract address");
        
        _initializeEIP712("Unicial marketplace", "1");

        setOwnerCutPerMillion(_ownerCutPerMillion);

        transferOwnership(_owner);
        acceptedToken = ERC20Interface(_acceptedToken);
    }

    /**
      * @dev Sets the share cut for the owner of the contract that's
      *  charged to the seller on a successful sale
      * @param _ownerCutPerMillion - Share amount, from 0 to 999,999
      */
    function setOwnerCutPerMillion(uint256 _ownerCutPerMillion) public onlyOwner {
        require(_ownerCutPerMillion < 1000000, "UNICIAL: The owner cut should be between 0 and 999,999");

        ownerCutPerMillion = _ownerCutPerMillion;
        emit ChangedOwnerCutPerMillion(ownerCutPerMillion);
    }

    /**
      * @dev Sets the publication fee that's charged to users to publish items
      * @param _publicationFee - Fee amount in wei this contract charges to publish an item
      */
    function setPublicationFee(uint256 _publicationFee) external onlyOwner {
        publicationFeeInWei = _publicationFee;
        emit ChangedPublicationFee(publicationFeeInWei);
    }

    /**
      * @dev Creates a new order
      * @param nftAddress - Non fungible registry address
      * @param assetId - ID of the published NFT
      * @param priceInWei - Price in Wei for the supported coin
      * @param expiresAt - Duration of the order (in hours)
      */
    function createOrder(address nftAddress, uint256 assetId, uint256 priceInWei, uint256 expiresAt) public whenNotPaused {
        _createOrder(nftAddress, assetId, priceInWei, expiresAt);
    }

    /**
      * @dev Cancel an already published order
      *  can only be canceled by seller or the contract owner
      * @param nftAddress - Address of the NFT registry
      * @param assetId - ID of the published NFT
      */
    function cancelOrder(address nftAddress, uint256 assetId) public whenNotPaused {
        _cancelOrder(nftAddress, assetId);
    }

    /**
      * @dev Executes the sale for a published NFT
      * @param nftAddress - Address of the NFT registry
      * @param assetId - ID of the published NFT
      * @param price - Order price
      */
    function executeOrder(address nftAddress, uint256 assetId, uint256 price) public whenNotPaused {
        _executeOrder(nftAddress, assetId, price, "");
    }

    /**
      * @dev Creates a new order
      * @param nftAddress - Non fungible registry address
      * @param assetId - ID of the published NFT
      * @param priceInWei - Price in Wei for the supported coin
      * @param expiresAt - Duration of the order (in hours)
      */
    function _createOrder(address nftAddress, uint256 assetId, uint256 priceInWei, uint256 expiresAt) internal {
        _requireERC721(nftAddress);

        address sender = _msgSender();

        ERC721Interface nftRegistry = ERC721Interface(nftAddress);
        address assetOwner = nftRegistry.ownerOf(assetId);

        require(sender == assetOwner, "UNICIAL: Only the owner can create orders");
        require(nftRegistry.getApproved(assetId) == address(this) || nftRegistry.isApprovedForAll(assetOwner, address(this)),
         "UNICIAL: The contract is not authorized to manage this asset");
        require(priceInWei > 0, "UNICIAL: Price should be bigger than zero");
        require(expiresAt > block.timestamp.add(5 minutes), "UNICIAL: Publication should be more than 5 minutes in the future");

        bytes32 orderId = keccak256(abi.encodePacked(block.timestamp, assetOwner, assetId, nftAddress, priceInWei));

        orderByAssetId[nftAddress][assetId] = Order({
            id: orderId,
            seller: sender,
            nftAddress: nftAddress,
            price: priceInWei,
            expiresAt: expiresAt
        });

        if (publicationFeeInWei > 0) {
            require(acceptedToken.transferFrom(sender, owner(), publicationFeeInWei), "UNICIAL: Transfering the publication fee to the Marketplace failed");
        }

        emit OrderCreated(orderId, assetId, sender, nftAddress, priceInWei, expiresAt);
    }

    /**
      * @dev Cancel an already published order
      *  can only be canceled by seller or the contract owner
      * @param nftAddress - Address of the NFT registry
      * @param assetId - ID of the published NFT
      */
    function _cancelOrder(address nftAddress, uint256 assetId) internal returns (Order memory) {
        address sender = _msgSender();
        Order memory order = orderByAssetId[nftAddress][assetId];

        require(order.id != 0, "UNICIAL: Asset not published");
        require(order.seller == sender || sender == owner(), "UNICIAL: Unauthorized user");

        bytes32 orderId = order.id;
        address orderSeller = order.seller;
        address orderNftAddress = order.nftAddress;
        delete orderByAssetId[nftAddress][assetId];

        emit OrderCancelled(orderId, assetId, orderSeller, orderNftAddress);

        return order;
    }

    /**
      * @dev Creates a new order
      * @param nftAddress - Non fungible registry address
      * @param assetId - ID of the published NFT
      * @param price - Order price
      * @param fingerprint - Verficiation info for the asset
      */
    function _executeOrder(address nftAddress, uint256 assetId, uint256 price, bytes memory fingerprint) internal returns(Order memory) {
        _requireERC721(nftAddress);

        address sender = _msgSender();

        ERC721Verifiable nftRegistry = ERC721Verifiable(nftAddress);

        if (nftRegistry.supportsInterface(InterfaceId_ValidateFingerprint)) {
            require(nftRegistry.verifyFingerprint(assetId, fingerprint),"UNICIAL: The asset fingerprint is not valid");
        }

        Order memory order = orderByAssetId[nftAddress][assetId];

        require(order.id != 0, "UNICIAL: Asset not published");

        address seller = order.seller;

        require(seller != address(0), "UNICIAL: Invalid address");
        require(seller != sender, "UNICIAL: Unauthorized user");
        require(order.price == price, "UNICIAL: The price is not correct");
        require(block.timestamp < order.expiresAt, "UNICIAL: The order expired");
        require(seller == nftRegistry.ownerOf(assetId), "UNICIAL: The seller is no longer the owner");

        uint256 saleShareAmount = 0;

        bytes32 orderId = order.id;
        delete orderByAssetId[nftAddress][assetId];

        if (ownerCutPerMillion > 0) {
            // Calculate sale share
            saleShareAmount = price.mul(ownerCutPerMillion).div(1000000);

            // Transfer share amount for marketplace Owner
            require(
                acceptedToken.transferFrom(sender, owner(), saleShareAmount),
                "UNICIAL: Transfering the cut to the Marketplace owner failed"
            );
        }

        // Transfer sale amount to seller
        require(acceptedToken.transferFrom(sender, seller, price.sub(saleShareAmount)),
            "UNICIAL: Transfering the sale amount to the seller failed");

        // Transfer asset owner
        nftRegistry.safeTransferFrom(seller, sender, assetId);

        emit OrderSuccessful(orderId, assetId, seller, nftAddress, price, sender);

        return order;
    }

    function _requireERC721(address nftAddress) internal view {
        require(nftAddress.isContract(), "UNICIAL: The NFT address should be a contract");
        
        ERC721Interface nft = ERC721Interface(nftAddress);
        require(nft.supportsInterface(ERC721_Interface), "UNICIAL: The NFT contract has an invalid ERC721 implementation");
    }
}