// Bloom.sol -- Coupons that Grow in Value
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

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./lib/IBloomERC1155.sol";
import "./lib/IBloomBridge.sol";


/**
 * @notice Bloom Contract - Coupons that Grow in Value
 */
contract Bloom is Initializable, Ownable {
    using SafeMath for uint256;
    using Address for address payable;

    /***********************************|
    |     Variables/Events/Modifiers    |
    |__________________________________*/

    // Minimum amount to hold in Escrow
    uint256 constant internal MIN_RESERVE_RATIO = 2e3; // Default: 2000 (20%) [Multiplier: 10000]

    IBloomERC1155 internal tokenMgr;
    IBloomBridge internal bridge;

    //        TypeID => Is Type Created
    mapping (uint256 => bool) internal createdTypes;

    //        TypeID => Max Supply
    mapping (uint256 => uint256) internal typeMaxSupply;

    //        TypeID => Minimum Asset Deposit per Coupon
    mapping (uint256 => uint256) internal typeMinDeposit;

    //        TypeID => Eth Price for Minting set by Type Creator
    // mapping (uint256 => uint256) internal mintFee;

    // ETH Fees earned by Contract
    uint256 internal collectedFees;

    // Fees to Register & Create Coupon-Types
    uint256 internal registerFeeEth;
    uint256 internal createFeeEth;

    // Type ID for Membership NFTs 
    uint256 internal membershipTypeId;

    // Contract State
    bool public isPaused;

    //
    // Modifiers
    //

    modifier whenNotPaused() {
        require(!isPaused, "Bloom: PAUSED");
        _;
    }

    //
    // Events
    //

    event MemberRegistered(
        address indexed _member,
        uint256 _tokenId
    );

    event CouponCreated(
        uint256 indexed _memberTokenId,
        uint256 indexed _typeId,
        uint256 _maxSupply,
        uint256 _minDeposit,
        uint256 _reserveRatio,
        string _uri
    );

    event CouponMinted(
        address indexed _sender,
        address indexed _receiver,
        uint256 indexed _typeId,
        uint256 _tokenId
    );

    event CouponBurned(
        address indexed _from,
        uint256 _tokenId
    );

    event FeesWithdrawn(
        address indexed _sender,
        address indexed _receiver,
        uint256 _amount
    );

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address _sender) public initializer {
        Ownable.initialize(_sender);
    }

    /***********************************|
    |            Public Read            |
    |__________________________________*/

    /**
     * @notice Gets the URI of a Token
     * @param _typeId The ID of the Token
     * @return  The URI of the Token
     */
    function uri(uint256 _typeId) public view returns (string memory) {
        return tokenMgr.uri(_typeId);
    }

    /**
     * @notice Gets the Owner Membership-Token ID of a Coupon Type
     * @param _typeId The Type ID of the Token
     * @return  The Owner Membership Token ID
     */
    function getMemberTokenIdByType(uint256 _typeId) public returns (uint256) {
        return bridge.getMemberTokenIdByType(_typeId);
    }

    /**
     * @notice Checks if a user is allowed to mint a Token by Type ID
     * @param _typeId   The Type ID of the Token
     * @param _amount   The amount of tokens to mint
     * @return  True if the user can mint the token type
     */
    function canMint(uint256 _typeId, uint256 _amount) public view returns (bool) {
        // Has Max
        if (typeMaxSupply[_typeId] > 0) {
            return tokenMgr.totalMinted(_typeId).add(_amount) <= typeMaxSupply[_typeId];
        }
        // No Max
        return true;
    }

    /**
     * @notice Gets the ETH price to create a Token Type
     * @return  The ETH price to create a type
     */
    function getCreationPrice() public view returns (uint256) {
        return createFeeEth;
    }

    /**
     * @notice Gets the ETH price to Register as a Member
     * @return  The ETH price to Register Membership
     */
    function getRegistrationPrice() public view returns (uint256) {
        return registerFeeEth;
    }

    /**
     * @notice Gets the Serial-Number of this Token
     * @param _tokenId  The ID of the token
     * @return  The Serial Number of the Token
     */
    function getSerialNumber(uint256 _tokenId) public view returns (uint256) {
        return tokenMgr.getNonFungibleIndex(_tokenId);
    }

    /**
     * @notice Gets the Max-Supply of the Token
     * @param _tokenId The ID of the Token
     * @return  The Maximum Supply of the Token-Type
     */
    function getMaxSupply(uint256 _tokenId) public view returns (uint256) {
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_tokenId);
        return typeMaxSupply[_typeId];
    }

    /**
     * @notice Gets the Number of Minted Tokens
     * @param _tokenId The ID or the Token
     * @return  The Total Minted Supply of the Token-Type
     */
    function getTotalMinted(uint256 _tokenId) public view returns (uint256) {
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_tokenId);
        return tokenMgr.totalMinted(_typeId);
    }

    /**
     * @notice Gets the Principal-Amount of Assets held in the Token
     * @param _tokenId  The ID of the Token
     * @return  The Principal-Amount of the Token
     */
    function getPrincipal(uint256 _tokenId) public returns (uint256) {
        return bridge.getPrincipal(_tokenId);
    }

    /**
     * @notice Gets the Interest-Amount that the Token has generated
     * @param _tokenId  The ID of the Token
     * @return  The Interest-Amount of the Token
     */
    function getInterest(uint256 _tokenId) public returns (uint256) {
        return bridge.getInterest(_tokenId);
    }

    /**
     * @notice Gets the Available Balance of Assets held in the Token
     * @param _tokenId  The ID of the Token
     * @return  The Available Balance of the Token
     */
    function getBalance(uint256 _tokenId) public returns (uint256) {
        return bridge.getBalance(_tokenId);
    }


    function getMembershipTokenHolder(uint256 _memberTokenId) public returns (address) {
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_memberTokenId);
        if (membershipTypeId > 0 && _typeId != membershipTypeId) {
            return address(0x0);
        }
        return tokenMgr.ownerOf(_memberTokenId);
    }

    function registerMember(address _member) 
        public 
        payable
        whenNotPaused 
        returns (uint256) 
    {
        require(msg.value >= registerFeeEth, "Bloom: INSUFF_FUNDS");
        require(membershipTypeId > 0, "Bloom: INVALID_MEMBER_ID");
        
        // Mint Membership Token
        uint256 _tokenId = tokenMgr.mint(_member, membershipTypeId, 1, "", "");

        // Collect Member-Registration Fees
        collectedFees = registerFeeEth.add(collectedFees);

        // Log Member Registration
        emit MemberRegistered(_member, _tokenId);

        // Refund over-payment
        uint256 _overage = msg.value.sub(registerFeeEth);
        if (_overage > 0) {
            msg.sender.sendValue(_overage);
        }
        return _tokenId;
    }

    /**
     * @notice Creates a new Coupon Type
     */
    function createCoupon(
        uint256 _memberTokenId,
        uint256 _maxSupply,
        uint256 _minDeposit,
        uint256 _reserveRatio,
        string memory _uri
    )
        public
        payable
        whenNotPaused
        returns (uint256)
    {
        require(msg.value >= createFeeEth, "Bloom: INSUFF_FUNDS");
        require(_reserveRatio >= MIN_RESERVE_RATIO, "Bloom: INVALID_RESERVE_RATIO");
        require(getMembershipTokenHolder(_memberTokenId) == msg.sender, "Bloom: INVALID_MEMBER_ID");

        // Create Type
        uint256 _typeId = _createCoupon(
            _memberTokenId, // Membership Token ID
            _maxSupply,     // Max Supply
            _minDeposit,    // Minimum Asset Deposit
            _reserveRatio,  // Reserve-Ratio for Escrow
            _uri            // Token Metadata URI
        );

        // Collect Type-Creation Fees
        collectedFees = createFeeEth.add(collectedFees);

        // Refund over-payment
        uint256 _overage = msg.value.sub(createFeeEth);
        if (_overage > 0) {
            msg.sender.sendValue(_overage);
        }

        return _typeId;
    }

    /**
     * @notice Mints a new Coupon of the specified Type
     *          Note: Requires Asset-Token to mint
     * @param _to           The owner address to assign the new token to
     * @param _typeId       The Type ID of the new token to mint
     * @param _assetAmount  The amount of Asset-Tokens to deposit
     * @param _uri          The Unique URI to the Token Metadata
     * @param _data         Custom data used for transferring tokens into contracts
     * @return  The ID of the newly minted token
     *
     * NOTE: Must approve THIS contract to TRANSFER your Asset-Token on your behalf
     */
    function mintCoupon(
        address _to,
        uint256 _typeId,
        uint256 _assetAmount,
        string memory _uri,
        bytes memory _data
    )
        public
        whenNotPaused
        returns (uint256)
    {
        require(tokenMgr.isNonFungibleBaseType(_typeId), "Bloom: INVALID_TYPE_ID");
        require(createdTypes[_typeId], "Bloom: UNKNOWN_TYPE_ID");
        require(canMint(_typeId, 1), "Bloom: MINTING_NOT_ALLOWED");

        // Mint Token
        uint256 _tokenId = tokenMgr.mint(_to, _typeId, 1, _uri, _data);

        // Deposit Asset Tokens into NFT
        depositAsset(_tokenId, _assetAmount);

        // Log Event
        emit CouponMinted(msg.sender, _to, _typeId, _tokenId);
        return _tokenId;
    }

    /**
     * @notice Destroys a Coupon and releases the underlying Asset + Interest
     * @param _tokenId  The ID of the token to burn
     */
    function burnCoupon(uint256 _tokenId) public whenNotPaused {
        // Verify Token
        require(tokenMgr.isNonFungibleBaseType(_tokenId), "Bloom: INVAID_TYPE_ID");
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_tokenId);
        require(createdTypes[_typeId], "Bloom: UNKNOWN_TYPE_ID");

        // Prepare Release
        address _tokenOwner = tokenMgr.ownerOf(_tokenId);
        bridge.release(_tokenOwner, _tokenId);

        // Burn Token
        tokenMgr.burn(msg.sender, _tokenId, 1);

        // Log Event
        emit CouponBurned(msg.sender, _tokenId);
    }

    /**
     * @notice Allows the owner/operator of the Coupon to add additional Asset Tokens
     * @param _tokenId      The ID of the Token
     * @param _assetAmount  The Amount of Asset Tokens to Deposit
     * @return  The amount of Interest-bearing Tokens added to the escrow for the Token
     */
    function depositAsset(uint256 _tokenId, uint256 _assetAmount)
        public
        whenNotPaused
        returns (uint256)
    {
        require(tokenMgr.isNonFungibleBaseType(_tokenId), "Bloom: INVALID_TYPE_ID");
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_tokenId);
        require(createdTypes[_typeId], "Bloom: UNKNOWN_TYPE_ID");

        // Transfer Asset Token from User to Contract
        uint256 _minDeposit = typeMinDeposit[_typeId];
        _collectAssetToken(msg.sender, _assetAmount, _minDeposit);

        // Transfer Asset from Contract to Escrow
        return bridge.deposit(_tokenId, _assetAmount);
    }

    /**
     * @notice Allows the owner/operator of the Coupon to collect/transfer a specific amount of
     *  the assets + interest generated from the token
     * @param _tokenId      The ID of the Token
     * @param _assetAmount  The Amount of Asset Tokens to Discharge from the NFT
     */
    function redeemCoupon(uint256 _tokenId, uint256 _assetAmount) 
        public 
        whenNotPaused
    {
        require(tokenMgr.isNonFungibleBaseType(_tokenId), "Bloom: INVALID_TYPE_ID");
        uint256 _typeId = tokenMgr.getNonFungibleBaseType(_tokenId);
        require(createdTypes[_typeId], "Bloom: UNKNOWN_TYPE_ID");
        
        bridge.redeem(_tokenId, _assetAmount);
    }

    /***********************************|
    |            Only Owner             |
    |__________________________________*/

    /**
     * @dev Setup the Creation/Minting Fees
     */
    function setupFees(uint256 _createFeeEth, uint256 _registerFeeEth) external onlyOwner {
        createFeeEth = _createFeeEth;
        registerFeeEth = _registerFeeEth;
    }

    /**
     * @dev Toggle the "Paused" state of the contract
     */
    function setPausedState(bool _paused) external onlyOwner {
        isPaused = _paused;
    }

    /**
     * @dev Register the address of the token manager contract
     */
    function registerTokenManager(address _tokenMgr) external onlyOwner {
        require(_tokenMgr != address(0x0), "Bloom: INVALID_ADDRESS");
        tokenMgr = IBloomERC1155(_tokenMgr);
    }

    /**
     * @dev Register the address of the escrow contract
     */
    function registerTokenBridge(address _bridgeAddress) external onlyOwner {
        require(_bridgeAddress != address(0x0), "Bloom: INVALID_ADDRESS");
        bridge = IBloomBridge(_bridgeAddress);
    }

    /**
     * @dev Approve the Token-Bridge Contract to move Assets from this Contract
     */
    function approveTokenBridge() external onlyOwner {
        require(address(bridge) != address(0x0), "Bloom: UNREGISTERED_BRIDGE");

        // Get Asset Token
        address _assetTokenAddress = bridge.getAssetTokenAddress();
        IERC20 _assetToken = IERC20(_assetTokenAddress);

        // Infinite Approve
        _assetToken.approve(address(bridge), uint(-1));
    }

    /**
     * @dev Creates the Membership Token Type
     */
    function createMembershipType(string calldata _uri) external onlyOwner returns (uint256) {
        require(membershipTypeId == 0, "Bloom: MEMBERSHIP_TOKEN_EXISTS");
        membershipTypeId = tokenMgr.createType(_uri, true); // ERC-1155 Non-Fungible
        return membershipTypeId;
    }

    /**
     * @dev Allows contract owner to withdraw any fees earned
     * @param _receiver   The address of the receiver
     */
    function withdrawFees(address payable _receiver) public onlyOwner {
        // Withdraw Collected Fees from Escrow
        bridge.withdrawFees(_receiver);

        // Withdraw Type-Creation Fees
        uint256 _amount = collectedFees;
        if (_amount > 0) {
            collectedFees = 0;
            _receiver.sendValue(_amount);
        }
        emit FeesWithdrawn(msg.sender, _receiver, _amount);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @notice Creates a new Coupon Type (NFT) which can later be minted/burned
     * @param _memberTokenId    The ID of the Membership Token
     * @param _maxSupply        The Max Supply of Tokens that can be minted
     *                          Provide a value of 0 for no limit
     * @param _minDeposit       The Minimum Amount of Asset Tokens to be deposited when Minting
     * @param _reserveRatio     The Reserve-Ratio for the Amount of Assets to Reserve within the Token
     * @param _uri              A unique URI for the Token Type which will serve the JSON metadata
     * @return The ID of the newly created Coupon Type
     *         Use this ID when Minting Coupons of this Type
     */
    function _createCoupon(
        uint256 _memberTokenId,
        uint256 _maxSupply,
        uint256 _minDeposit,
        uint256 _reserveRatio,
        string memory _uri
    )
        internal
        returns (uint256)
    {
        // Create Type
        uint256 _typeId = tokenMgr.createType(_uri, true); // ERC-1155 Non-Fungible
        createdTypes[_typeId] = true;

        // Max Supply of Token; 0 = No Max
        typeMaxSupply[_typeId] = _maxSupply;

        // Minimum Asset Deposit Amount
        typeMinDeposit[_typeId] = _minDeposit;

        // Register Coupon-Type with Escrow
        bridge.registerType(_typeId, _memberTokenId, _reserveRatio);

        // Log Created Coupon
        emit CouponCreated(
            _memberTokenId,
            _typeId,
            _maxSupply,
            _minDeposit,
            _reserveRatio,
            _uri
        );
    }

    /**
     * @dev Collects the Required Asset Token from the users wallet
     * @param _from         The owner address to collect the Assets from
     * @param _assetAmount  The Amount of Asset Tokens to Collect
     * @param _minDeposit   The Minimum Amount of Asset Tokens to Collect
     */
    function _collectAssetToken(address _from, uint256 _assetAmount, uint256 _minDeposit) internal {
        // Check Minimum Asset Deposit
        require(_assetAmount >= _minDeposit, "Bloom: INSUFF_MIN_DEPOSIT");

        // Check User-Balance of Asset Tokens
        address _assetTokenAddress = bridge.getAssetTokenAddress();
        IERC20 _assetToken = IERC20(_assetTokenAddress);
        uint256 _userAssetBalance = _assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "Bloom: INSUFF_FUNDS");

        // Transfer Asset Tokens
        require(_assetToken.transferFrom(_from, address(this), _assetAmount), "Bloom: TRANSFER_FAILED"); // Be sure to Approve this Contract to transfer your Asset Token
    }
}
