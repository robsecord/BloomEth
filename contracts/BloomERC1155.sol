// BloomERC1155.sol
// MIT License
// Copyright (c) 2020 Rob Secord <robsecord.eth>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in all
// copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
// SOFTWARE.

pragma solidity 0.5.16;
pragma experimental ABIEncoderV2;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./lib/IBloomERC1155.sol";
import "./lib/ERC1155.sol";


/**
 * @notice Bloom ERC1155 - Token Manager
 */
contract BloomERC1155 is Initializable, Ownable, IBloomERC1155, ERC1155 {
    // Bloom Controller Contract
    address internal bloom;

    // Throws if called by any account other than the Bloom Controller contract
    modifier onlyBloom() {
        require(bloom == msg.sender, "BloomERC1155: ONLY_BLOOM");
        _;
    }

    function initialize(address _sender) public initializer {
        Ownable.initialize(_sender);
        ERC1155.initialize();
    }

    function isNonFungible(uint256 _id) external pure returns(bool) {
        return _id & TYPE_NF_BIT == TYPE_NF_BIT;
    }
    function isFungible(uint256 _id) external pure returns(bool) {
        return _id & TYPE_NF_BIT == 0;
    }
    function getNonFungibleIndex(uint256 _id) external pure returns(uint256) {
        return _id & NF_INDEX_MASK;
    }
    function getNonFungibleBaseType(uint256 _id) external pure returns(uint256) {
        return _id & TYPE_MASK;
    }
    function isNonFungibleBaseType(uint256 _id) external pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK == 0);
    }
    function isNonFungibleItem(uint256 _id) external pure returns(bool) {
        return (_id & TYPE_NF_BIT == TYPE_NF_BIT) && (_id & NF_INDEX_MASK != 0);
    }

    /**
     * @dev Creates a new Coupon Type, either FT or NFT
     */
    function createType(
        string calldata _uri,
        bool isNF
    )
        external
        onlyBloom
        returns (uint256)
    {
        return _createType(_uri, isNF);
    }

    /**
     * @dev Mints a new Coupon, either FT or NFT
     */
    function mint(
        address _to,
        uint256 _typeId,
        uint256 _amount,
        string calldata _uri,
        bytes calldata _data
    )
        external
        onlyBloom
        returns (uint256)
    {
        return _mint(_to, _typeId, _amount, _uri, _data);
    }

    /**
     * @dev Mints a Batch of new Tokens, either FT or NFT
     */
    function mintBatch(
        address _to,
        uint256[] calldata _types,
        uint256[] calldata _amounts,
        string[] calldata _URIs,
        bytes calldata _data
    )
        external
        onlyBloom
        returns (uint256[] memory)
    {
        return _mintBatch(_to, _types, _amounts, _URIs, _data);
    }

    /**
     * @dev Burns an existing Coupon, either FT or NFT
     */
    function burn(
        address _from,
        uint256 _tokenId,
        uint256 _amount
    )
        external
        onlyBloom
    {
        _burn(_from, _tokenId, _amount);
    }

    /**
     * @dev Burns a Batch of existing Tokens, either FT or NFT
     */
    function burnBatch(
        address _from,
        uint256[] calldata _tokenIds,
        uint256[] calldata _amounts
    )
        external
        onlyBloom
    {
        _burnBatch(_from, _tokenIds, _amounts);
    }

    /**
     * @dev Adds an Integration Controller Contract to allow Creating/Minting
     */
    function setBloomController(address _bloomAddress) external onlyOwner {
        bloom = _bloomAddress;
    }
}
