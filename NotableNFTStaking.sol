// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

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

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

interface NBLInterface {
  function transferFrom(address from, address to, uint256 amount) external;
  function transfer(address to, uint256 amount) external;
  function balanceOf(uint256 amount) external returns (uint256);
}

contract NBLStaking {
  struct info {
    uint256 balance;
    uint256 deposited;
  }
  mapping(address => info) public data;
  uint256 public killed = 0;
  uint256 public maxFee;
  uint256 public APY;
  uint256 public treasury;
  address public owner;
  NBLInterface public NBLToken;

  event FeeChanged(uint256 amount);
  event NBLAddressChanged(address nbl);
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  event Rewarded(address indexed user, uint256 amount);
  event Staked(address indexed user, uint256 amount);
  event Unstaked(address indexed user, uint256 amount);

  constructor(address nbl, uint256 fee, uint256 apy) {
    maxFee = fee;
    APY = apy;
    NBLToken = NBLInterface(nbl);
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(owner == msg.sender, "ERROR: ONLY OWNER");
    _;
  }

  function transferOwnership(address _owner) external onlyOwner {
    owner = _owner;
    emit OwnershipTransferred(msg.sender, owner);
  }

  function kill() external onlyOwner {
    require(killed == 0, "ERROR: ALREADY KILLED");
    killed = block.timestamp;
  }

  function changeFee(uint256 fee) external onlyOwner {
    maxFee = fee;
    emit FeeChanged(maxFee);
  }

  function setNBLAddress(address nbl) external onlyOwner {
    NBLToken = NBLInterface(nbl);
    emit NBLAddressChanged(nbl);
  }

  function getReward(address user) public view returns (uint256) {
    uint256 day;
    if (killed == 0) {
      day = (block.timestamp - data[user].deposited) / 1 days;
    } else {
      day = (killed - data[user].deposited) / 1 days;
    }
    return (((data[user].balance * day) / 365) * APY) / 100;
  }

  function calcWithdrawAmount(address user) public view returns (uint256) {
    uint256 day = (block.timestamp - data[user].deposited) / 1 days;
    uint256 amount = data[user].balance + getReward(user);
    if (day >= 30 || killed != 0) {
      return amount;
    } else {
      return amount - (amount * maxFee - (amount * maxFee * day) / 30) / 100;
    }
  }

  function stake(uint256 amount) external {
    require(killed == 0, "ERROR: PLEASE USE THE NEWER CONTRACT");
    NBLToken.transferFrom(msg.sender, address(this), amount);
    uint256 reward = getReward(msg.sender);
    emit Rewarded(msg.sender, reward);
    emit Staked(msg.sender, amount);
    data[msg.sender].balance += amount + reward;
    data[msg.sender].deposited = block.timestamp;
  }

  function unstake() external {
    require(data[msg.sender].balance > 0, "ERROR: BALANCE");
    uint256 amount = calcWithdrawAmount(msg.sender);
    if (amount < data[msg.sender].balance) {
      treasury += data[msg.sender].balance - amount;
    } else {
      treasury -= amount - data[msg.sender].balance;
    }
    NBLToken.transfer(msg.sender, amount);
    emit Rewarded(msg.sender, getReward(msg.sender));
    emit Unstaked(msg.sender, amount);
    data[msg.sender].balance = 0;
    data[msg.sender].deposited = 0;
  }

  function emergencyWithdraw() external {
    require(data[msg.sender].balance > 0, "ERROR: BALANCE");
    uint256 amount = calcWithdrawAmount(msg.sender);
    require(amount > data[msg.sender].balance && (amount - data[msg.sender].balance) > treasury, "ERROR: YOU CAN USE THE NORMAL UNSTAKE");
    amount = data[msg.sender].balance + treasury;
    NBLToken.transfer(msg.sender, amount);
    emit Rewarded(msg.sender, treasury);
    emit Unstaked(msg.sender, amount);
    treasury = 0;
    data[msg.sender].balance = 0;
    data[msg.sender].deposited = 0;
  }

  function depositTreasury(uint256 amount) external onlyOwner {
    NBLToken.transferFrom(msg.sender, address(this), amount);
    treasury += amount;
  }

  function withdrawTreasury(uint256 amount) external onlyOwner {
    require(treasury >= amount, "ERROR: NOT ENOUGH FUNDS IN TREASURY");
    NBLToken.transfer(msg.sender, amount);
    treasury -= amount;
  }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract creatorGas {
  struct addresses {
    address one;
    address two;
    uint256 dist;
  }
  mapping(uint256 => address) mSingle;
  mapping(uint256 => address[]) mMulti;
  mapping(uint256 => uint256[]) mDist;
  mapping(uint256 => addresses) mFixed;

  function setSingle(uint256 token, address one) external {
    mSingle[token] = one;
  }

  function setFixed(uint256 token, address one, address two, uint256 dist) external {
    mFixed[token].one = one;
    mFixed[token].two = two;
    mFixed[token].dist = dist;
  }

  function setMultiple(uint256 token, address[] memory multi, uint256[] memory distribution) external {
    require(distribution.length == multi.length && multi.length > 0 && multi.length <= 10, "ERROR: ARRAY SIZE");
    for (uint i = 0; i < multi.length; i++) {
      mMulti[token].push(multi[i]);
      mDist[token].push(distribution[i]);
    }
  }

  function sendSingle(uint token) external payable {
    payable(mSingle[token]).transfer(msg.value);
  }

  function sendFixed(uint token) external payable {
    payable(mFixed[token].one).transfer((msg.value * mFixed[token].dist) / 100);
    if (mFixed[token].two != address(0)) {
      payable(mFixed[token].two).transfer((msg.value * (100 - mFixed[token].dist)) / 100);
    }
  }

  function sendMultiple(uint token) external payable {
    for (uint i = 0; i < mMulti[token].length; i++) {
      payable(mMulti[token][i]).transfer((msg.value * mDist[token][i]) / 100);
    }
  }
}
// SPDX-License-Identifier: MIT

pragma solidity >=0.4.22 <0.9.0;

import "./owner.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";

interface STAKE {
  struct info {
    uint256 balance;
    uint256 deposited;
  }
  function data(address addr) external view returns (info memory);
}

interface ERC20TokenInterface {
  function transferFrom(address from, address to, uint256 amount) external;
  function allowance(address owner, address spender) external returns (uint256);
}

/// @author NotableNFT
/// @title Experience NFT smart contract 

contract eNFT is ERC721, Owner {
  event Redeemed(address indexed user, uint256 token);
  event Used(address indexed creator, uint256 token);
  event Traded(address indexed from, address indexed to, uint256 token, uint256 nonce);
  event Minted(address indexed creator, address indexed user, uint256 token, uint256 nonce);
  event NFTChanged(uint256 indexed token, uint256 start, uint256 expire, uint256 pending, uint8 status);
  event MetadataChanged(uint256 indexed token, string metadata);
  event cancelMNonce(address indexed user, uint256 nonce);
  event cancelTNonce(address indexed user, uint256 nonce);
  event revokedApproval(address user);

  /**
   * @dev Main properties of the NFT:
   * 
   */
  struct NFT {
    uint256 start;
    uint256 expire;
    uint256 pending;
    uint8 status;
    bool locked;
    string metadata;
  }

  struct RoyaltyInfo {
    address[] creators;
    uint8[] dist;
  }
  mapping(uint256 => NFT) public data;
  mapping(uint256 => RoyaltyInfo) royalties;
  mapping(address => mapping(uint256 => uint256)) public nonce;
  mapping(address => mapping(uint256 => bool)) public tradeNonce;
  mapping(address => bool) public allowContract;
  mapping(address => bool) public allowedForApproval;
  
  address public authorizer;
  address public nProfit;
  address public nFund;
  STAKE public staking;

  uint256 public TRADE_PROFIT = 2;
  uint256 public PROFIT = 9;
  uint256 public TRADE_BASE = 4;
  uint256 public BASE = 85;
  uint256 public VALUE = 87;

  uint256 public totalSupply = 0;

  struct tier {
    uint256 holding;
    uint256 bonus;
  }
  tier[4] public cTiers;
  tier[4] public pTiers;


  constructor(address profit, address fund, address auth, address stake) ERC721("Experience NFT", "eNFT") {
    nProfit = profit;
    nFund = fund;
    staking = STAKE(stake);
    authorizer = auth;
    allowedForApproval[address(0)] = true;
  }

  function allowForApproval(address _contract) external onlyOwner {
    allowedForApproval[_contract] = true;
  }
  function disallowForApproval(address _contract) external onlyOwner {
    require(_contract != address(0), "ERROR: Address 0 has to be allowed for approvals");
    allowedForApproval[_contract] = false;
  }

  function approve(address to, uint256 tokenId) public override {
    require(allowedForApproval[to], "ERROR: NOT ALLOWED FOR APPROVAL");
    super.approve(to, tokenId);
  }

  function changeProfitAddress(address addr) external onlyOwner {
    nProfit = addr;
  }
  function changeFundAddress(address addr) external onlyOwner {
    nFund = addr;
  }
  function changeStakingAddress(address addr) external onlyOwner {
    staking = STAKE(addr);
  }
  function changeAuthorizationAddress(address addr) external onlyOwner {
    authorizer = addr;
  }

  /**
   * Backdoor function that changes a specific Token parameters
   * @param _tokenId is the Token ID that need to be updated
   * @param _start start timestamp
   * @param _expire expire date
   * @param _pending pending
   * @param _status status
   * @param _creators creators addresses to split royalties
   * @param _dist royalites distribution percentage

   * @dev Backdoor function that changes a specific Token parameters
   */
  function changeToken(uint256 _tokenId, uint256 _start, uint256 _expire, uint256 _pending, uint8 _status, address[] memory _creators, uint8[] memory _dist) external onlyOwner {
    require(_creators.length <= 10 && _dist.length == _creators.length - 1, "ERROR: ARRAY SIZE");
    data[_tokenId].start = _start;
    if (!data[_tokenId].locked) {
      data[_tokenId].expire = _expire;
      royalties[_tokenId].creators = _creators;
    }
    royalties[_tokenId].dist = _dist;
    data[_tokenId].pending = _pending;
    data[_tokenId].status = _status;
    emit NFTChanged(_tokenId, _start, _expire, _pending, _status);
  }

  function updateMetadata(uint256 _tokenId, string calldata _metadata) external onlyOwner {
    data[_tokenId].metadata = _metadata;
    emit MetadataChanged(_tokenId, _metadata);
  }

  function tokenURI(uint256 tokenId) public view override returns (string memory) {
    require(tokenId <= totalSupply && totalSupply != 0, "ERC721Metadata: URI query for nonexistent token");
    return string(abi.encodePacked("ipfs://", data[tokenId].metadata));
  }

  /**
   * Change trading percentages
   * @param tp trade profit
   * @param p profit
   * @param tb trade base
   * @param b base
   * @param v value

   * @dev Change trading percentages
   */
  function  setPercentages(uint256 tp, uint256 p, uint256 tb, uint256 b, uint256 v) external onlyOwner {
    TRADE_PROFIT = tp;
    PROFIT = p;
    TRADE_BASE = tb;
    BASE = b;
    VALUE = v;
  }

  function setCreatorTiers(tier calldata one, tier calldata two, tier calldata three, tier calldata four) external onlyOwner {
    cTiers[0] = one;
    cTiers[1] = two;
    cTiers[2] = three;
    cTiers[3] = four;
  }


  /**
   cashback
   */
  function setPurchaseTiers(tier calldata one, tier calldata two, tier calldata three, tier calldata four) external onlyOwner {
    pTiers[0] = one;
    pTiers[1] = two;
    pTiers[2] = three;
    pTiers[3] = four;
  }

  /**
   * @notice Calculates the price of the trade considering the amount of NBL staked
   * @dev Calculates the price of the trade considering the amount of NBL staked
   * @param user addres of the user
   * @param _price price of the operation
   * @return price returned price considering the discount
   */
  function getPrice(address user, uint256 _price) public view returns (uint256) {
    return _price - _price * getStakingBenefit(user, true) / 10000; // Allow 2 decimal points after %
  }

  /**
   * @notice Calculate benefit according to the amount of NBL staked in the staking contract at 0x38864dbF09406E98B258Cc73f4e3fdE321D2Ae0F
   * @dev Calculate benefit according to the amount of NBL staked in the staking contract at 0x38864dbF09406E98B258Cc73f4e3fdE321D2Ae0F 
   * @param user address of the purchaser
   * @param purchaser boolean flag to choose the tier between purchaser and creator
   * @return bonus The bonus percentage depending of the amount of NBL staked
   */
  function getStakingBenefit(address user, bool purchaser) public view returns (uint256) {
    tier[4] memory Tiers;
    if (purchaser) Tiers = pTiers;
    else Tiers = cTiers;
    uint256 balance = staking.data(user).balance;
    if (balance >= Tiers[0].holding) {
      for (uint256 i = 1; i < 4; i++) {
        if (balance < Tiers[i].holding) {
          return Tiers[i - 1].bonus;
        }
      }
    }
    return 0;
  }

  function cancelMintNonce(uint256 _nonce) external {
    require(nonce[msg.sender][_nonce] == 0, "ERROR: USED NONCE");
    nonce[msg.sender][_nonce] = 1;
    emit cancelMNonce(msg.sender, _nonce);
  }

  function cancelTradeNonce(uint256 _nonce) external {
    require(tradeNonce[msg.sender][_nonce] == false, "ERROR: USED NONCE");
    tradeNonce[msg.sender][_nonce] = true;
    emit cancelTNonce(msg.sender, _nonce);
  }

  function tokenData(uint256 _tokenId) external view returns (NFT memory, address) {
    return (data[_tokenId], royalties[_tokenId].creators[0]);
  }

  /**
   * Minting function
   * @param _currency token used for payment
   * @param _nums Price for minting, start of token, expiration of token, nonce
   * @param _creators array of addresses for royalties distribution
   * @param _dist array of percentages for the royalties distribution 
   * @param _locked boolean flag to check the possibility to change some parameters of the token
   * @param _signature backend signature required for the minting

   * @dev Minting function
   */
  function mint(address _currency, uint256[] memory _nums, address[] calldata _creators, uint8[] calldata _dist, bool _locked, string memory _metadata, bytes calldata _signature) external {
    require(_creators.length <= 10 && _dist.length == _creators.length - 1, "ERROR: ARRAY SIZE");
    require(nonce[_creators[0]][_nums[3]] == 0, "ERROR: USED NONCE");
    require(mintSigner(_currency, _nums, _creators, _dist, _locked, _metadata, _signature) == authorizer, "ERROR: BAD SIGNATURE");
    uint256 requiredAmount = getPrice(msg.sender, _nums[0]);

    totalSupply += 1;
    nonce[_creators[0]][_nums[3]] = totalSupply;
    _mint(msg.sender, totalSupply);
    data[totalSupply] = NFT(_nums[1], _nums[2], 0, 0, _locked, _metadata);
    royalties[totalSupply] = RoyaltyInfo(_creators, _dist);
    distributeFunds(msg.sender, _currency, totalSupply, _nums[0], requiredAmount, false, _creators, _dist);
    emit Minted(_creators[0], msg.sender, totalSupply, _nums[3]);
  }

  /**
   * Trading function called by the Notable Marketplace to sell the token
   * @param _currency token used for payment
   * @param _price token sell price
   * @param _tokenId token ID
   * @param _nonce signature nonce to avoid replay attacks
   * @param _timestamp timestamp to expire old signatures 
   * @param signature signature of the backend

   * @dev Trading function called by the Notable Marketplace to sell the token and trigger royalties
   */
  function trade(address _buyer, address _currency, uint256 _price, uint256 _tokenId, uint256 _nonce, uint256 _timestamp, bytes calldata signature) external {
    require(tradeNonce[ownerOf(_tokenId)][_nonce] == false, "ERROR: USED NONCE");
    require(_timestamp >= (block.timestamp - 1 days) && _timestamp < block.timestamp, "ERROR: TIME"); 
    require(tradeSigner(_currency, _price, _tokenId, ownerOf(_tokenId), _buyer, _nonce, _timestamp, signature) == authorizer, "ERROR: BAD SIGNATURE");
    require(allowContract[ownerOf(_tokenId)], "ERROR: SELLER HAS NOT AUTHORIZED THE CONTRACT");
    uint256 requiredAmount = getPrice(_buyer, _price);

    tradeNonce[ownerOf(_tokenId)][_nonce] = true;
    distributeFunds(_buyer, _currency, _tokenId, _price, requiredAmount, true, royalties[_tokenId].creators, royalties[_tokenId].dist);
    emit Traded(ownerOf(_tokenId), _buyer, _tokenId, _nonce);
    _transfer(ownerOf(_tokenId), _buyer, _tokenId);
  }

  /**
   * Minting function
   * @param _nums Price for minting, start of token, expiration of token, nonce
   * @param _creators array of addresses for royalties distribution
   * @param _dist array of percentages for the royalties distribution 
   * @param _locked boolean flag to check the possibility to change some parameters of the token
   * @param _signature backend signature required for the minting

   * @dev Minting function
   */
  function mintETH(uint256[] memory _nums, address[] calldata _creators, uint8[] calldata _dist, bool _locked, string memory _metadata, bytes calldata _signature) external payable {
    require(_creators.length <= 10 && _dist.length == _creators.length - 1, "ERROR: ARRAY SIZE");
    require(nonce[_creators[0]][_nums[3]] == 0, "ERROR: USED NONCE");
    require(mintSigner(address(0), _nums, _creators, _dist, _locked, _metadata, _signature) == authorizer, "ERROR: BAD SIGNATURE");
    uint256 requiredAmount = getPrice(msg.sender, _nums[0]);
    require(msg.value >= requiredAmount, "ERROR: PAYMENT AMOUNT");
    if (msg.value > requiredAmount) payable(msg.sender).transfer(msg.value - requiredAmount);    

    totalSupply += 1;
    nonce[_creators[0]][_nums[3]] = totalSupply;
    _mint(msg.sender, totalSupply);
    data[totalSupply] = NFT(_nums[1], _nums[2], 0, 0, _locked, _metadata);
    royalties[totalSupply] = RoyaltyInfo(_creators, _dist);
    distributeFundsETH(totalSupply, _nums[0], false, _creators, _dist);
    emit Minted(_creators[0], msg.sender, totalSupply, _nums[3]);
  }

  /**
   * Trading function called by the Notable Marketplace to sell the token
   * @param _price token sell price
   * @param _tokenId token ID
   * @param _nonce signature nonce to avoid replay attacks
   * @param _timestamp timestamp to expire old signatures 
   * @param signature signature of the backend

   * @dev Trading function called by the Notable Marketplace to sell the token and trigger royalties
   */
  function tradeETH(uint256 _price, uint256 _tokenId, uint256 _nonce, uint256 _timestamp, bytes calldata signature) external payable {
    require(tradeNonce[ownerOf(_tokenId)][_nonce] == false, "ERROR: USED NONCE");
    require(_timestamp >= (block.timestamp - 1 days) && _timestamp < block.timestamp, "ERROR: TIME"); 
    require(tradeSigner(address(0), _price, _tokenId, ownerOf(_tokenId), msg.sender, _nonce, _timestamp, signature) == authorizer, "ERROR: BAD SIGNATURE");
    require(allowContract[ownerOf(_tokenId)], "ERROR: SELLER HAS NOT AUTHORIZED THE CONTRACT");
    uint256 requiredAmount = getPrice(msg.sender, _price);
    require(msg.value >= requiredAmount, "ERROR: PAYMENT AMOUNT");
    if (msg.value > requiredAmount) payable(msg.sender).transfer(msg.value - requiredAmount);

    tradeNonce[ownerOf(_tokenId)][_nonce] = true;
    distributeFundsETH(_tokenId, _price, true, royalties[_tokenId].creators, royalties[_tokenId].dist);
    emit Traded(ownerOf(_tokenId), msg.sender, _tokenId, _nonce);
    _transfer(ownerOf(_tokenId), msg.sender, _tokenId);
  }

  /**
   * Changes the status of the token to REDEEMED
   * @param _tokenId Token ID
   * @param timestamp signature timestamp to avoid double redeeming, adding an expiration validity for the signature
   * @param signature signature of the backend

   * @dev Changes the status of the token
   */
  function redeem(uint256 _tokenId, uint256 timestamp, bytes calldata signature) external {
    require(msg.sender == ownerOf(_tokenId), "ERROR: ONLY OWNER CAN REDEEM");
    require(block.timestamp >= data[_tokenId].start && block.timestamp < data[_tokenId].expire, "ERROR: TIME");
    require(data[_tokenId].status == 0 || (data[_tokenId].status == 1 && (block.timestamp - 90 days) >= data[_tokenId].pending), "ERROR: TOKEN CANNOT BE REDEEMED");
    require(redeemSigner(_tokenId, timestamp, signature) == authorizer && (block.timestamp - 1 days) < timestamp && timestamp < block.timestamp, "ERROR: BAD SIGNATURE");
    data[_tokenId].status = 1;
    data[_tokenId].pending = block.timestamp;
    emit Redeemed(msg.sender, _tokenId); 
  }

  
  /**
   * Changes the status of the token to USED
   */
  function used(uint256 _tokenId) external {
    require(msg.sender == royalties[_tokenId].creators[0], "ERROR: ONLY THE MAIN CREATOR CAN CHANGE STATUS TO USED");
    require(data[_tokenId].status == 1 && (block.timestamp - 90 days) < data[_tokenId].pending, "ERROR: TOKEN STATUS CANNOT BE SET TO USED");
    data[_tokenId].status = 2;
    emit Used(msg.sender, _tokenId);
  }

  function redeemable(uint256 _tokenId) external {
    require(data[_tokenId].status == 1 && (block.timestamp - 90 days) >= data[_tokenId].pending, "ERROR: CANNOT REVERT TOKEN BACK TO REDEEMABLE");
    data[_tokenId].status = 0;
    data[_tokenId].pending = 0;
  }

  function distributeFunds(address _buyer, address _currency, uint256 _tokenId, uint256 _price, uint256 _required, bool _trade, address[] memory _creators, uint8[] memory _dist) internal {
    uint256 sent;
    uint256 base;
    ERC20TokenInterface tkn = ERC20TokenInterface(_currency);

    if (_trade) {
      tkn.transferFrom(_buyer, nProfit, _price * TRADE_PROFIT / 100);
      sent = (_price * TRADE_PROFIT / 100);
      tkn.transferFrom(_buyer, ownerOf(_tokenId), _price * VALUE / 100);
      sent += _price * VALUE / 100;
      base = TRADE_BASE;
    } else {
      tkn.transferFrom(_buyer, nProfit, _price * PROFIT / 100);
      sent = (_price * PROFIT / 100);
      base = BASE;
    }

    uint256 last = 100;
    uint256 cut;
    for (uint256 i = 0; i < _dist.length; i++) {
      cut = (_price * (base * 100 + getStakingBenefit(_creators[i], false)) / 10000) * _dist[i] / 100;
      tkn.transferFrom(_buyer, _creators[i], cut);
      sent += cut;
      last -= _dist[i];
    }
    cut = (_price * (base * 100 + getStakingBenefit(_creators[_dist.length], false)) / 10000) * last / 100;
    tkn.transferFrom(_buyer, _creators[_dist.length], cut);
    sent += cut;

    tkn.transferFrom(_buyer, nFund, _required - sent);
  }

  function distributeFundsETH(uint256 _tokenId, uint256 _price, bool _trade, address[] memory _creators, uint8[] memory _dist) internal {
    uint256 sent;
    uint256 base;

    if (_trade) {
      payable(nProfit).transfer(_price * TRADE_PROFIT / 100);
      sent = (_price * TRADE_PROFIT / 100);
      payable(ownerOf(_tokenId)).transfer(_price * VALUE / 100);
      sent += _price * VALUE / 100;
      base = TRADE_BASE;
    } else {
      payable(nProfit).transfer(_price * PROFIT / 100);
      sent = (_price * PROFIT / 100);
      base = BASE;
    }

    uint256 last = 100;
    uint256 cut;
    for (uint256 i = 0; i < _dist.length; i++) {
      cut = (_price * (base * 100 + getStakingBenefit(_creators[i], false)) / 10000) * _dist[i] / 100;
      payable(_creators[i]).transfer(cut);
      sent += cut;
      last -= _dist[i];
    }
    cut = (_price * (base * 100 + getStakingBenefit(_creators[_dist.length], false)) / 10000) * last / 100;
    payable(_creators[_dist.length]).transfer(cut);
    sent += cut;

    payable(nFund).transfer(msg.value - sent);
  }

  function royaltyInfoArray(uint256 _tokenId, uint256 _salePrice) external view returns (address[12] memory receiver, uint256[12] memory royaltyAmount) {
    uint256 sent;

    address[12] memory receivers;
    uint256[12] memory amounts;

    address[] memory _creators = royalties[_tokenId].creators;
    uint8[] memory _dist = royalties[_tokenId].dist;

    receivers[0] = nProfit;
    amounts[0] = _salePrice * PROFIT / 100;
    sent = (_salePrice * PROFIT / 100);

    uint256 last = 100;
    for (uint256 i = 0; i < _dist.length; i++) {
      receivers[2 + i] = _creators[i];
      amounts[2 + i] = (_salePrice * (BASE * 100 + getStakingBenefit(_creators[i], false)) / 10000) * _dist[i] / 100;
      sent += amounts[2 + i];
      last -= _dist[i];
    }
    receivers[2 + _dist.length] = _creators[_dist.length];
    amounts[2 + _dist.length] = (_salePrice * (BASE * 100 + getStakingBenefit(_creators[_dist.length], false)) / 10000) * last / 100;
    sent += amounts[2 + _dist.length];

    receivers[1] = nFund;
    amounts[1] = _salePrice - sent;
    return (receivers, amounts);
  }

  function redeemSigner(uint256 _tokenId, uint256 timestamp, bytes calldata _signature) public pure returns (address) {
    bytes memory _data = abi.encodePacked(_tokenId, timestamp);
    return ECDSA.recover(
        ECDSA.toEthSignedMessageHash(keccak256(_data)),
        _signature
      );
  }

  function tradeSigner(address _currency, uint256 _price, uint256 _tokenId, address _owner, address _buyer, uint256 _nonce, uint256 _timestamp, bytes calldata _signature) public pure returns (address) {
    bytes memory _data = abi.encodePacked(_currency, _price, _tokenId, _owner, _buyer, _nonce, _timestamp);
    return ECDSA.recover(
        ECDSA.toEthSignedMessageHash(keccak256(_data)),
        _signature
      );
  }

  function mintSigner(address _currency, uint256[] memory _nums, address[] memory _creators, uint8[] memory _dist, bool _locked, string memory _metadata, bytes calldata _signature) public pure returns (address) {
    bytes memory _data = abi.encodePacked(_currency, _nums[0], _nums[1], _nums[2], _nums[3], _locked, _metadata);
    for (uint256 i = 0; i < _creators.length - 1; i++) {
      _data = abi.encodePacked(_data, _creators[i], _dist[i]);
    }
    _data = abi.encodePacked(_data, _creators[_creators.length - 1]);
    return ECDSA.recover(
        ECDSA.toEthSignedMessageHash(keccak256(_data)),
        _signature
      );
  }

  function approveContract() external {
    allowContract[msg.sender] = true;
  }

  function revokeContractApproval() external {
    allowContract[msg.sender] = false;
    emit revokedApproval(msg.sender);
  }
  function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal view override {
    require(data[tokenId].status != 1 || (data[tokenId].status == 1 && (block.timestamp - 90 days) >= data[tokenId].pending), "ERROR: PENDING TOKENS CANNOT BE TRANSFERRED");
  }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

interface ERC20Interface {
  function transferFrom(address from, address to, uint256 amount) external;
  function transfer(address to, uint256 amount) external;
  function balanceOf(uint256 amount) external returns (uint256);
}

contract lockingGas {
  struct history {
    uint256 balance;
    uint256 date;
  }

  mapping(address => uint256) mBalance;
  mapping(address => uint256) mDeposited;
  mapping(address => uint256) mUnlock;
  mapping(address => history[]) mHistory;

  ERC20Interface public token;

  uint punishment = 10;

  function setToken(address _token) external {
    token = ERC20Interface(_token);
  }

  function getAverage(address user) public view returns (uint256) {
    if (mHistory[user].length == 0) return 0;
    uint256 duration = 30 days;
    uint256 avg = 0;
    for (uint256 i = mHistory[user].length; i > 0; i--) {
      uint256 length = mHistory[user][i - 1].date;
      if (i == mHistory[user].length) length = block.timestamp - length;
      if (length > duration) {
        length = duration;
        avg += (mHistory[user][i - 1].balance / 30) * (length / 1 days);
        break;
      } else {
        duration -= length;
        avg += (mHistory[user][i - 1].balance / 30) * (length / 1 days);
      }
    }
    return avg;
  }

  function deposit(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    mBalance[msg.sender] += amount;
    mDeposited[msg.sender] = block.timestamp;
  }
  function depositLocking(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    mBalance[msg.sender] += amount;
    mUnlock[msg.sender] = block.timestamp + 30 days;
  }
  function depositAverage(uint256 amount) external {
    token.transferFrom(msg.sender, address(this), amount);
    mBalance[msg.sender] += amount;
    if (mHistory[msg.sender].length > 0) {
      uint256 last = mHistory[msg.sender].length - 1;
      uint256 duration = block.timestamp - mHistory[msg.sender][last].date;
      if (duration < 1 days) {
        mHistory[msg.sender][last].balance = mBalance[msg.sender];
      } else {
        mHistory[msg.sender][last].date = duration;
        mHistory[msg.sender].push(history(mBalance[msg.sender], block.timestamp));
      }
    } else {
      mHistory[msg.sender].push(history(mBalance[msg.sender], block.timestamp));
    }
  }

  function withdraw(uint256 amount) external {
    require(mBalance[msg.sender] >= amount, "ERROR: BALANCE");
    token.transfer(msg.sender, (amount * (100 - punishment)) / 100);
    mBalance[msg.sender] -= amount;
    mDeposited[msg.sender] = block.timestamp;
  }

  function withdrawLocking() external {
    require(block.timestamp >= mUnlock[msg.sender], "ERROR: LOCKED");
    require(mBalance[msg.sender] > 0, "ERROR: BALANCE");
    token.transfer(msg.sender, mBalance[msg.sender]);
    mBalance[msg.sender] = 0;
    mUnlock[msg.sender] = 0;
  }

  function withdrawAverage(uint256 amount) external {
    require(mBalance[msg.sender] >= amount, "ERROR: BALANCE");
    token.transfer(msg.sender, amount);
    mBalance[msg.sender] -= amount;
    uint256 last = mHistory[msg.sender].length - 1;
    uint256 duration = block.timestamp - mHistory[msg.sender][last].date;
    if (duration < 1 days) {
      mHistory[msg.sender][last].balance = mBalance[msg.sender];
    } else {
      mHistory[msg.sender][last].date = duration;
      mHistory[msg.sender].push(history(mBalance[msg.sender], block.timestamp));
    }
  }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract Owner {
  address public owner;
  event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

  constructor() {
    owner = msg.sender;
  }

  modifier onlyOwner() {
    require(owner == msg.sender, "ERROR: ONLY OWNER");
    _;
  }

  function transferOwnership(address _owner) external onlyOwner {
    owner = _owner;
    emit OwnershipTransferred(msg.sender, owner);
  }
}
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract token is ERC20 {
  constructor() ERC20("TKN", "Token") {}
  function mint(address to, uint256 amount) external {
    _mint(to, amount);
  }
}