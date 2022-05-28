// SPDX-License-Identifier: MIT
// Creator: The Systango Team
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/ERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/finance/PaymentSplitterUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/StringsUpgradeable.sol";
import "./IMersMeta.sol";

contract MersMeta is Initializable, ERC1155Upgradeable, OwnableUpgradeable, PausableUpgradeable, PaymentSplitterUpgradeable, IMersMeta {

    // Name of the token
    string public name;

    // Symbol of the token
    string public symbol;

    // Token Uri mapping  correspond to token id
    mapping(uint => string) public tokenURI;

    // Mint Price mapping for different token id 
    mapping(uint => uint256) public mintPrice;

    //Base token Uri
    string baseUri ; 
    
    function initialize(
        string memory nameOfContract, 
        string memory symbolOfContract,
        address[] memory payees,
        uint256[] memory shares
    ) initializer external {
        __ERC1155_init("");
        __Ownable_init();
        __Pausable_init();
        __PaymentSplitter_init(payees, shares);
        name = nameOfContract;
        symbol = symbolOfContract;
    }

    /// @dev This is a function use to set the token price. Using this function one can set different token price for different token id.
    /// @param id The id of the token whose token price to be set.
    /// @param mintValue The mint value in ether. This value will use as mint price for token.

    function setTokenIDPrice (uint32 id, uint256 mintValue) external override onlyOwner whenNotPaused
    {
        mintPrice[id] = mintValue;
        emit SetTokenValue(mintValue);
    }

    /// @dev This is the token mint function.
    /// @param id The id of the token which you want to mint 
    /// @param amount The amount of token you want to mint for that particular token id

    function mintToken (uint32 id, uint256 amount) external override payable whenNotPaused
    {
        require(mintPrice[id] != 0 , "MersMeta: Cannot mint token as token ID is not active yet!");
        require(msg.value >= mintPrice[id], "MersMeta: Insufficient ETH supplied.");
        _mint(msg.sender, id, amount, "");
        emit NewTokenCreated(id);
    }

    /// @dev This is the airDrop function. It is used by the owner to airdrop `amount` number of  tokens to the `recipient` address respectively.
    /// @dev Only the owner can call this function
    /// @param recipient The address to be air dropped
    /// @param id The id of the token that should be airdroped  
    /// @param amount The amount of tokens to be air dropped

    function airDrop (address[] memory recipient, uint256[] memory amount , uint256 id) external override onlyOwner whenNotPaused 
    {
        require(mintPrice[id] != 0 , "MersMeta: Cannot airdrop token as token ID is not active yet!");
        require(amount.length == recipient.length, "MersMeta: Incorrect parameter length.");
        for (uint256 index = 0; index < recipient.length; index++) {
            _mint(recipient[index], id, amount[index], "");
        }
    }

    /// @dev This is the function to set the URI to token id 
    /// @dev Only the owner can call this function
    /// @param seturi The new URI 

    function setURI (string memory seturi) external override onlyOwner whenNotPaused
    {
        baseUri = seturi;
        emit SetUri(seturi);
    }

    /// @dev The external function for getting the URI string based on token id 
    /// @param id The id of the token whose URI should be get 

    function uri(uint id) public view virtual override(IMersMeta,ERC1155Upgradeable) whenNotPaused returns (string memory) 
    {
        return string(abi.encodePacked(baseUri,StringsUpgradeable.toString(id)));
    }

    /// @dev The external function returns the current contract balance 
    function balanceOfContract() external view returns(uint256) {
       return address(this).balance;
    }

    /// @dev The external function for withdraw the amount of share hold by the account 
    /// @param account The account address in which the ether to be send
    function withdraw(address account) external override whenNotPaused
    {
        require(account != address(0), "MersMeta: Cannot be transferred to zero address.");
        release(payable(account));
    }

    /// @dev This function would pause the contract
    /// @dev Only the owner can call this function

    function pause() external override onlyOwner 
    {
        _pause();
    }

    /// @dev This function would unpause the contract
    /// @dev Only the owner can call this function

    function unpause() external override onlyOwner 
    {
        _unpause();
    }

    /// @dev Overridden function called before every token transfer

    function _beforeTokenTransfer( address _operator, address _from, address _to, uint256[] memory _ids, uint256[] memory _amounts, bytes memory _data) internal whenNotPaused override
    {
        super._beforeTokenTransfer(_operator, _from, _to, _ids, _amounts, _data);
    }
}

interface IMersMeta { 

    // The event emitted when new token is minted
    event NewTokenCreated(uint32 id);

    // The event emitted when token value is set
    event SetTokenValue(uint256 mintValue);

    // The event emitted when new URI is set
    event SetUri(string seturi);

    /**
     * @dev Set token ID mint price
     */
    function setTokenIDPrice(uint32 id, uint256 mintValue) external;

    /**
     * @dev Mint a new token 
     */
    function mintToken(uint32 id, uint256 amount) external payable;   

    /**
     * @dev Airdrop the Tokens to assigned address by the owner
     */
    function airDrop(address[] memory recipient, uint256[] memory amount , uint256 id) external;

    /**
     * @dev Set a new Base URI 
     */
    function setURI(string memory seturi) external;

    /**
     * @dev Get the Base URI 
     */
    function uri(uint id) external view returns (string memory); 

    /**
     * @dev Withdraw the share amount to account owner
     */
    function withdraw(address account) external;

    /**
     * @dev Pause the contract
     */
    function pause() external;

    /**
     * @dev Unpause the contract
     */
    function unpause() external;
}

contract Migrations {
  address public owner = msg.sender;
  uint public last_completed_migration;

  modifier restricted() {
    require(
      msg.sender == owner,
      "This function is restricted to the contract's owner"
    );
    _;
  }

  function setCompleted(uint completed) external restricted {
    last_completed_migration = completed;
  }
}