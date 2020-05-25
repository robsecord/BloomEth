// BloomAaveBridge.sol
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

import "@openzeppelin/contracts-ethereum-package/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/ownership/Ownable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/utils/Address.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/introspection/IERC165.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "./aave/IAToken.sol";
import "./aave/ILendingPool.sol";
import "./aave/ILendingPoolAddressesProvider.sol";

import "./lib/IBloomBridge.sol";
import "./lib/TokenSmartWallet.sol";

contract IOwnable {
    function owner() public view returns (address);
}

contract INonFungible {
    function ownerOf(uint256 _tokenId) public view returns (address);
    function isApprovedForAll(address _owner, address _operator) external view returns (bool);
}

contract IBloomERC1155 {
    function getTypeCreator(uint256 _type) public view returns (address);
}

/**
 * @notice Bloom Escrow Contract
 */
contract BloomAaveBridge is Initializable, Ownable, ReentrancyGuard, IBloomBridge {
    using SafeMath for uint256;

    uint256 constant internal DEPOSIT_MODIFIER  = 1e4;   // 10000  (100%)
    uint256 constant internal MIN_RESERVE_RATIO = 2e3;   //  2000   (20%)

    uint256 constant internal TYPE_NF_BIT = 1 << 255;                   // ERC1155 Common Non-fungible Token Bit
    uint256 constant internal TYPE_MASK = uint256(uint128(~0)) << 128;  // ERC1155 Common Non-fungible Type Mask

    bytes4 constant internal INTERFACE_SIGNATURE_ERC721 = 0x80ac58cd;
    bytes4 constant internal INTERFACE_SIGNATURE_ERC1155 = 0xd9b67a26;

    /***********************************|
    |     Variables/Events/Modifiers    |
    |__________________________________*/

    ILendingPoolAddressesProvider internal lendingPoolProvider;
    ILendingPool internal lendingPool;

    // The Bloom Controller Contract Address
    address internal bloom;

    // The Bloom ERC1155 Token Contract Address
    address internal bloomTokenMgr;

    // Contract Interface to Asset Token
    address internal assetToken;

    // Contract Interface to Interest-bearing Token
    address internal interestToken;

    // Template Contract for creating Token Smart-Wallet Bridges
    address internal tokenWalletTemplate;

    //       TokenID => Token Smart-Wallet Bridge Address
    //        TypeID => Type-Creator Smart-Wallet Bridge Address
    mapping (uint256 => address) internal bridge;

    //        TypeID => Owner Membership TokenID
    mapping (uint256 => uint256) internal typeMemberTokenId; // The Membership NFT that controls the Coupon Type

    //        TypeID => Reserve-Ratio of the Type
    mapping (uint256 => uint256) internal typeReserveRatio; // Amount to be held in reserve for the Token to accrue interest

    //       TokenID => Coupon Type ID
    mapping (uint256 => uint256) internal tokenTypeId; 

    // Token Deposit Fee
    uint256 public depositFee;

    //
    // Events
    //
    event NewTokenSmartWallet(uint256 indexed tokenId, address indexed bridge);
    event CouponDeposit(uint256 indexed tokenId, uint256 assetAmount, uint256 aTokenAmount);
    event CouponRedeem(uint256 indexed tokenId, uint256 assetAmount);
    event CouponReleased(uint256 indexed tokenId, address indexed receiver);
    event ContractFeesWithdrawn(address indexed receiver);

    //
    // Modifiers
    //

    /// @dev Throws if called by any account other than a Bridge contract.
    modifier onlyBridge(uint256 _typeId) {
        require(bridge[_typeId] == msg.sender, "BloomAaveBridge: ONLY_BRIDGE");
        _;
    }

    /// @dev Throws if called by any account other than the Bloom Controller contract
    modifier onlyBloom() {
        require(bloom == msg.sender, "BloomAaveBridge: ONLY_BLOOM");
        _;
    }

    /***********************************|
    |          Initialization           |
    |__________________________________*/

    function initialize(address _sender) public initializer {
        Ownable.initialize(_sender);
        ReentrancyGuard.initialize();

        tokenWalletTemplate = address(new TokenSmartWallet());
    }

    /***********************************|
    |              Public               |
    |__________________________________*/
    
    function getAssetTokenAddress() external returns (address) {
        return assetToken;
    }

    function getInterestTokenAddress() external returns (address) {
        return interestToken;
    }

    function getMemberTokenIdByType(uint256 _typeId) external returns (uint256) {
        return typeMemberTokenId[_typeId];
    }

    /**
     * @notice Gets the Principal-Amount of Assets held in the Token
     * @param _tokenId  The ID of the Token
     * @return  The Principal-Amount of the Token
     */
    function getPrincipal(uint256 _tokenId) public returns (uint256) {
        if (bridge[_tokenId] == address(0x0)) { return 0; }
        return TokenSmartWallet(bridge[_tokenId]).getPrincipal();
    }

    /**
     * @notice Gets the Interest-Amount that the Token has generated
     * @param _tokenId  The ID of the Token
     * @return  The Interest-Amount of the Token
     */
    function getInterest(uint256 _tokenId) public returns (uint256) {
        if (bridge[_tokenId] == address(0x0)) { return 0; }
        return TokenSmartWallet(bridge[_tokenId]).getInterest();
    }

    /**
     * @notice Gets the Available Balance of Assets held in the Token
     * @param _tokenId  The ID of the Token
     * @return  The Available Balance of the Token
     */
    function getBalance(uint256 _tokenId) public returns (uint256) {
        if (bridge[_tokenId] == address(0x0)) { return 0; }
        return TokenSmartWallet(bridge[_tokenId]).getBalance();
    }

    /**
     * @notice Register a Coupoon Type and Associate with Membership NFT
     * @param _typeId         The ID of the Coupon Type
     * @param _memberTokenId  The ID of the Membership NFT creating the Type
     * @param _reserveRatio   The Ratio of Assets held in Reserve for the Coupon
     * @return  The address of the Member-Smart-Wallet
     */
    function registerType(
        uint256 _typeId, 
        uint256 _memberTokenId, 
        uint256 _reserveRatio
    ) 
        external 
        onlyBloom 
        returns (address) 
    {
        require(typeMemberTokenId[_typeId] == 0, "BloomAaveBridge: TYPE_REGISTERED");
        require(_memberTokenId > 0, "BloomAaveBridge: INVALID_MEMBER_TOKEN");
        typeMemberTokenId[_typeId] = _memberTokenId;
        typeReserveRatio[_typeId] = _reserveRatio;

        // Create Smart-Wallet for Coupon-Type owned by Membership NFT
        address _memberWallet = _createTokenWallet(_memberTokenId);
        bridge[_memberTokenId] = _memberWallet;
        return _memberWallet;
    }

    /**
     * @notice Creates a New Token-Smart-Wallet for the Coupon NFT of the specified Type
     * @param _typeId       The ID of the Coupon Type
     * @param _tokenId      The ID of the Coupon NFT
     * @return  The address of the Token-Smart-Wallet
     */
    function createCoupon(
        uint256 _typeId,
        uint256 _tokenId
    ) 
        external
        onlyBloom
        returns (address)
    {
        require(bridge[_tokenId] == address(0x0), "BloomAaveBridge: TOKEN_BRIDGE_EXISTS");

        // Create Smart-Wallet for NFT
        address _tokenWallet = _createTokenWallet(_tokenId);
        bridge[_tokenId] = _tokenWallet;
        tokenTypeId[_tokenId] = _typeId;

        return _tokenWallet;
    }

    /**
     * @notice Fund NFT with Asset Token
     *    Must be called by the Owner providing the Asset
     *    Owner must Approve THIS contract as Operator of Asset
     *
     * @param _tokenId          The ID of the Token to Energize
     * @param _assetAmount      The Amount of Asset Token to Energize the Token with
     * @return  The amount of Interest-bearing Tokens added to the escrow for the Token
     */
    function deposit(
        uint256 _tokenId,
        uint256 _assetAmount
    )
        external
        onlyBloom
        returns (uint256)
    {
        require(bridge[_tokenId] != address(0x0), "BloomAaveBridge: INVALID_TOKEN_BRIDGE");

        address _self = address(this);
        IERC20 _assetToken = IERC20(assetToken);
        IERC20 _interestToken = IERC20(interestToken);
        
        // Collect Asset Token (reverts on fail)
        _collectAssetToken(msg.sender, _assetAmount); 

        // Approve LendingPool contract to transfer Assets
        _assetToken.approve(lendingPoolProvider.getLendingPoolCore(), _assetAmount);

        // Deposit Assets into Aave
        uint256 _preBalance = _interestToken.balanceOf(_self);
        lendingPool = ILendingPool(lendingPoolProvider.getLendingPool());
        lendingPool.deposit(assetToken, _assetAmount, 0);
        uint256 _postBalance = _interestToken.balanceOf(_self);

        // Calculate Reserve-Amount for Coupon NFT
        // Calculate Payment-Amount for Membership NFT
        uint256 _tokenTypeId = tokenTypeId[_tokenId];
        uint256 _memberTokenId = typeMemberTokenId[_tokenTypeId];
        uint256 _reserveRatio = typeReserveRatio[_tokenTypeId];
        uint256 _transferedAmount = _postBalance.sub(_preBalance);
        uint256 _tokenAmount = _transferedAmount; // TODO: calculate amount for token-reserve
        uint256 _remainingAmount = _transferedAmount.sub(_tokenAmount);

        // TODO: Take "depositFee"

        // Transfer ATokens into Smart-Wallet of Coupon NFT
        _interestToken.transfer(bridge[_tokenId], _tokenAmount);

        // Transfer ATokens into Smart-Wallet of Membership NFT
        _interestToken.transfer(bridge[_memberTokenId], _remainingAmount);

        // Log Event
        emit CouponDeposit(_tokenId, _assetAmount, _transferedAmount);

        // Return amount of Interest-bearing Token transfered
        return _transferedAmount;
    }

    /**
     * @notice Redeems a portion of the Assets held within the NFT
     * @param _tokenId   The ID of the Token to Release
     * @param _amount    The Amount of Assets to Redeem
     */
    function redeem(
        uint256 _tokenId,
        uint256 _amount
    )
        external
        onlyBloom
    {
        require(_amount > 0 && getPrincipal(_tokenId) >= _amount, "BloomAaveBridge: INSUFF_BALANCE");

        // Redeem a portion of the Coupon
        _redeemCoupon(_tokenId, _amount);

        // Log Event
        emit CouponRedeem(_tokenId, _amount);
    }

    /**
     * @notice Releases the Full amount of Asset + Interest held within a Coupon or Membership NFT
     * @param _receiver  The Address to Receive the Released Asset Tokens
     * @param _tokenId   The ID of the Token to Release
     * @return  The Total Amount of Asset Token Released including all converted Interest
     */
    function release(
        address _receiver,
        uint256 _tokenId
    )
        external
        onlyBloom
        returns (uint256)
    {
        require(getPrincipal(_tokenId) > 0, "BloomAaveBridge: NO_BALANCE");

        // Log Event
        emit CouponReleased(_tokenId, _receiver);

        // Release NFT to Receiver
        return _payoutFull(_tokenId, _receiver);
    }

    /***********************************|
    |          Only Admin/DAO           |
    |__________________________________*/

    function setAddresses(address _bloom, address _aaveLendingProvider, address _assetToken, address _interestToken) external onlyOwner {
        bloomTokenMgr = _bloom;
        lendingPoolProvider = ILendingPoolAddressesProvider(address(_aaveLendingProvider));
        assetToken = _assetToken;           // DAI
        interestToken = _interestToken;     // aDAI
    }

    /**
     * @dev Setup the Base Deposit Fee for the Escrow
     */
    function setDepositFee(uint256 _depositFee) external onlyOwner {
        depositFee = _depositFee;
    }

    /**
     * @dev Allows Escrow Contract Owner/DAO to withdraw any fees earned
     */
    function withdrawFees(address _receiver) external onlyOwner {
        
        // TODO... 
        // Should redirect fees on "deposit" into an Owner-Smart-Wallet and use "_payoutFull" to withdraw?
        //  - Needs an Owner NFT minted

        emit ContractFeesWithdrawn(_receiver);
    }

    /***********************************|
    |         Private Functions         |
    |__________________________________*/

    /**
     * @dev Collects the Required Asset Token from the users wallet
     */
    function _collectAssetToken(address _from, uint256 _assetAmount) internal {
        IERC20 _assetToken = IERC20(assetToken);
        uint256 _userAssetBalance = _assetToken.balanceOf(_from);
        require(_assetAmount <= _userAssetBalance, "BloomAaveBridge: INSUFF_FUNDS");
        require(_assetToken.transferFrom(_from, address(this), _assetAmount), "BloomAaveBridge: TRANSFER_FAILED"); // Be sure to Approve this Contract to transfer your Asset Token
    }

    /**
     * @dev Redeems the Coupons Assets to the Coupon-Type Creator (stays in yield-token until withdrawn)
     */
    function _redeemCoupon(uint256 _tokenId, uint256 _assetAmount) internal {
        IERC20 _interestToken = IERC20(interestToken);
        uint256 _memberTokenId = typeMemberTokenId[tokenTypeId[_tokenId]];

        // Transfer aTokens from Token-Smart-Wallet to Smart-Wallet of Type-Creator
        address _from = bridge[_tokenId];
        address _to = bridge[_memberTokenId];
        require(_interestToken.transferFrom(_from, _to, _assetAmount), "BloomAaveBridge: REDEEM_FAILED");
    }

    /**
     * @dev Pays out the full amount of the Assets + Interest in the underlying asset-token
     */
    function _payoutFull(uint256 _tokenId, address _receiver) internal returns (uint256) {
        address _self = address(this);
        IERC20 _assetToken = IERC20(assetToken);
        IERC20 _interestToken = IERC20(interestToken);
        IAToken _aToken = IAToken(interestToken);

        address _from = bridge[_tokenId];
        uint256 _fullBalance = getBalance(_tokenId);

        // Transfer aTokens from Token-Smart-Wallet to Contract
        uint256 _preBalance = _interestToken.balanceOf(_self);
        require(_interestToken.transferFrom(_from, _self, _fullBalance), "BloomAaveBridge: PAYOUT_FAILED");
        uint256 _postBalance = _interestToken.balanceOf(_self);
        uint256 _redeemAmount = _postBalance.sub(_preBalance);

        // Redeem aTokens for Asset Tokens
        require(_aToken.isTransferAllowed(_self, _redeemAmount), "BloomAaveBridge: PAYOUT_NOT_ALLOWED");
        _preBalance = _assetToken.balanceOf(_self);
        _aToken.redeem(_redeemAmount);
        _postBalance = _assetToken.balanceOf(_self);
        uint256 _redeemedAssets = _postBalance.sub(_preBalance);

        // Transfer Assets to Receiver
        require(_assetToken.transfer(_receiver, _redeemedAssets), "BloomAaveBridge: PAYOUT_TRANSFER_FAILED");
        return _redeemedAssets;
    }

    /**
     * @dev Creates an ERC20 Token Bridge Contract to interface with the ERC1155 Contract
     */
    function _createTokenWallet(
        uint256 _tokenId
    )
        internal
        returns (address)
    {
        require(bridge[_tokenId] == address(0), "BloomAaveBridge: INVALID_TOKEN_ID");

        address newBridge = _createClone(tokenWalletTemplate);
        TokenSmartWallet(newBridge).initialize(_tokenId, interestToken);
        bridge[_tokenId] = newBridge;

        emit NewTokenSmartWallet(_tokenId, newBridge);
        return newBridge;
    }

    /**
     * @dev Creates Contracts from a Template via Cloning
     * see: https://github.com/ethereum/EIPs/blob/master/EIPS/eip-1167.md
     */
    function _createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }
}
