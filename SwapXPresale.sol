// SPDX-License-Identifier: MIT


// File: contracts\interfaces\IBEP20.sol
interface IBEP20 {
  // @dev Returns the amount of tokens in existence.
  function totalSupply() external view returns (uint256);
  // @dev Returns the token decimals.
  function decimals() external view returns (uint8);
  // @dev Returns the token symbol.
  function symbol() external view returns (string memory);
  //@dev Returns the token name.
  function name() external view returns (string memory);
  //@dev Returns the bep token owner.
  function getOwner() external view returns (address);
  //@dev Returns the amount of tokens owned by `account`.
  function balanceOf(address account) external view returns (uint256);
  /**
   * @dev Moves `amount` tokens from the caller's account to `recipient`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address recipient, uint256 amount) external returns (bool);
  /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
  function allowance(address _owner, address spender) external view returns (uint256);
  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * IMPORTANT: Beware that changing an allowance with this method brings the risk
   * that someone may use both the old and the new allowance by unfortunate
   * transaction ordering. One possible solution to mitigate this race
   * condition is to first reduce the spender's allowance to 0 and set the
   * desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   *
   * Emits an {Approval} event.
   */
  function approve(address spender, uint256 amount) external returns (bool);
  /**
   * @dev Moves `amount` tokens from `sender` to `recipient` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
  //@dev Emitted when `value` tokens are moved from one account (`from`) to  another (`to`). Note that `value` may be zero.
  event Transfer(address indexed from, address indexed to, uint256 value);
  //@dev Emitted when the allowance of a `spender` for an `owner` is set by a call to {approve}. `value` is the new allowance.
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

// File: contracts\libraries\PresaleLib.sol
// PSL stands for Presale Library
library PSL {
    address public constant zeroAddress = 0x0000000000000000000000000000000000000000;
    struct PresaleData {
        uint256 id;
        string token_name;
        string token_symbol;
        uint256 token_decimals;
        PresaleAddresses addresses;
        PresaleIntegers integers;
        string[] strings;
        PresaleRates rates;
        address presale_address;
    }
    struct PresaleAddresses {    
        address token;
        address exchange;
        address factory;
        address payable owner;
        address payable vault;
    }
    struct PresaleIntegers {
        uint256 presale;
        uint256 liquidity;
        uint256 fee;
        uint256 emergency;
        uint256 total;
        uint256 start_date;
        uint256 end_date;
        uint256 liquidity_unlock;
    }
    struct PresaleRates {   
        uint256 softcap;
        uint256 hardcap;
        uint256 min_contrib;
        uint256 max_contrib; 
        uint256 presale_rate;
        uint256 exchange_rate;
        uint256 exchange_percentage;
        uint256 coin_fee_percentage;
    }
    function calculateTokenAmounts(
        uint256 hardcap, // hardcap
        uint256 psr, // presale rate
        uint256 dexr, // exchange rate
        uint256 dexp, // exchange percentage
        uint256 etp, // emergency tokens percent
        uint256 tfp, // token fee percent
        uint256 token_decimals // token decimals
        ) internal pure returns (
            uint256 pst, // presale tokens
            uint256 dext, // exchange tokens
            uint256 ft, // fee tokens
            uint256 et, // emergency tokens
            uint256 tt // token total
        ) {
        uint256 tokenized_hardcap = PSL.tokenizeDecimals(hardcap, token_decimals); // tokenized hard cap
        pst = tokenized_hardcap * psr;
        uint256 dexc;
        (dexc, dext) = calculateLiquidityAmounts(hardcap, dexp, dexr, token_decimals);
        ft = (pst + dext) * tfp / 1000;
        et = (pst + dext) * etp / 1000;
        tt = pst + dext + ft + et;
    }
    function tokenizeDecimals(uint256 coin_amount, uint256 token_decimals) internal pure returns(uint256) {
        if(token_decimals > 18)
            return coin_amount * (10 ** (token_decimals - 18));
        else if(token_decimals < 18)
            return coin_amount / (10 ** (18 - token_decimals));
        return coin_amount;
    }
    function calculateLiquidityAmounts(
        uint256 hardcap, 
        uint256 dex_precentage, 
        uint256 dex_rate,
        uint256 token_decimals) internal pure returns(uint256 dex_coins, uint256 dex_tokens) {
        dex_coins = PSL.multiDiv(hardcap, dex_precentage, 100);
        dex_tokens = dex_rate * PSL.tokenizeDecimals(dex_coins, token_decimals);
    }
    function validateDates(
        uint256 start_date, 
        uint256 end_date, 
        uint256 liquidity_unlock, 
        uint256 timestamp, 
        uint256 max_presale_len) internal pure returns(bool) {
        return (timestamp < start_date) &&  // Chosen start date already passed 
            (start_date < end_date) &&  // End date must be after start
            (end_date < liquidity_unlock) && // Liquidity unlock date must be after presale end
            ((end_date - start_date) < max_presale_len); // Presale too long
    }
    function multiDiv(uint256 value, uint256 percent_value, uint256 precision) internal pure returns(uint256) {
        return (value * percent_value) / precision;
    }
    function subtract(uint256 first, uint256 second) internal pure returns(uint256) {   
        if(first > second) {
            return first - second;
        }
        return 0;
    }
    // A presale is valid when it still hasn't been cancelled, finalized, or failed
    function checkValid(bool cancelled, bool finalized, bool failed) internal pure returns(bool) {
        // If not cancelled or finalized or failed (active or ended)
        return (
            (cancelled == false) &&
            (finalized == false) &&
            (failed == false)
        );
    }
    // A presale is over when it's cancelled, finalized, or failed
    function checkOver(bool cancelled, bool finalized, bool failed) internal pure returns(bool) {
        // If not cancelled or finalized or failed (active or ended)
        return checkValid(cancelled, finalized, failed) == false;
    }
    // Running means pending or active
    function checkRunning(
        bool cancelled,
        bool finalized,
        bool failed,
        bool ended) internal pure returns(bool) {
        // If not cancelled, finalized, failed, or ended
        return (cancelled == false) && (finalized == false) && (failed == false) && (ended == false);
    }
    // Presale time started or not
    function checkTimeStarted(
        uint256 timestamp,
        uint256 startdate,
        uint256 enddate) internal pure returns(bool) {
        // If time less than end date and more than start date
        return (
            (timestamp > startdate) &&
            (timestamp < enddate)
        );
    }
    function checkFailed(
        uint256 balance,
        uint256 softcap,
        uint256 timestamp,
        uint256 enddate) internal pure returns(bool) {
        // Softcap hasn't been reached and the time has ended
        return (
            (balance < softcap) &&
            (timestamp > enddate)
        );
    }
    function checkEnded(
        uint256 balance,
        uint256 hardcap,
        uint256 timestamp,
        uint256 enddate) internal pure returns(bool) {
        // If harcap has been reached or the time has ended
        return (
            (balance >= hardcap) ||
            (timestamp > enddate)
        );
    }
    function canWithdrawTokens(
        bool presale_finalized,
        bool microvaults_enabled,
        bool specific_withdrawl_status
    ) internal pure returns(bool) {
        return (
            (presale_finalized == true) &&
            (microvaults_enabled == false) && // microvaults not be enabled
            (specific_withdrawl_status == false) // User already withdrew tokens?
        );
    }
    function canWithdrawVestTokens(
        bool presale_finalized,
        bool microvaults_enabled,
        bool specific_withdrawl_status,
        uint256 vest,
        uint256 vest_count,
        uint256 timestamp,
        uint256 final_unlock_date,
        uint256 presale_end_date
    ) internal pure returns(bool) {
        return (
            (presale_finalized == true) &&
            (microvaults_enabled == true) && // microvaults enabled
            (vest < vest_count) && // Vest higher than vests count
            (specific_withdrawl_status == false) && // User already withdrew tokens?
            (timestamp > getVestUnlockDate(
                final_unlock_date,
                presale_end_date,
                vest_count,
                vest)) // Not time to unlock
        );
    }
    function getVestUnlockDate(
        uint256 final_unlock_date,
        uint256 presale_end_date,
        uint256 vest_count,
        uint256 vest) internal pure returns(uint256) {            
        uint256 single_chunk = (final_unlock_date - presale_end_date) / vest_count;
        uint256 total_vest_chunks = (single_chunk * (vest + 1));
        return presale_end_date - total_vest_chunks;
    }
    function staticAddressFetch(address contract_address, string memory signature) internal view returns(address) {
      (bool success, bytes memory data) = contract_address.staticcall(
        abi.encodeWithSignature(signature)
      );
      require(success, "PSL-ERR-STATIC-CALL");
      return address(uint160(uint256(bytes32(data))));
    }
    function transferCall(address target_address, uint256 amount) internal {
        (bool success,) = target_address.call{value: amount}(""); 
        require(success, "PSL-ERR-TRANSFER"); // widthdrawl failed
    }
    function transferBEP20(address token, address target, uint256 amount) internal {
      IBEP20(token).transfer(target, amount);
    }
}

// File: contracts\interfaces\ISwapXRouter01.sol
pragma solidity >=0.6.2;
interface ISwapXRouter01 {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountETH);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountETH);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

// File: contracts\interfaces\ISwapXRouter02.sol
pragma solidity >=0.6.2;
interface ISwapXRouter02 is ISwapXRouter01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external returns (uint amountETH);
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountETH);
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}

// File: contracts\interfaces\ISwapXFactory.sol
pragma solidity >=0.5.0;
interface ISwapXFactory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);
    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);
    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);
    function createPair(address tokenA, address tokenB) external returns (address pair);
    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
    function INIT_CODE_PAIR_HASH() external view returns (bytes32);
}

// File: contracts\PresaleV1.sol
contract PresaleV1 {
  // Presale Data
  PSL.PresaleData private _data;
  // Presale Metdata
  bool private _presale_finalized;
  bool private _presale_cancelled;
  bool public _remaining_tokens_withdrawn;
  address private _pair_address;
  uint256[] private _badges;
  mapping(address => uint256) public _user_contributions;
  address[] private _contributors;
  // Whitelisting feature
  bool private _whitelist_enabled;
  mapping(address => bool) public _whitelist_addresses;
  address[] private _whitelist_address_list;
  // Micro Vault Feature
  mapping(address => mapping(uint256 => bool)) public _user_withdrawals;
  bool private _microvaults_enabled;
  uint256 private _microvaults_unlock_date;
  uint256 private _microvaults_vests_count;
  uint256 private _archived_bnb_amount;
  uint256 private _remaining_tokens;
  // Presale core events
  event CancelPresale();
  event FinalizedPresale();
  event ContributedToPresale();
  modifier onlyAdmin() {
      require(msg.sender == PSL.staticAddressFetch(_data.addresses.factory, '_owner()'), "PS: Not Admin");
      _;
  }
  modifier onlyOwner() {
      require(
        (msg.sender == _data.addresses.owner) ||
        (msg.sender == PSL.staticAddressFetch(_data.addresses.factory, '_owner()')),
        "PS: Not Owner"
      );
      _;
  }
  modifier hasContribution() {
    require(_user_contributions[msg.sender] > 0, "PS: Not Contributer");
    _;
  }
  modifier presaleValid() {
    require(
      PSL.checkValid(_presale_cancelled, _presale_finalized, _hasPresaleFailed()),
      "PS: Not active/pending/ended."
    );
    _;
  }
  modifier presalePending() {
    require(block.timestamp < _data.integers.start_date, "PS: Not pending");
    _;
  }
  modifier presaleRunning() {
    require(PSL.checkRunning(_presale_cancelled, _presale_finalized, _hasPresaleFailed(), _hasPresaleEnded()), "PS: Not running.");
    _;
  }
  constructor(PSL.PresaleData memory data) {
    _data = data;
    _data.presale_address = address(this);
  }
  // General Setter Functions
  function updateSocials(string[] memory presale_strings) public onlyOwner returns(string[] memory) {
    return _data.strings = presale_strings;
  }
  // General Getter Functions
  function getPresaleData() external view returns(PSL.PresaleData memory) {
    return _data;
  }
  function getPresaleDetails() external view returns(
    address,
    string memory,
    address,
    bool,
    bool,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256,
    uint256[] memory,
    address[] memory) {
      return (
        address(this),
        getPresaleStatus(),
        _pair_address,
        _whitelist_enabled,
        _microvaults_enabled,
        _microvaults_unlock_date,
        _microvaults_vests_count,
        address(this).balance,
        _archived_bnb_amount,
        IBEP20(_data.addresses.token).balanceOf(address(this)),
        _badges,
        _whitelist_address_list
      );
  }
  function getPresaleStatus() public view returns(string memory) {
    if(_presale_cancelled)
      return "CANCELLED";
    else if(_presale_finalized)
      return "FINALIZED";
    else if(_hasPresaleFailed())
      return "FAILED";
    else if(block.timestamp < _data.integers.start_date)
      return "NOT_STARTED";
    else if(_hasPresaleEnded())
      return "ENDED";
    else
      return "ACTIVE";
  }
  // Presale Fate Control Functions
  function cancelPresale() external onlyOwner presaleValid {
    emit CancelPresale();
    _presale_cancelled = true;
  }
  function finalizePresale() external onlyOwner presaleValid {
    IBEP20 token = IBEP20(_data.addresses.token);
    require((address(this).balance >= _data.rates.softcap), "PS-ERR-1021"); // PS: Softcap not reached or Token Pair not generated
    require((token.balanceOf(address(this)) >= _data.integers.total), "PS-ERR-1021B");
    _presale_finalized = true;
    _archived_bnb_amount = address(this).balance;
    (uint256 exchange_coins, uint256 exchange_tokens) = PSL.calculateLiquidityAmounts(
      _archived_bnb_amount,
      _data.rates.exchange_percentage,
      _data.rates.exchange_rate,
      _data.token_decimals
    );
    uint256 remaining_coins = _archived_bnb_amount - exchange_coins;
    uint256 fee_coins = PSL.multiDiv(remaining_coins, _data.rates.coin_fee_percentage, 1000);
    // Approve transfer of tokens from presale to exchange
    token.approve(_data.addresses.exchange, exchange_tokens);
    ISwapXRouter02 router = ISwapXRouter02(_data.addresses.exchange);
    (uint256 amountToken, uint256 amountETH, ) = router.addLiquidityETH{value: exchange_coins}(
      address(token),
      exchange_tokens,
      0,
      0,
      address(this),
      block.timestamp
    );
    require(
      (amountToken == exchange_tokens) &&
      (amountETH == exchange_coins),
      "PS-ERR-1203"
    ); // Adding expected liquidity failed, token pair may already exist
    // Fetch the pair address from the router factory
    _pair_address = ISwapXFactory(router.factory()).getPair(address(token), address(router.WETH()));
    // Collect token fees
    PSL.transferBEP20(_data.addresses.token, _data.addresses.vault, _data.integers.fee);
    // Collect coin fees
    PSL.transferCall(_data.addresses.vault, fee_coins);
    // Transfer coins (Coins for owner = Coin total after exchange) to owner
    PSL.transferCall(_data.addresses.owner, (remaining_coins - fee_coins));
    _remaining_tokens = token.balanceOf(address(this)) - PSL.tokenizeDecimals(_archived_bnb_amount, _data.token_decimals) * _data.rates.presale_rate;
    emit FinalizedPresale();
  }
  // Whitelist Feature Functions
  function toggleWhitelist(bool status) external onlyOwner presalePending {
    _whitelist_enabled = status;
  }
  function getPresaleContributors() external view returns(address[] memory) {
    return _contributors;
  }
  function addWhitelistUsers(address[] memory users) external onlyOwner presaleRunning {
    for(uint i = 0; i < users.length; i++) {
      if(_whitelist_addresses[users[i]] == false) {
        _whitelist_address_list.push(users[i]);
      }
      _whitelist_addresses[users[i]] = true;
    }
  }
  function removeWhitelistUser(address user, uint256 index) external onlyOwner presaleRunning {
    require(_whitelist_addresses[user] == true, "PS-ERR-1002B"); // already exists in whitelist
    _whitelist_addresses[user] = false;
    _whitelist_address_list[index] = _whitelist_address_list[_whitelist_address_list.length - 1];
    delete _whitelist_address_list[_whitelist_address_list.length - 1];
  }
  function addBadge(uint256 badge) external onlyAdmin {
    _badges.push(badge);
  }
  function removeBadge(uint256 index) external onlyAdmin {
    _badges[index] = _badges[_badges.length - 1];
    delete _badges[_badges.length - 1];
  }
  // Microvault Feature Functions
  function configureMicrovault(bool status, uint256 unlock_date, uint256 vests) external onlyOwner presalePending {
    require((
      (unlock_date > _data.integers.end_date) &&
      (vests > 0)), "PS-ERR-1017"
    );
    _microvaults_enabled = status;
    _microvaults_unlock_date = unlock_date;
    _microvaults_vests_count = vests;
  }
  // The main payable function that allows contributing Coins to the presale
  function contributeToPresale() external payable {
    require(wasPresaleRunning(address(this).balance - msg.value), "PS: Not running.");
    if(_whitelist_enabled) require(_whitelist_addresses[msg.sender], "PS: Not Whitelisted");
    require(PSL.checkTimeStarted(block.timestamp, _data.integers.start_date, _data.integers.end_date),
      "PS: Not active."
    );
    if(_user_contributions[msg.sender] == 0) {
      _contributors.push(msg.sender);
    }
    require(address(this).balance <= _data.rates.hardcap, "PS-ERR-1003"); // contribution overflows hardcap
    uint256 new_contrib = _user_contributions[msg.sender] + msg.value;
    require((
        (new_contrib >= _data.rates.min_contrib) &&  // PS: value lower than min contribution.
        (new_contrib <= _data.rates.max_contrib) // PS: value higher than max contribution.
      ), "PS-ERR-1004");
    _user_contributions[msg.sender] = new_contrib;
    emit ContributedToPresale();
  }
  // The withdraw methods that let users take out their Coins contribution or earned tokens
  function withdrawPresaleTokens() external hasContribution {
    require(
      (_presale_finalized == true) &&
      (_microvaults_enabled == false),
      "PS-ERR-1014"
    ); // Presale finalized and microvaults not be enabled
    require((_user_withdrawals[msg.sender][0] == false), "PS-ERR-1015");
    _user_withdrawals[msg.sender][0] = true;
    // Tokens owed to Contributor = User Coin Contribution * Exchange Rate
    uint256 tokenized_contibution = PSL.tokenizeDecimals(_user_contributions[msg.sender], _data.token_decimals);
    uint256 presaleTokens = tokenized_contibution * _data.rates.presale_rate;   
    PSL.transferBEP20(_data.addresses.token, msg.sender, presaleTokens);
  }
  function withdrawPresaleTokensFromMicrovault(uint256 vest) external hasContribution {
    require(
      (_presale_finalized == true) &&
      (_microvaults_enabled == true) && 
      (vest < _microvaults_vests_count),
      "PS-ERR-1014"
    );
    require((_user_withdrawals[msg.sender][vest] == false), "PS-ERR-1015");
    require((
      block.timestamp > PSL.getVestUnlockDate(
      _microvaults_unlock_date,
      _data.integers.end_date,
      _microvaults_vests_count,
      vest)
      ), "PS-ERR-1016"); // Microvaults: Too soon to release this vest
    // Tokens owed to Contributor = User Coin Contribution * Exchange Rate / vests
    uint256 tokenized_contibution = PSL.tokenizeDecimals(_user_contributions[msg.sender], _data.token_decimals);
    uint256 presaleTokens = PSL.multiDiv(tokenized_contibution, _data.rates.presale_rate, _microvaults_vests_count);
    _user_withdrawals[msg.sender][vest] = true;
    PSL.transferBEP20(_data.addresses.token, msg.sender, presaleTokens);
  }
  function withdrawContribution() external presaleRunning {
    _withdrawContribution();
  }
  function withdrawRefund() external {
    require(_presale_cancelled || _hasPresaleFailed(), "PS: Not failed/cancelled");    
    _withdrawContribution();
  }
  function withdrawOwnerLPTokens() external onlyOwner {
    require(block.timestamp > _data.integers.liquidity_unlock, "PS-ERR-1040"); // unlock date hasn't arrived yet
    PSL.transferBEP20(_pair_address, _data.addresses.owner, IBEP20(_pair_address).balanceOf(address(this)));
  }
  function withdrawRemainingTokens(address target) external onlyOwner { 
    require(_remaining_tokens_withdrawn == false, "PS-ERR-1041");
    if(_presale_finalized) {
      PSL.transferBEP20(_data.addresses.token, target, _remaining_tokens);
      _remaining_tokens_withdrawn = true;
    } else if (_presale_cancelled || _hasPresaleFailed()) {
      PSL.transferBEP20(_data.addresses.token, target, IBEP20(_data.addresses.token).balanceOf(address(this)));
      _remaining_tokens_withdrawn = true;
    }
  }
  // Internal Functions
  function _withdrawContribution() internal hasContribution returns(uint256) {
    address payable user = payable(msg.sender); 
    uint256 contrib = _user_contributions[user];
    _user_contributions[user] = 0;
    PSL.transferCall(user, contrib);
    return contrib;
  }
  function wasPresaleRunning(uint256 oldBalance) internal view returns(bool) {
    bool failed = PSL.checkFailed(oldBalance, _data.rates.softcap, block.timestamp, _data.integers.end_date);
    bool ended = PSL.checkEnded(oldBalance, _data.rates.hardcap, block.timestamp, _data.integers.end_date);
    return PSL.checkRunning(_presale_cancelled, _presale_finalized, failed, ended);
  }
  function _hasPresaleFailed() internal view returns(bool) {
    return PSL.checkFailed(address(this).balance, _data.rates.softcap, block.timestamp, _data.integers.end_date);
  }
  function _hasPresaleEnded() internal view returns(bool) {
    return PSL.checkEnded(address(this).balance, _data.rates.hardcap, block.timestamp, _data.integers.end_date);
  }
}

// File: contracts\PresaleV1Factory.sol
contract PresaleV1Factory {
  PresaleV1[] public _presale_addresses;
  mapping(address => PresaleV1[]) public _presale_addresses_by_beneficiary;
  mapping(address => PresaleV1[]) public _presale_addresses_by_token;
  mapping(uint256 => PresaleV1) public _presale_addresses_by_id;
  address public _owner;
  address payable public _vault;
  address[] private _exchange_addresses;
  uint256 public _id_counter = 0;
  uint256 public _creation_fee = 0.1 * (10 ** 18);
  uint256 public _cap_minimum_percentage = 50; // out of 100 for regular precision 
  uint256 public _max_presale_length = 604800; // One week
  uint256 public _token_fee_percentage = 25; // out of 1000 to get higher percision 
  uint256 public _coin_fee_percentage = 25; // out of 1000 to get higher percision 
  uint256 public _emergency_tokens_percentage = 20; // out of 1000 to get higher percision 
  bool public _factory_paused = false;
  event CreatedPresale(address presale);
  modifier onlyOwner() {
      require(msg.sender == _owner, "PSF: Not Owner");
      _;
  }
  constructor(address payable vault, address[] memory exchange_addresses) {
    _vault = vault;
    _exchange_addresses = exchange_addresses;
    _owner = msg.sender;
  }
  // General getter functions
  function transferOwnership(address new_owner) external onlyOwner {
    _owner = new_owner;
  }
  function getPresales(uint256 page, uint256 count) external view returns(PSL.PresaleData[] memory) {
    return _getPresales(_presale_addresses, page, count);
  }
  function getFilteredPresales(uint256 page, uint256 count, string memory presaleType) external view returns(PSL.PresaleData[] memory) {
    PresaleV1[] memory result = new PresaleV1[](_presale_addresses.length);
    for(uint256 i = 0; i < _presale_addresses.length; i++) {
      if(keccak256(bytes(_presale_addresses[i].getPresaleStatus())) == keccak256(bytes(presaleType)))
        result[i] = _presale_addresses[i];
    }
    return _getPresales(result, page, count);
  }
  function getPresalesByAddress(uint256 page, uint256 count, address add) external view returns(PSL.PresaleData[] memory) {
    return _getPresales(_presale_addresses_by_beneficiary[add], page, count);
  }
  function _getPresales(PresaleV1[] memory addresses, uint256 page, uint256 count) internal view returns(PSL.PresaleData[] memory dataPage) {
    dataPage = new PSL.PresaleData[](count);
    // DEC
    uint256 itemsAdded = 0;
    uint256 skip = PSL.subtract(addresses.length, (page * count));
    uint256 stop_at = PSL.subtract(skip, count);
    for(uint i = skip; i > stop_at; i--) {
      if(address(addresses[(i-1)]) != PSL.zeroAddress) {
        dataPage[itemsAdded] = addresses[(i-1)].getPresaleData();
        ++itemsAdded;
      }
    }
  }
  // General setter functions
  function togglePause(bool status) external onlyOwner {
    _factory_paused = status;
  }
  function setFactoryConfig(
    address owner,
    address payable vault,
    address[] memory exchange_addresses,
    uint256 new_minimum_percentage,
    uint256 max_presale_length,
    uint256 creation_fee,
    uint256 token_fee_percentage,
    uint256 coin_fee_percentage,
    uint256 new_emergency_tokens_percentage) external onlyOwner {
    _owner = owner;
    _vault = vault;
    _exchange_addresses = exchange_addresses;
    _cap_minimum_percentage = new_minimum_percentage;
    _max_presale_length = max_presale_length;
    _creation_fee = creation_fee;
    _token_fee_percentage = token_fee_percentage;
    _coin_fee_percentage = coin_fee_percentage;
    _emergency_tokens_percentage = new_emergency_tokens_percentage;
  }  
  // Core functionality
  function withdrawFees() external onlyOwner {
    // Get the current contract balance and transfer the funds to the vault address.
    uint256 amount = address(this).balance;
    (bool success,) = _vault.call{value: amount}(""); 
    require(success, "PSF-ERR-1001"); // Withdraw Failed
  }
  function getExchanges() external view returns(address[] memory) {
    return _exchange_addresses;
  }
  function createPresale(PSL.PresaleData memory data, uint256 selected_exchange) external payable returns(PresaleV1 presale) {    
    IBEP20 token = IBEP20(data.addresses.token);
    if(msg.sender != _owner) {
      require(!_factory_paused, "PSF-PAUSED");
      // Time validation
      require(PSL.validateDates(
        data.integers.start_date, 
        data.integers.end_date, 
        data.integers.liquidity_unlock,
        block.timestamp,
        _max_presale_length), "PSF-ERR-1050"); // Dates are invalid
      // Cap Validation
      require(
        data.rates.softcap > PSL.multiDiv(data.rates.hardcap, _cap_minimum_percentage, 100), 
        "PSF-ERR-1054"
      ); // softcap must be higher than minimum
      // Funds validation
      require(msg.value >= _creation_fee, "PSF-ERR-1057"); // Not enough funds for presale fees
    }
    // Contribution Validation
    require(
      (data.rates.softcap < data.rates.hardcap) &&
      (data.rates.min_contrib < data.rates.max_contrib),
      "PSF-ERR-1056"
    ); // Softcap must be lower than hardcap min contribution must be less than max
    require(token.balanceOf(msg.sender) >= data.integers.total, "PSF-ERR-1058"); // not enough tokens to cover presale
    // Calculate the token amounts that are generated dynamically
    (data.integers.presale, data.integers.liquidity, data.integers.fee, data.integers.emergency, data.integers.total)
      = PSL.calculateTokenAmounts(
        data.rates.hardcap,
        data.rates.presale_rate,
        data.rates.exchange_rate,
        data.rates.exchange_percentage,
        _emergency_tokens_percentage,
        _token_fee_percentage,
        token.decimals());  
    // Get Other Presale Values
    data.id = ++_id_counter;
    data.token_name = token.name();
    data.token_symbol = token.symbol();
    data.token_decimals = token.decimals();
    data.addresses.exchange = _exchange_addresses[selected_exchange];
    data.addresses.owner = payable(msg.sender);
    data.addresses.vault = _vault;
    data.addresses.factory = address(this);
    data.rates.coin_fee_percentage = _coin_fee_percentage;
    // New presale contract generated using parameters and pushed into memory
    presale = new PresaleV1(data);
    // Store the presale in the array, and each of the mappings.
    _presale_addresses.push(presale);
    _presale_addresses_by_beneficiary[msg.sender].push(presale);
    _presale_addresses_by_token[data.addresses.token].push(presale);
    _presale_addresses_by_id[data.id] = presale;
    emit CreatedPresale(address(presale));
  }
}