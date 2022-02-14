// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";

contract CrownWars is ERC1155, Ownable, ERC1155Supply {
    using SafeMath for uint256;
    using Strings for string;

    string public name;
    string public symbol;

    address public constant CREATORS = 0xbB73C02cd7a3f8417eF31a40bBf7B517deDC13d1;

    // NFT SALE
    uint256 public constant PRICE = 0.2 ether;
    uint256 public constant MAX_ELEMENTS = 10;
    uint256 public constant MAX_MINT = 10;
    bool public sale;

    // GAME
    uint256 public constant GOD_HP = 10000;
    uint256 public constant BASE_HP = 1;
    uint256 public constant STORM_CLAIM_RATE = 10;
    bool public gameActive;
    uint256 public stormClaimDead = 2;
    uint256 public attackStormCost = 5;
    uint256 public attackDMG = 1;
    uint256 public hideStormCost = 5;

    /**
     * TOKEN TYPES:
     *  0 - STORM TOKEN
     *  1 - MAIN NFT
     *  2 - BADGE/ACHIEVEMENT
     *  3 - SPECIAL WEAPON
     *  4 - SPECIAL HEAL
     */
    struct TokenData {
        uint256 _type;
        uint256 lastClaimedSTORM;
        uint256 hiddenUntil;
        uint256 hp;
        string name;
        string bio;
        string faction;
    }

    mapping(uint256 => TokenData) public tokenData;

    // NFT EVENTS
    event WelcomeCrownWarrior(uint256 indexed tokenId);

    // GAME EVENTS
    event GameStateChanged(
        uint256 stormClaimDead,
        uint256 attackStormCost,
        uint256 attackDMG,
        uint256 hideStormCost
    );
    event NFTAttacked(
        uint256 indexed attackerTokenId,
        uint256 indexed attackedTokenId,
        uint256 damage
    );
    event NFTKilled(uint256 indexed attackerTokenId, uint256 indexed attackedTokenId);
    event NFTHidden(uint256 indexed tokenId, uint256 until);

    // Constructor
    constructor(
        string memory _uri,
        string memory _name,
        string memory _symbol
    ) ERC1155(_uri) {
        name = _name;
        symbol = _symbol;

        mintCrownWarrior(CREATORS, 1, true);
    }

    // Used for testing
    receive() external payable onlyOwner {}

    /**
     * ESSENTIALS
     */

    function setURI(string memory newuri) external onlyOwner {
        _setURI(newuri);
    }

    function uri(uint256 _id) public view override(ERC1155) returns (string memory) {
        require(exists(_id), "Nonexistent token");
        return string(abi.encodePacked(super.uri(0), Strings.toString(_id), ".json"));
    }

    // Withdraw amount to address
    function _withdraw(address _address, uint256 _amount) private {
        (bool success, ) = _address.call{value: _amount}("");
        require(success, "Transfer failed");
    }

    // Distribute the funds to the creators
    function withdrawAll() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No funds");
        _withdraw(CREATORS, address(this).balance);
    }

    function recoverAddress(bytes memory message, bytes memory signature)
        private
        pure
        returns (address)
    {
        return ECDSA.recover(ECDSA.toEthSignedMessageHash(keccak256(message)), signature);
    }

    /**
     * TOKEN FUNCTIONS AND MODIFIERS
     */

    function toggleSale() external onlyOwner {
        sale = !sale;
    }

    // Mint NFT, godmode creates special NFTs for the game
    function mintCrownWarrior(
        address from,
        uint256 tokenId,
        bool godmode
    ) private {
        TokenData storage _tokenData = tokenData[tokenId];
        _tokenData._type = 1;
        _tokenData.hp = godmode ? GOD_HP : BASE_HP;

        emit WelcomeCrownWarrior(tokenId);
        _mint(from, tokenId, 1, "");
    }

    // Minting external function
    // Signature has to be acuired by the owner address signing the values
    function mint(
        address from,
        uint256 tokenId,
        uint256 timestamp,
        bytes memory signature
    ) external payable {
        require(sale, "Sale not active");
        require(block.timestamp < timestamp, "Out of time");
        require(msg.value >= PRICE, "Below price");

        require(!exists(tokenId), "Must not exist");
        require(
            owner() == recoverAddress(abi.encode(from, tokenId, timestamp), signature),
            "Not authorized to mint"
        );

        mintCrownWarrior(from, tokenId, false);
    }

    // Checks if you own the amount of tokens
    function isTokensYours(
        address from,
        uint256 tokenId,
        uint256 amount
    ) public view returns (bool) {
        return
            (from == _msgSender() || isApprovedForAll(from, _msgSender())) &&
            balanceOf(from, tokenId) >= amount;
    }

    /**
     * THE FOLLOWING FUNCTIONS ARE OVERRIDES REQUIRED BY SOLIDITY
     */

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    /**
     * AIRDROP
     */

    // Can only airdrop other game items either by solving challenges or giveaways
    function airdropFT(
        address to,
        uint256 tokenId,
        uint256 _tokenType,
        uint256 amount,
        uint256 _hp,
        string calldata _name,
        string calldata _bio
    ) external onlyOwner {
        require(tokenId == 0 || tokenId > MAX_ELEMENTS, "Token must be fungable");
        require(_tokenType != 1, "Token must be fungable");
        require(amount > 0, "More than 0");

        TokenData storage _tokenData = tokenData[tokenId];
        _tokenData._type = _tokenType;
        _tokenData.hp = _hp;
        _tokenData.name = _name;
        _tokenData.bio = _bio;

        _mint(to, tokenId, amount, "");
    }

    /**
     * GAME LOGICS
     */

    /**
     * GETTERS AND SETTER FOR IDENTIFIERS
     */

    // Used to start the game.
    // The game should not be paused unless the game ends
    // but the option exists too.
    function toggleGame() external onlyOwner {
        gameActive = !gameActive;
    }

    // Set main NFT details such as name, bio and faction
    function setNFTInfo(
        address from,
        uint256 tokenId,
        string calldata _name,
        string calldata _bio,
        string calldata _faction
    ) external {
        require(gameActive, "Game is not active");
        require(isTokensYours(from, tokenId, 1), "Not yours");

        TokenData storage _tokenData = tokenData[tokenId];
        require(_tokenData._type == 1, "Bad token");
        _tokenData.name = _name;
        _tokenData.bio = _bio;
        _tokenData.faction = _faction;
    }

    // Used by creators to create special events by changing game variables
    // This creates a interesting and varied game
    function setGameState(
        uint256 _stormClaimDead,
        uint256 _attackStormCost,
        uint256 _attackDMG,
        uint256 _hideStormCost
    ) external onlyOwner {
        stormClaimDead = _stormClaimDead;
        attackStormCost = _attackStormCost;
        attackDMG = _attackDMG;
        hideStormCost = _hideStormCost;

        emit GameStateChanged(_stormClaimDead, _attackStormCost, _attackDMG, _hideStormCost);
    }

    /**
     * STAKING
     */

    // Calculate claimable STORM tokens
    function claimableSTORM(uint256 tokenId) public view returns (uint256) {
        TokenData storage _tokenData = tokenData[tokenId];
        require(_tokenData._type == 1, "Bad token");

        uint256 claimable = STORM_CLAIM_RATE;
        if (_tokenData.lastClaimedSTORM > 0) {
            claimable = STORM_CLAIM_RATE.mul(block.timestamp.sub(_tokenData.lastClaimedSTORM)).div(
                86400
            );
        }

        if (_tokenData.hp <= 0) claimable = claimable.div(stormClaimDead);

        return claimable;
    }

    // Claim STORM tokens, based on daily rewards
    function claimSTORM(address from, uint256 tokenId) external {
        require(gameActive, "Game is not active");
        require(isTokensYours(from, tokenId, 1), "Not yours");

        TokenData storage _tokenData = tokenData[tokenId];
        require(_tokenData._type == 1, "Bad token");
        require(block.timestamp >= _tokenData.lastClaimedSTORM, "Bad transaction");

        uint256 claimable = claimableSTORM(tokenId);
        require(claimable > 0, "Nothing to claim");

        _tokenData.lastClaimedSTORM = block.timestamp;
        _mint(from, 0, claimable, "");
    }

    /**
     * ATTACK NFT
     */

    // Checks if the NFT is of type 1 and checks if HP is <= 0
    function isNFTDead(uint256 tokenId) public view returns (bool) {
        TokenData storage _tokenData = tokenData[tokenId];
        require(_tokenData._type == 1, "Bad token");
        return _tokenData.hp <= 0;
    }

    // Your NFT attacks another NFT a certain amount of times
    function attackNFT(
        address from,
        uint256 attackerTokenId,
        uint256 attackedTokenId,
        uint256 times
    ) external {
        require(gameActive, "Game is not active");

        // Checks if you own your NFT and the tokens required
        require(isTokensYours(from, attackerTokenId, 1), "Not yours");
        require(isTokensYours(from, 0, times.mul(attackStormCost)), "Not enough");

        // Checks if your NFT is of type 1, not dead nor hidden
        require(!isNFTDead(attackerTokenId), "Attacker is dead");
        require(!isNFTHidden(attackerTokenId), "Attacker is hidden");

        // Checks if the opponent's NFT, is of type 1, not dead nor hidden
        require(!isNFTDead(attackedTokenId), "Already dead");
        require(!isNFTHidden(attackedTokenId), "NFT is hidden");

        // Burns the amount of STORM tokens required
        _burn(from, 0, times.mul(attackStormCost));

        TokenData storage _tokenData = tokenData[attackedTokenId];

        if (_tokenData.hp <= times.mul(attackDMG)) {
            // Opponent's NFT dies
            _tokenData.hp = 0;
            emit NFTKilled(attackerTokenId, attackedTokenId);
        } else {
            // Opponent's NFT did not die
            _tokenData.hp = _tokenData.hp.sub(times.mul(attackDMG));
            emit NFTAttacked(attackerTokenId, attackedTokenId, times.mul(attackDMG));
        }
    }

    /**
     * HIDE NFT
     */

    // Checks if NFT is of type 1 and still hidden by block.timestamp
    function isNFTHidden(uint256 tokenId) public view returns (bool) {
        TokenData storage _tokenData = tokenData[tokenId];
        require(_tokenData._type == 1, "Bad token");
        return _tokenData.hiddenUntil >= block.timestamp;
    }

    // Hides your NFT from any other attacks for a certain amount of days
    function hideNFT(
        address from,
        uint256 tokenId,
        uint256 _days
    ) external {
        require(gameActive, "Game is not active");

        // Checks if you own your NFT and the tokens required
        require(isTokensYours(from, 0, _days.mul(hideStormCost)), "Not enough");
        require(isTokensYours(from, tokenId, 1), "Not yours");

        // Checks if your NFT is of type 1, not dead nor hidden
        require(!isNFTDead(tokenId), "NFT is dead");
        require(!isNFTHidden(tokenId), "NFT is already hidden");

        // Burns the amount of STORM tokens required
        _burn(from, 0, _days.mul(hideStormCost));

        // Hides your NFT for the specified amount of days
        TokenData storage _tokenData = tokenData[tokenId];
        _tokenData.hiddenUntil = block.timestamp.add(_days.mul(86400));
        emit NFTHidden(tokenId, _tokenData.hiddenUntil);
    }

    /**
     * USE SPECIAL ITEM
     */

    // Uses special item by your NFT on other NFTs or your own
    function useSpecialItem(
        address from,
        uint256 fromTokenId,
        uint256 toTokenId,
        uint256 itemTokenId
    ) external {
        require(gameActive, "Game is not active");

        // Checks if you own your NFT and your item
        require(isTokensYours(from, fromTokenId, 1), "Not yours");
        require(isTokensYours(from, itemTokenId, 1), "Not yours");

        // Checks if your and the target NFT is of type 1 and not dead
        require(!isNFTDead(fromTokenId), "NFT is dead");
        require(!isNFTDead(toTokenId), "Target NFT is dead");

        // Checks if the item is of correct type (weapon or heal)
        TokenData storage _itemTokenData = tokenData[itemTokenId];
        require(_itemTokenData._type == 3 || _itemTokenData._type == 4, "Bad token");

        // Burn the item
        _burn(from, itemTokenId, 1);

        // Calculate the HP modifier (based on the percentage of the target NFT's HP)
        TokenData storage _tokenData = tokenData[toTokenId];
        uint256 hpModifier = _tokenData.hp.mul(_itemTokenData.hp).div(100);

        // If it is a weapon the HP should be equal to the modifier,
        // otherwise add it to the current HP.
        _tokenData.hp = (_itemTokenData._type == 3) ? hpModifier : _tokenData.hp.add(hpModifier);
    }
}