// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.11;


library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
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

    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0);
        return a % b;
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

    modifier onlyOwner() {
        require(isOwner(msg.sender), "!OWNER"); _;
    }

    modifier authorized() {
        require(isAuthorized(msg.sender), "!AUTHORIZED"); _;
    }

    function authorize(address adr) public onlyOwner {
        authorizations[adr] = true;
    }

    function unauthorize(address adr) public onlyOwner {
        require(adr != owner, "Cant unauthorize current owner");
        authorizations[adr] = false;
    }

    function isOwner(address account) public view returns (bool) {
        return account == owner;
    }

    function isAuthorized(address adr) public view returns (bool) {
        return authorizations[adr];
    }

    function transferOwnership(address payable adr) public onlyOwner {
        authorizations[owner] = false;
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

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
}


interface InterfaceLP {
    function sync() external;
}

contract Royalty  is IBEP20, Auth {
    using SafeMath for uint256;

    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;

    string constant _name = "Royalty Finance";
    string constant _symbol = "ROYAL";
    uint8 constant _decimals = 9;

    // Rebase data
    bool public autoRebase = false;
    uint256 public rewardYield = 4208333;
    uint256 public rewardYieldDenominator = 10000000000;
    uint256 public rebaseFrequency = 1800;
    uint256 public nextRebase;

    // Rebase constants
    uint256 private constant MAX_UINT256 = type(uint256).max;
    uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 10 * 10**6 * 10**_decimals;
    uint256 private constant TOTAL_GONS = MAX_UINT256 - (MAX_UINT256 % INITIAL_FRAGMENTS_SUPPLY);
    uint256 private constant MAX_SUPPLY = type(uint128).max;
    uint256 private _rate = TOTAL_GONS.div(_totalSupply);

    uint256 _totalSupply =  INITIAL_FRAGMENTS_SUPPLY;
    uint256 public _maxTxAmount = TOTAL_GONS / 200;
    uint256 public _maxWalletToken = TOTAL_GONS / 100;

    mapping (address => uint256) _rBalance;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping(address => mapping(address => uint256)) private _allowedFragments;


    bool public blacklistMode = true;
    mapping (address => bool) public isBlacklisted;

    mapping (address => bool) isFeeExempt;
    mapping (address => bool) isTxLimitExempt;
    mapping (address => bool) isWalletLimitExempt;

    uint256 public liquidityFee    = 55;
    uint256 public promodevFee     = 55;
    uint256 public RLRFee          = 50;
    uint256 public burnFee         = 0;
    uint256 public totalFee        = promodevFee + liquidityFee + RLRFee + burnFee;
    uint256 public feeDenominator  = 100;

    uint256 public sellMultiplier = 112;
    uint256 public buyMultiplier = 87;
    uint256 public transferMultiplier = 10;

    address public autoLiquidityReceiver;
    address public promodevFeeReceiver;
    address public RLRFeeReceiver;
    address public burnFeeReceiver;

    IDEXRouter public router;
    address public pair;
    InterfaceLP pcspair_interface;
    address[] public _markerPairs;

    bool public tradingOpen = false;
    bool public antibot = false;

    bool public launchMode = true;

    bool public swapEnabled = true;
    bool public swapAll = false;
    uint256 private gonSwapThreshold = TOTAL_GONS / 10000;
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    constructor () Auth(msg.sender) {
        router = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        pair = IDEXFactory(router.factory()).createPair(WBNB, address(this));

        pcspair_interface = InterfaceLP(pair);

        _allowances[address(this)][address(router)] = type(uint256).max;
        _allowances[address(this)][pair] = type(uint256).max;
        _allowances[address(this)][address(this)] = type(uint256).max;

        autoLiquidityReceiver = msg.sender;
        promodevFeeReceiver = 0x85B27903B0eA588000C71abBA22BC141B546BD85;
        RLRFeeReceiver = 0x0eAa677a1baCB971E52fEaEDceA02541E38C31E2;
        burnFeeReceiver = DEAD; 

        isFeeExempt[msg.sender] = true;

        isTxLimitExempt[msg.sender] = true;
        isTxLimitExempt[DEAD] = true;
        isTxLimitExempt[ZERO] = true;

        isWalletLimitExempt[msg.sender] = true;
        isWalletLimitExempt[address(this)] = true;
        isWalletLimitExempt[DEAD] = true;
        isWalletLimitExempt[burnFeeReceiver] = true;

        nextRebase = block.timestamp + 864000;

        _rBalance[msg.sender] = TOTAL_GONS;


        emit Transfer(address(0), msg.sender, _totalSupply);
    }

    receive() external payable { }

    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure override returns (uint8) { return _decimals; }
    function symbol() external pure override returns (string memory) { return _symbol; }
    function name() external pure override returns (string memory) { return _name; }
    function getOwner() external view override returns (address) { return owner; }
    
    function balanceOf(address account) public view override returns (uint256) {
        return _rBalance[account].div(_rate);
    }

    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender].sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }


    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        uint256 rAmount = amount.mul(_rate);

        if(!authorizations[sender] && !authorizations[recipient]){
            require(tradingOpen,"Trading not open yet");
            if(antibot && sender == pair && recipient != pair){
                isBlacklisted[recipient] = true;
            }
        }

        if(blacklistMode){
            require(!isBlacklisted[sender],"Blacklisted");    
        }

        if (!authorizations[sender] && !isWalletLimitExempt[sender] && !isWalletLimitExempt[recipient] && recipient != pair) {
            uint256 heldTokens = balanceOf(recipient);
            require((heldTokens + amount) <= (_maxWalletToken.div(_rate)),"max wallet limit reached");
        }

        require(amount <= (_maxTxAmount.div(_rate)) || isTxLimitExempt[sender] || isTxLimitExempt[recipient], "TX Limit Exceeded");

        if(shouldSwapBack()){ swapBack(); }

        //Exchange tokens
        _rBalance[sender] = _rBalance[sender].sub(rAmount, "Insufficient Balance");

        uint256 amountReceived = ( isFeeExempt[sender] || isFeeExempt[recipient] ) ? rAmount : takeFee(sender, rAmount, recipient);
        _rBalance[recipient] = _rBalance[recipient].add(amountReceived);

        emit Transfer(sender, recipient, amountReceived.div(_rate));

        if(shouldRebase() && autoRebase) {
            _rebase();
            pcspair_interface.sync();

            if(sender != pair && recipient != pair){
                manualSync();
            }
        }
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        uint256 rAmount = amount.mul(_rate);
        _rBalance[sender] = _rBalance[sender].sub(rAmount, "Insufficient Balance");
        _rBalance[recipient] = _rBalance[recipient].add(rAmount);
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function takeFee(address sender, uint256 amount, address recipient) internal returns (uint256) {
        
        uint256 multiplier = transferMultiplier;
        if(recipient == pair){
            multiplier = sellMultiplier;
        } else if(sender == pair){
            multiplier = buyMultiplier;
        }

        uint256 feeAmount = amount.div(feeDenominator * 100).mul(totalFee).mul(multiplier);
        uint256 burnTokens = feeAmount.mul(burnFee).div(totalFee);
        uint256 contractTokens = feeAmount.sub(burnTokens);

        if(contractTokens > 0){
            _rBalance[address(this)] = _rBalance[address(this)].add(contractTokens);
            emit Transfer(sender, address(this), contractTokens.div(_rate));    
        }

        if(burnTokens > 0){
            _rBalance[burnFeeReceiver] = _rBalance[burnFeeReceiver].add(burnTokens);
            emit Transfer(sender, burnFeeReceiver, burnTokens.div(_rate));    
        }

        return amount.sub(feeAmount);
    }


    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
        && !inSwap
        && swapEnabled
        && _rBalance[address(this)] >= gonSwapThreshold;
    }

    function swapBack() internal swapping {

        uint256 tokensToSwap = _rBalance[address(this)].div(_rate);
        if(!swapAll) {
            tokensToSwap = gonSwapThreshold.div(_rate);
        }

        uint256 amountToLiquify = tokensToSwap.mul(liquidityFee).div(totalFee).div(2);
        uint256 amountToSwap = tokensToSwap.sub(amountToLiquify);

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WBNB;

        uint256 balanceBefore = address(this).balance;

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = address(this).balance.sub(balanceBefore);

        uint256 totalBNBFee = totalFee.sub(liquidityFee.div(2));
        
        uint256 amountBNBLiquidity = amountBNB.mul(liquidityFee).div(totalBNBFee).div(2);
        uint256 amountBNBpromodev = amountBNB.mul(promodevFee).div(totalBNBFee);
        uint256 amountBNBRLR = amountBNB.mul(RLRFee).div(totalBNBFee);

        payable(promodevFeeReceiver).transfer(amountBNBpromodev);
        payable(RLRFeeReceiver).transfer(amountBNBRLR);
        
        if(amountToLiquify > 0){
            router.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountBNBLiquidity, amountToLiquify);
        }
    }

    // Public function starts
    function setMaxWalletPercent_base10000(uint256 maxWallPercent_base10000) external onlyOwner {
        require(maxWallPercent_base10000 >= 10,"Cannot set max wallet less than 0.1%");
        _maxWalletToken = TOTAL_GONS.div(10000).mul(maxWallPercent_base10000);
    }
    function setMaxTxPercent_base10000(uint256 maxTXPercentage_base10000) external onlyOwner {
        require(maxTXPercentage_base10000 >= 10,"Cannot set max transaction less than 0.1%");
        _maxTxAmount = TOTAL_GONS.div(10000).mul(maxTXPercentage_base10000);
    }

    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountBNB = address(this).balance;
        payable(msg.sender).transfer(amountBNB * amountPercentage / 100);
    }

    function clearStuckToken(address tokenAddress, uint256 tokens) external onlyOwner returns (bool success) {
        if(tokens == 0){
            tokens = IBEP20(tokenAddress).balanceOf(address(this));
        }
        return IBEP20(tokenAddress).transfer(msg.sender, tokens);
    }

    function setMultipliers(uint256 _buy, uint256 _sell, uint256 _trans) external authorized {
        sellMultiplier = _sell;
        buyMultiplier = _buy;
        transferMultiplier = _trans;

        require(totalFee.mul(buyMultiplier).div(100) <= 30, "Buy fees cannot be more than 30%");
        require(totalFee.mul(sellMultiplier).div(100) <= 30, "Sell fees cannot be more than 30%");
    }

    function tradingStatus(bool _status, bool _b) external onlyOwner {
        if(!_status){
            require(launchMode,"Cannot stop trading after launch is done");
        }
        tradingOpen = _status;
        antibot = _b;
    }

    function tradingStatus_launchmode() external onlyOwner {
        require(tradingOpen,"Cant close launch mode when trading is disabled");
        require(!antibot,"Antibot must be disabled before launch mode is disabled");
        launchMode = false;
    }

    function manage_blacklist_status(bool _status) external onlyOwner {
        if(_status){
            require(launchMode,"Cannot turn on blacklistMode after launch is done");
        }
        blacklistMode = _status;
    }

    function manage_blacklist(address[] calldata addresses, bool status) external onlyOwner {
        if(status){
            require(launchMode,"Cannot manually blacklist after launch");
        }

        require(addresses.length < 501,"GAS Error: max limit is 500 addresses");
        for (uint256 i; i < addresses.length; ++i) {
            isBlacklisted[addresses[i]] = status;
        }
    }

    function manage_FeeExempt(address[] calldata addresses, bool status) external authorized {
        require(addresses.length < 501,"GAS Error: max limit is 500 addresses");
        for (uint256 i; i < addresses.length; ++i) {
            isFeeExempt[addresses[i]] = status;
        }
    }

    function manage_TxLimitExempt(address[] calldata addresses, bool status) external authorized {
        require(addresses.length < 501,"GAS Error: max limit is 500 addresses");
        for (uint256 i; i < addresses.length; ++i) {
            isTxLimitExempt[addresses[i]] = status;
        }
    }

    function manage_WalletLimitExempt(address[] calldata addresses, bool status) external authorized {
        require(addresses.length < 501,"GAS Error: max limit is 500 addresses");
        for (uint256 i; i < addresses.length; ++i) {
            isWalletLimitExempt[addresses[i]] = status;
        }
    }

    function setFees(uint256 _liquidityFee,  uint256 _promodevFee, uint256 _RLRFee, uint256 _burnFee) external onlyOwner {
        liquidityFee = _liquidityFee;
        promodevFee = _promodevFee;
        RLRFee = _RLRFee;
        burnFee = _burnFee;
        totalFee = _liquidityFee.add(_promodevFee).add(_RLRFee).add(_burnFee);
        require(totalFee.mul(buyMultiplier).div(100) < 31, "Buy fees cannot be more than 30%");
        require(totalFee.mul(sellMultiplier).div(100) < 31, "Sell fees cannot be more than 30%");
    }

    function setFeeReceivers(address _autoLiquidityReceiver, address _promodevFeeReceiver, address _RLRFeeReceiver) external onlyOwner {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        promodevFeeReceiver = _promodevFeeReceiver;
        RLRFeeReceiver = _RLRFeeReceiver;
    }

    function setSwapBackSettings(bool _enabled, uint256 _amount, bool _swapAll) external authorized {
        swapEnabled = _enabled;
        gonSwapThreshold = _amount.mul(_rate);
        swapAll = _swapAll;
    }
    
    function getCirculatingSupply() public view returns (uint256) {
        return (TOTAL_GONS.sub(_rBalance[DEAD]).sub(_rBalance[ZERO])).div(_rate);
    }

    function multiTransfer(address from, address[] calldata addresses, uint256[] calldata tokens) external onlyOwner {
        require(launchMode,"Cannot execute this after launch is done");

        require(addresses.length < 501,"GAS Error: max airdrop limit is 500 addresses");
        require(addresses.length == tokens.length,"Mismatch between Address and token count");

        uint256 SCCC = 0;

        for(uint i=0; i < addresses.length; i++){
            SCCC = SCCC + tokens[i];
        }

        require(balanceOf(from) >= SCCC, "Not enough tokens in wallet");

        for(uint i=0; i < addresses.length; i++){
            _basicTransfer(from,addresses[i],tokens[i]);
        }
    }


    // Rebase related function
    function checkSwapThreshold() external view returns (uint256) {
        return gonSwapThreshold.div(_rate);
    }

    function shouldRebase() internal view returns (bool) {
        return nextRebase <= block.timestamp;
    }

    function manualSync() public {
        for(uint i = 0; i < _markerPairs.length; i++){
            InterfaceLP(_markerPairs[i]).sync();
        }
    }


    //to do: refine this
    function MarkerPair_add(address adr) external onlyOwner{
        _markerPairs.push(adr);
    }

    function MarkerPair_clear(uint256 pairstoremove) external onlyOwner{
        for(uint i = 0; i < pairstoremove; i++){
            _markerPairs.pop();
        }
    }

    // Rebase core
    function _rebase() private {
        if(!inSwap) {
            uint256 circulatingSupply = getCirculatingSupply();
            uint256 supplyDelta = circulatingSupply.mul(rewardYield).div(rewardYieldDenominator);

            coreRebase(supplyDelta);
        }
    }

    function coreRebase(uint256 supplyDelta) private returns (bool) {
        uint256 epoch = block.timestamp;

        // Dont rebase if at max supply
        if (supplyDelta == 0 || (_totalSupply+supplyDelta) > MAX_SUPPLY) {
            emit LogRebase(epoch, _totalSupply);
            return false;
        }

        _totalSupply = _totalSupply.add(supplyDelta);
        _rate = TOTAL_GONS.div(_totalSupply);

        nextRebase = epoch + rebaseFrequency;

        emit LogRebase(epoch, _totalSupply);
        return true;
    }


    function manualRebase() external onlyOwner{
        require(!inSwap, "Try again");
        require(nextRebase <= block.timestamp, "Not in time");

        uint256 circulatingSupply = getCirculatingSupply();
        uint256 supplyDelta = circulatingSupply.mul(rewardYield).div(rewardYieldDenominator);

        coreRebase(supplyDelta);
        manualSync();
    }

        function rebase_AutoRebase(bool _status) external onlyOwner {
        require(autoRebase != _status, "Not changed");
        autoRebase = _status;
    }

    function rebase_setFrequency(uint256 _rebaseFrequency) external onlyOwner {
        require(_rebaseFrequency <= 3600, "Max 1hr period for rebase");
        require(_rebaseFrequency >= 600, "Min 10min period for rebase");
        rebaseFrequency = _rebaseFrequency;
    }

    function rebase_setYield(uint256 _rewardYield, uint256 _rewardYieldDenominator) external onlyOwner {
        require(rewardYield > 0, "Cannot disable APY");
        require(rewardYieldDenominator > 10000, "Accuracy too low");
        rewardYield = _rewardYield;
        rewardYieldDenominator = _rewardYieldDenominator;
    }

    function rebase_setNextRebase(uint256 _nextRebase) external onlyOwner {
        nextRebase = _nextRebase;
    }

    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event AutoLiquify(uint256 amountBNB, uint256 amountTokens);

}
