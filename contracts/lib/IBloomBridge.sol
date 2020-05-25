// IBloomEscrow.sol
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


/**
 * @notice Bloom Escrow Contract Interface
 */
contract IBloomBridge {
    function getAssetTokenAddress() external returns (address);
    function getInterestTokenAddress() external returns (address);
    function getMemberTokenIdByType(uint256 _typeId) external returns (uint256);
    function getPrincipal(uint256 _tokenId) public returns (uint256);
    function getInterest(uint256 _tokenId) public returns (uint256);
    function getBalance(uint256 _tokenId) public returns (uint256);
    function registerType(uint256 _typeId, uint256 _memberTokenId, uint256 _reserveRatio) external returns (address);
    function createCoupon(uint256 _typeId, uint256 _tokenId) external returns (address);
    function deposit(uint256 _tokenId, uint256 _assetAmount) external returns (uint256);
    function redeem(uint256 _tokenId, uint256 _amount) external;
    function release(address _receiver, uint256 _tokenId) external returns (uint256);
    function withdrawFees(address _receiver) external;
}
