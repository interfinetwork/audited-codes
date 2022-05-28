// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";

contract AnimeVerseNFT is ERC721Enumerable, Ownable {
    using Counters for Counters.Counter;
    using Strings for uint256;
    
    uint256 public MAX_SUPPLY = 150;

    uint256 public COST = 0.1  ether;

    string private BASE_URI;
    string private UNREVEAL_URI;

    Counters.Counter private _COUNTER;

    bool public PAUSED = true;
    constructor() ERC721("AnimeVerse NFT", "AVNFT") {}

    function togglePause() public onlyOwner {
        PAUSED = !PAUSED;
    }

    function setUnevealURI(string memory unrevealURI) external onlyOwner {
        UNREVEAL_URI = unrevealURI;
    }

    function setBaseURI(string memory baseURI) external onlyOwner {
        BASE_URI = baseURI;
    }

    function setMintPrice(uint256 price) external onlyOwner {
        COST = price;
    }

    function setMaxLimit(uint256 maxLimit) external onlyOwner {
        MAX_SUPPLY = maxLimit;
    }

    function airdrop(address to, uint256 numberOfTokens) external onlyOwner {
        require(_COUNTER.current() + numberOfTokens < MAX_SUPPLY, "Purchase would exceed MAX_SUPPLY");
        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _COUNTER.current();
            _safeMint(to, tokenId);
            _COUNTER.increment();
        }
    }

    function mint(uint256 numberOfTokens) external payable {
        require(!PAUSED, "Sale is not opened");

        require(_COUNTER.current() + numberOfTokens < MAX_SUPPLY,"Purchase would exceed MAX_SUPPLY");

        require(COST * numberOfTokens <= msg.value,"ETH amount is not sufficient");

        for (uint256 i = 0; i < numberOfTokens; i++) {
            uint256 tokenId = _COUNTER.current();
            _safeMint(msg.sender, tokenId);
            _COUNTER.increment();
        }
    }

    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");
        return bytes(BASE_URI).length > 0 ? string(abi.encodePacked(BASE_URI, tokenId.toString())) : UNREVEAL_URI;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;

        payable(msg.sender).transfer(balance);
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";

contract AnimeVerseStaking is ReentrancyGuard, Pausable, Ownable, IERC721Receiver {
    using Counters for Counters.Counter;
    using Strings for uint256;
    using EnumerableSet for EnumerableSet.UintSet;
    using SafeERC20 for IERC20;
    /* ------------------------ NFT Staking ------------------------- */
    bool public _enableHarvest = false;

    address public NFT_TOKEN_ADDRESS;
    address public REWARD_TOKEN_ADDRESS;

    uint256 public TOKEN_REWARD_PER_DAY;

    struct UserInfo {
        uint256 rewards;
        uint256 lastUpdated;
    }

    mapping(address => EnumerableSet.UintSet) private userBalances;
    mapping(address => UserInfo) public userInfo;

    address[] public stakerList;

    /* --------------------------------------------------------------------------------- */
    constructor(address _nftAddress, address _rewardTokenAddress, uint256 _rewardPerDay) {
        NFT_TOKEN_ADDRESS = _nftAddress;
        REWARD_TOKEN_ADDRESS = _rewardTokenAddress;
        TOKEN_REWARD_PER_DAY = _rewardPerDay;
    }
    
    function setEnableHarvest (bool _bEnabled) external onlyOwner {
        _enableHarvest = _bEnabled;
    }

    function setTokenRewardPerDay (uint256 _rewardPerDay) external onlyOwner {
        TOKEN_REWARD_PER_DAY = _rewardPerDay;
    }

    function withdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        payable(_msgSender()).transfer(balance);
    }

    function withdrawToken() external onlyOwner {
        IERC20(REWARD_TOKEN_ADDRESS).safeTransfer(_msgSender(), IERC20(REWARD_TOKEN_ADDRESS).balanceOf(address(this)));
    }

    function userHoldNFT(address _owner) public view returns(uint256[] memory){
        uint256 tokenCount = IERC721(NFT_TOKEN_ADDRESS).balanceOf(_owner);
        if (tokenCount == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = IERC721Enumerable(NFT_TOKEN_ADDRESS).tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    /* --------------------------------------------------------------------- */
    function setNFTAddress(address _nftAddress) public onlyOwner {
        NFT_TOKEN_ADDRESS = _nftAddress;
    }
    function setTokenRewardAddress(address _tokenAddress) public onlyOwner {
        REWARD_TOKEN_ADDRESS = _tokenAddress;
    }
    function addStakerList(address _user) internal{
        for (uint256 i = 0; i < stakerList.length; i++) {
            if (stakerList[i] == _user)
                return;
        }
        stakerList.push(_user);
    }

    function userStakeInfo(address _owner) external view returns(UserInfo memory){
         return userInfo[_owner];
    }
    
    function userStakedNFT(address _owner) public view returns(uint256[] memory){
        uint256 tokenCount = userBalances[_owner].length();
        if (tokenCount == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);
            uint256 index;
            for (index = 0; index < tokenCount; index++) {
                result[index] = userBalances[_owner].at(index);
            }
            return result;
        }
    }

    function isStaked( address account ,uint256 tokenId) public view returns (bool) {
        return userBalances[account].contains(tokenId);
    }

    function earned(address account) public view returns (uint256) {
        uint256 blockTime = block.timestamp;

        UserInfo memory user = userInfo[account];

        uint256 amount = (blockTime - user.lastUpdated) * userBalances[account].length() * TOKEN_REWARD_PER_DAY / (1 days);

        return user.rewards + amount;
    }

    function totalEarned() public view returns (uint256) {
        uint256 totalEarning = 0;
        for (uint256 i = 0; i < stakerList.length; i++) {
            totalEarning += earned(stakerList[i]);
        }
        return totalEarning;
    }

    function totalStakedCount() public view returns (uint256) {
        uint256 totalCount = 0;
        for (uint256 i = 0; i < stakerList.length; i++) {
            totalCount += userBalances[stakerList[i]].length();
        }
        return totalCount;
    }

    function totalStakedMembers() public view returns (uint256) {
        uint256 totalMembers = 0;
        for (uint256 i = 0; i < stakerList.length; i++) {
            if (userBalances[stakerList[i]].length() > 0) totalMembers += 1;
        }
        return totalMembers;
    }

    
    function stake( uint256[] calldata _tokenIDList) public nonReentrant whenNotPaused {
        require(IERC721(NFT_TOKEN_ADDRESS).isApprovedForAll(_msgSender(),address(this)),"Not approve nft to staker address");

        addStakerList(_msgSender());

        UserInfo storage user = userInfo[_msgSender()];
        user.rewards = earned(_msgSender());
        user.lastUpdated = block.timestamp;

        for (uint256 i = 0; i < _tokenIDList.length; i++) {
            IERC721(NFT_TOKEN_ADDRESS).safeTransferFrom(_msgSender(), address(this), _tokenIDList[i]);
            
            userBalances[_msgSender()].add(_tokenIDList[i]);
        }
    }

    function unstake( uint256[] memory  tokenIdList) public nonReentrant {
        UserInfo storage user = userInfo[_msgSender()];
        user.rewards = earned(_msgSender());
        user.lastUpdated = block.timestamp;

        for (uint256 i = 0; i < tokenIdList.length; i++) {

            require(isStaked(_msgSender(), tokenIdList[i]), "Not staked this nft");        

            IERC721(NFT_TOKEN_ADDRESS).safeTransferFrom(address(this) , _msgSender(), tokenIdList[i], "");

            userBalances[_msgSender()].remove(tokenIdList[i]);
        }
    }

    function harvest() public nonReentrant {
        require(_enableHarvest == true, "Harvest is not activated");
        
        UserInfo storage user = userInfo[_msgSender()];
        user.rewards = earned(_msgSender());
        user.lastUpdated = block.timestamp;

        require(IERC20(REWARD_TOKEN_ADDRESS).balanceOf(address(this)) >= user.rewards,"Reward token amount is small");

        if (user.rewards > 0) {
            IERC20(REWARD_TOKEN_ADDRESS).safeTransfer(_msgSender(), user.rewards);
        }

        user.rewards = 0;
    }

    function onERC721Received(address, address, uint256, bytes memory) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }

    receive() external payable {}
}

