
pragma solidity 0.5.16;

import "@openzeppelin/upgrades/contracts/Initializable.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts-ethereum-package/contracts/token/ERC20/IERC20.sol";

import "../aave/IAToken.sol";
import "./IBloomBridge.sol";
import "./ERC1155.sol";

/**
 * @notice ERC20-Token Smart-Wallet Bridge to Bloom
 */
contract TokenSmartWallet is Initializable {
    using SafeMath for uint256;

    IAToken public aToken;
    IBloomBridge public entity;
    uint256 public tokenId;

    function initialize(uint256 _tokenId, address _aTokenAddress) public initializer {
        entity = IBloomBridge(msg.sender);
        tokenId = _tokenId;

        // Reference to aToken
        aToken = IAToken(_aTokenAddress);

        // Infinite Approve Bloom to control aTokens in this Wallet
        IERC20(_aTokenAddress).approve(msg.sender, uint(-1));
    }

    function getPrincipal() external returns (uint256) {
        return aToken.principalBalanceOf(address(this));
    }

    function getInterest() external returns (uint256) {
        address _self = address(this);
        uint256 principal = aToken.principalBalanceOf(_self);
        return aToken.balanceOf(_self).sub(principal);
    }

    function getBalance() external returns (uint256) {
        return aToken.balanceOf(address(this));
    }
}
