//SPDX-License-Identifier: No License
pragma solidity ^0.8.0;
 
/**
 * SAFEMATH LIBRARY
 */
library SafeMath {
 
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }
 
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }
 
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }
 
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }
 
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }
 
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }
 
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }
 
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }
 
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }
 
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }
 
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }
 
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }
 
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}
 
interface IBEP20 {
    function totalSupply() external view returns (uint256);
    function decimals() external view returns (uint8);
    function symbol() external view returns (string memory);
    function name() external view returns (string memory);
    function getOwner() external view returns (address);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function allowance(address _owner, address spender) external view returns (uint256);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);
}
 
abstract contract Auth {
    address internal owner;
    mapping (address => bool) internal authorizations;
 
    constructor(address _owner) {
        owner = _owner;
        authorizations[_owner] = true;
    }
 
    /**
     * Function modifier to require caller to be contract owner
     */
    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }
 
    /**
     * Function modifier to require caller to be authorized
     */
    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }
 
    /**
     * Authorize address. Owner only
     */
    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }
 
    /**
     * Remove address' authorization. Owner only
     */
    function unauthorize(address adr) public onlyOwner {
        authorizations[adr] = false;
    }
 
    /**
     * Check if address is owner
     */
    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }
 
    /**
     * Return address' authorization status
     */
    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }
 
    /**
     * Transfer ownership to new address. Caller must be owner. Leaves old owner authorized
     */
    function transferOwnership(address payable adr) public onlyOwner {
        owner = adr;
        authorizations[adr] = true;
        emit OwnershipTransferred(adr);
    }
 
    event OwnershipTransferred(address owner);
}
 
interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}
 
interface IDEXRouter {
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
 
/** @dev this token is a liquidity generator token, with taxes going towards the liquidity pool, a developer wallet, a marketing wallet and a team wallet. 
 
The taxes are set individually for both buy and sell. They are accumulated in the contract before being converted to BNB and distributed.
The buy and sell storage amounts are kept separately in the storedBuyFees and storedSellFees counters, to be converted when the threshold is hit
in the correct ratios.
 
There are no taxes on wallet to wallet transactions.
*/ 
 
contract TokifyLiquidityGenerator is IBEP20, Auth {
    using SafeMath for uint256;
 
    uint256 public constant MASK = type(uint128).max;
    address public WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
    address DEAD_NON_CHECKSUM = 0x000000000000000000000000000000000000dEaD;
 
    string constant _name = "Tokify Liquidity Generator";
    string constant _symbol = "TLG";
    uint8 constant _decimals = 9;
 
    uint256 private _totalSupply = 1000000000000000;
    uint256 public _maxTxAmount = _totalSupply.div(400); // 0.25%
 
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
 
    /// @dev mappings to keep track of blacklisted and exempt wallets
    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isExcludedFromPause;
    mapping (address => bool) antiBotBlackList;
 
    /// @dev taxes are different for both buy and sell
    uint256 buyLiquidityFee = 200;
    uint256 buyMarketingFee = 200;
    uint256 buyDeveloperFee = 400;
    uint256 buyTeamFee = 200;
    uint256 totalBuyFee = buyLiquidityFee.add(buyMarketingFee).add(buyDeveloperFee).add(buyTeamFee);
 
    uint256 sellLiquidityFee = 400;
    uint256 sellMarketingFee = 400;
    uint256 sellDeveloperFee = 500;
    uint256 sellTeamFee = 200;
    uint256 totalSellFee = sellLiquidityFee.add(sellMarketingFee).add(sellDeveloperFee).add(sellTeamFee);
 
    /// @dev the counters of stored fees allow the buy and sell conversions to BNB to be called individually to make sure they are distributed in the correct ratios.
    uint256 public storedBuyFees;
    uint256 public storedSellFees;
 
    uint256 feeDenominator = 10000;
 
    address public autoLiquidityReceiver;
    address public marketingFeeReceiver;
    address public developerFeeReceiver;
    address public teamFeeReceiver;
    address generatorFeeReceiver = 0xF6bF36933149030ed4B212F0a79872306690e48e;
    uint256 generatorFee = 500;
 
    uint256 targetLiquidity = 25;
    uint256 targetLiquidityDenominator = 100;
 
    IDEXRouter public router;
    address public pair;
 
    /// @dev bools to allow pausing of transactions and pausing of fees
    bool public isPaused = false;
    bool public takeFeeActive = true;
 
    bool public swapEnabled = true;
    uint256 public swapThreshold = _totalSupply / 4000; // 0.025%
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }
 
    constructor (
        address _dexRouter,
        address _marketingFeeReceiver,
        address _developerFeeReceiver,
        address _teamFeeReceiver
    ) Auth(msg.sender) {
        router = IDEXRouter(_dexRouter);
        pair = IDEXFactory(router.factory()).createPair(WBNB, address(this));
        _allowances[address(this)][address(router)] = _totalSupply;
        WBNB = router.WETH();
 
        isFeeExempt[msg.sender] = true;
        isTxLimitExempt[msg.sender] = true;
        isExcludedFromPause[msg.sender] = true;
 
        autoLiquidityReceiver = msg.sender;
        marketingFeeReceiver = _marketingFeeReceiver;
        developerFeeReceiver = _developerFeeReceiver;
        teamFeeReceiver = _teamFeeReceiver;
 
        approve(_dexRouter, _totalSupply);
        approve(address(pair), _totalSupply);
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);
    }
 
    receive() external payable { }
 
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
 
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
 
    function approveMax(address spender) external returns (bool) {
        return approve(spender, _totalSupply);
    }
 
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }
 
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != _totalSupply){
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }
 
        return _transferFrom(sender, recipient, amount);
    }
 
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        /// @dev if the token is currently being swapped by the contract into BNB, then no taxes apply
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }
        /// @dev if the contract is currently paused, then the transaction is reverted
        if(isPaused){
          require(isExcludedFromPause[sender] == true || isExcludedFromPause[recipient] == true,"WARNING: contract is in pause for maintenance");
        }
        /// @dev if either the sender or recipient are on the blacklist, then revert the transaction
        require(antiBotBlackList[sender] == false && antiBotBlackList[recipient] == false, "WARNING: sending or recipient address is in blacklist, contact the team");
        /// @dev check that size of transaction is not over the transaction limit
        checkTxLimit(sender, amount);
        /// @dev check if enough tokens have been accumulated in either buy or sell taxes to swap back. Do not call both in the same transaction
        if(shouldSwapBackSelling()){ swapBackSell(); }
        else if(shouldSwapBackBuying()){ swapBackBuy(); }
 
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
 
        /// @dev calculate taxes needed to be taken, if any
        uint256 amountReceived = shouldTakeFee(sender, recipient) ? takeFee(sender, recipient, amount) : amount;
 
        _balances[recipient] = _balances[recipient].add(amountReceived);
 
        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
 
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount, "Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        return true;
    }
 
    function checkTxLimit(address sender, uint256 amount) internal view {
        require(amount <= _maxTxAmount || isTxLimitExempt[sender], "TX Limit Exceeded");
    }
 
    /// @dev check if fee is active, then check that it is either a buy or sell transaction, then check if the sender is exempt from fee
    function shouldTakeFee(address sender, address recipient) internal view returns (bool) {
        if (takeFeeActive == false) {
            return false;
        }
        if (sender != pair && recipient != pair) {
            return false;
        }
        return !isFeeExempt[sender];
    }
 
    /// @dev calculae the total fee to be taken on the transaction. Different for buying and selling
    function getTotalFee(bool selling, bool buying) public view returns (uint256) {
        if(selling){ return totalSellFee; }
        if(buying){ return totalBuyFee; }
        return 0;
    }
 
    /// @dev figure out the amount transferred when taxes are deducted and add the taxes to this contract and to the counters
    function takeFee(address sender, address receiver, uint256 amount) internal returns (uint256) {
        bool selling = receiver == pair;
        bool buying = sender == pair;
        uint256 feeAmount = amount.mul(getTotalFee(selling, buying)).div(feeDenominator);
 
        if(selling){
            storedSellFees = storedSellFees.add(feeAmount);
        } else if (buying){
            storedBuyFees = storedBuyFees.add(feeAmount);
        }
 
        _balances[address(this)] = _balances[address(this)].add(feeAmount);
 
        emit Transfer(sender, address(this), feeAmount);
 
        return amount.sub(feeAmount);
    }
 
    function shouldSwapBackSelling() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && storedSellFees >= swapThreshold;
    }
 
    /// @dev function to swap the token accumulated in the contract through sell taxes into BNB
    /// @dev the BNB is then accordingly distributed to the receivers
    /// @dev the counter for stored sell taxes is also adjusted
    function swapBackSell() internal swapping {
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : sellLiquidityFee;
        uint256 amountToLiquify = swapThreshold.mul(dynamicLiquidityFee).div(totalSellFee).div(2);
        uint256 amountToSwap = swapThreshold.sub(amountToLiquify);
 
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        uint256 balanceBefore = address(this).balance;
        uint256 tokenBalanceBeforeExchange = balanceOf(address(this));
 
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
 
        storedSellFees = storedSellFees.add(balanceOf(address(this))).sub(tokenBalanceBeforeExchange);
        uint256 amountBNB = address(this).balance.sub(balanceBefore);
 
        uint256 totalBNBFee = totalSellFee.sub(dynamicLiquidityFee.div(2));
 
        uint256 amountBNBLiquidity = amountBNB.mul(dynamicLiquidityFee).div(totalBNBFee).div(2);
        uint256 amountBNBMarketing = amountBNB.mul(sellMarketingFee).div(totalBNBFee);
        uint256 amountBNBDeveloper = amountBNB.mul(sellDeveloperFee).div(totalBNBFee);
        uint256 amountBNBTeam = amountBNB.mul(sellTeamFee).div(totalBNBFee);
 
        sendCreatorWalletAmounts(amountBNBMarketing, amountBNBDeveloper, amountBNBTeam);
 
        if(amountToLiquify > 0){
            uint256 tokenBalanceBeforeLiquify = balanceOf(address(this));
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            storedSellFees = storedSellFees.add(balanceOf(address(this))).sub(tokenBalanceBeforeLiquify);
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }
 
    function shouldSwapBackBuying() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && storedBuyFees >= swapThreshold;
    }
 
    /// @dev function to swap the token accumulated in the contract through buy taxes into BNB
    /// @dev the BNB is then accordingly distributed to the receivers
    /// @dev the counter for stored buy taxes is also adjusted
    function swapBackBuy() internal swapping {
        uint256 dynamicLiquidityFee = isOverLiquified(targetLiquidity, targetLiquidityDenominator) ? 0 : buyLiquidityFee;
        uint256 amountToLiquify = swapThreshold.mul(dynamicLiquidityFee).div(totalBuyFee).div(2);
        uint256 amountToSwap = swapThreshold.sub(amountToLiquify);
 
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;
        uint256 balanceBefore = address(this).balance;
        uint256 tokenBalanceBeforeExchange = balanceOf(address(this));
 
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
        storedBuyFees = storedBuyFees.add(balanceOf(address(this))).sub(tokenBalanceBeforeExchange);
        uint256 amountBNB = address(this).balance.sub(balanceBefore);
 
        uint256 totalBNBFee = totalBuyFee.sub(dynamicLiquidityFee.div(2));
 
        uint256 amountBNBLiquidity = amountBNB.mul(dynamicLiquidityFee).div(totalBNBFee).div(2);
        uint256 amountBNBMarketing = amountBNB.mul(buyMarketingFee).div(totalBNBFee);
        uint256 amountBNBDeveloper = amountBNB.mul(buyDeveloperFee).div(totalBNBFee);
        uint256 amountBNBTeam = amountBNB.mul(buyTeamFee).div(totalBNBFee);
 
        sendCreatorWalletAmounts(amountBNBMarketing, amountBNBDeveloper, amountBNBTeam);
 
        if(amountToLiquify > 0){
            uint256 tokenBalanceBeforeLiquify = balanceOf(address(this));
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            storedBuyFees = storedBuyFees.add(balanceOf(address(this))).sub(tokenBalanceBeforeLiquify);
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }
 
    function sendCreatorWalletAmounts(uint256 amountBNBMarketing, uint256 amountBNBDeveloper, uint256 amountBNBTeam) internal {
        /// @dev tax on the marketing wallet going towards the contract generator platform
        uint256 generatorMarketingAmount = amountBNBMarketing.mul(generatorFee).div(feeDenominator);
        uint256 marketingAmount = amountBNBMarketing.sub(generatorMarketingAmount);
 
        /// @dev tax on the marketing wallet going towards the contract generator platform
        uint256 generatorDeveloperAmount = amountBNBDeveloper.mul(generatorFee).div(feeDenominator);
        uint256 developerAmount = amountBNBDeveloper.sub(generatorDeveloperAmount);
 
        uint256 generatorAmount = generatorMarketingAmount.add(generatorDeveloperAmount);
 
        payable(marketingFeeReceiver).transfer(marketingAmount);
        payable(developerFeeReceiver).transfer(developerAmount);
        /// @dev team wallet does not pay the generator tax to Tokify
        payable(teamFeeReceiver).transfer(amountBNBTeam);
        payable(generatorFeeReceiver).transfer(generatorAmount);
    }
 
    /// @dev set the transaction limit
    function setTxLimit(uint256 amount) external authorized {
        require(amount >= _totalSupply / 1000);
        _maxTxAmount = amount;
    }
 
    /// @dev set whether an address is exempt from the fee
    function setIsFeeExempt(address holder, bool exempt) external authorized {
        isFeeExempt[holder] = exempt;
    }
 
    /// @dev set whether an address is exempt from the maximum transaction limit
    function setIsTxLimitExempt(address holder, bool exempt) external authorized {
        isTxLimitExempt[holder] = exempt;
    }
 
    /// @dev set the sell fees
    function setSellFees(uint256 _liquidityFee, uint256 _marketingFee, uint256 _developerFee, uint256 _teamFee, uint256 _feeDenominator) external authorized {
        sellLiquidityFee = _liquidityFee;
        sellMarketingFee = _marketingFee;
        sellDeveloperFee = _developerFee;
        sellTeamFee = _teamFee;
        totalSellFee = _liquidityFee.add(_marketingFee).add(_developerFee).add(_teamFee);
        feeDenominator = _feeDenominator;
        require(totalSellFee < feeDenominator/4);
    }
 
    /// @dev set the buy fees
    function setBuyFees(uint256 _liquidityFee, uint256 _marketingFee, uint256 _developerFee, uint256 _teamFee, uint256 _feeDenominator) external authorized {
        buyLiquidityFee = _liquidityFee;
        buyMarketingFee = _marketingFee;
        buyDeveloperFee = _developerFee;
        buyTeamFee = _teamFee;
        totalBuyFee = _liquidityFee.add(_marketingFee).add(_developerFee).add(_teamFee);
        feeDenominator = _feeDenominator;
        require(totalBuyFee < feeDenominator/4);
    }
 
    /// @dev set the addresses that benefit from the fees
    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver, address _developerFeeReceiver, address _teamFeeReceiver) external authorized {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
        developerFeeReceiver = _developerFeeReceiver;
        teamFeeReceiver = _teamFeeReceiver;
    }
 
    /// @dev set whether the contract can swap back its accumulated token into BNB and set the threshold for this
    function setSwapBackSettings(bool _enabled, uint256 _amount) external authorized {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }
 
    /// @dev set the maximum amount of liquidity up to which taxes keep being sent to the pool
    function setTargetLiquidity(uint256 _target, uint256 _denominator) external authorized {
        targetLiquidity = _target;
        targetLiquidityDenominator = _denominator;
    }
 
    /// @dev enable or disable the fee
    function setFeeActive(bool setTakeFeeActive) external authorized {
        takeFeeActive = setTakeFeeActive;
    }
 
    /// @dev get the token supply not stored in the burn wallets
    function getCirculatingSupply() public view returns (uint256) {
        return _totalSupply.sub(balanceOf(DEAD)).sub(balanceOf(ZERO));
    }
 
    /// @dev get how much of the token is in the liquidity pool
    function getLiquidityBacking(uint256 accuracy) public view returns (uint256) {
        return accuracy.mul(balanceOf(pair).mul(2)).div(getCirculatingSupply());
    }
 
    /// @dev check whether too much of the token is in the liquidity pool
    function isOverLiquified(uint256 target, uint256 accuracy) public view returns (bool) {
        return getLiquidityBacking(accuracy) > target;
    }
 
    /// @dev allow contract to be paused for maintenance
    function setPause(bool enabled) external onlyOwner {
      isPaused = enabled;
    }
 
    /// @dev check whether contract is paused for maintenance
    function getPause() public view returns(bool){
      return isPaused;
    }
 
    /// @dev exclude specific wallets from the pause
    function excludeFromPause(address account) public authorized {
        isExcludedFromPause[account] = true;
    }
 
    /// @dev include and address in the pause
    function includeInPause(address account) public authorized {
        require(isOwner(account) == false, "ERR: owner can't be included");
        isExcludedFromPause[account] = false;
    }
 
    /// @dev exclude a wallet from the blacklist
    function excludeFromAntiBot(address account) public authorized {
        antiBotBlackList[account] = false;
    }
 
    /// @dev include a wallet in the blacklist
    function includeInAntiBot(address account) public authorized {
        require(isOwner(account) == false, "ERR: owner can't be included");
        antiBotBlackList[account] = true;
    }
 
    /// @dev mint additional tokens - only used in special circumstances
    function mint(uint256 amount) public onlyOwner returns (bool) {
        _mint(msg.sender, amount);
        return true;
    }
 
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "BEP20: mint to the zero address");
 
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }
 
    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
}