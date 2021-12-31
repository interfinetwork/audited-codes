// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./BEP20.sol";
import "./DividendDistributor.sol";

contract MarioFloki is BEP20 {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    IDEXRouter public constant ROUTER = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address public immutable pair;

    address public marketingWallet = 0x9685842D043E711C0384e11F7E318fcE5E04eF2A;
    address public charityWallet = 0x20f6Ccd6e4F915ED1a4a18d120BaC33742384F9A;

    uint256 public swapThreshold = 100000000 * 10**18;
    bool public swapEnabled = true;
    bool presaleInitialized;
    bool tradingEnabled;
    bool inSwap;

    mapping (address => bool) public isWhitelisted;
    mapping (address => bool) public isDividendExempt;
    mapping (address => bool) public isMarketMaker;
    mapping (address => bool) public isCEX;

    uint256 public buyTax = 1100;
    uint256 public sellTax = 1600;
    uint256 public transferTax = 0;

    uint256 public rewardShare = 500;
    uint256 public charityShare = 50;
    uint256 public liquidityShare = 150;
    uint256 public marketingShare = 300;
    uint256 totalShares = 1000;
    uint256 constant DENOMINATOR = 10000;

    DividendDistributor public immutable distributor;
    uint256 public minBalanceForDividends = 100000000 * 10**18;
    uint256 public transferGas = 25000;

    event PreparePresale(address presale);
    event RecoverBNB(uint256 amount);
    event RecoverBEP20(address token, uint256 amount);
    event EnableTrading();
    event SetMarketingWallet(address newWallet, address oldWallet);
    event SetCharityWallet(address newWallet, address oldWallet);
    event SetTransferGas(uint256 newGas, uint256 oldGas);
    event SetWhitelisted(address account, bool value);
    event SetCEX(address account, bool value);
    event SetMarketMaker(address account, bool value);
    event SetDividendExempt(address account, bool exempt);
    event SetMinBalanceForDividends(uint256 amount);
    event SetSwapBackSettings(bool enabled, uint256 amount);
    event TriggerSwapBack();
    event SetTaxes(uint256 buyTax, uint256 sellTax, uint256 transferTax);
    event SetTaxShares(uint256 rewardShare, uint256 charityShare, uint256 liquidityShare, uint256 marketingShare);
    event DepositMarketing(address wallet, uint256 amount);
    event DepositCharity(address wallet, uint256 amount);
    event AutoLiquidity(uint256 pairAmount, uint256 tokenAmount);

    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

    constructor() BEP20(marketingWallet) {
        pair = IDEXFactory(ROUTER.factory()).createPair(ROUTER.WETH(), address(this));
        _approve(address(this), address(ROUTER), type(uint256).max);
        isMarketMaker[pair] = true;

        distributor = new DividendDistributor();
        _excludeAccounts();
    }

    // Public

    receive() external payable {}

    function getCirculatingSupply() external view returns (uint256) {
        return totalSupply() - balanceOf(DEAD);
    }

    // Private

    function _transfer(address sender, address recipient, uint256 amount) internal override {
        if (!isWhitelisted[sender]) { require(tradingEnabled, "Trading is disabled"); }

        if (inSwap || amount == 0) {
            super._transfer(sender, recipient, amount);
            return;
        }

        if (_shouldSwapBack(recipient)) { _swapBack(); }
        uint256 amountAfterTaxes = _shouldTakeTaxes(sender) ? _takeTax(sender, recipient, amount) : amount;
        super._transfer(sender, recipient, amountAfterTaxes);

        if (_shouldSetShares(sender)) { try distributor.setShare(sender, balanceOf(sender)) {} catch {} }
        if (_shouldSetShares(recipient)) { try distributor.setShare(recipient, balanceOf(recipient)) {} catch {} }
        if (_shouldProcessDividends(sender, recipient)) { try distributor.process() {} catch {} }
    }

    function _shouldSwapBack(address recipient) private view returns (bool) {
        return isMarketMaker[recipient] && swapEnabled && balanceOf(address(this)) >= swapThreshold;
    }

    function _shouldTakeTaxes(address sender) private view returns (bool) {
        return !isWhitelisted[sender];
    }

    function _shouldSetShares(address account) private view returns (bool) {
        return !isDividendExempt[account] && balanceOf(account) >= minBalanceForDividends;
    }

    function _shouldProcessDividends(address sender, address recipient) private view returns (bool) {
        return !isWhitelisted[sender] && !isCEX[sender] && !isCEX[recipient];
    }

    function _swapBack() private swapping {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = ROUTER.WETH();

        uint256 liquidityTokens = swapThreshold * liquidityShare / totalShares / 2;
        uint256 amountToSwap = swapThreshold - liquidityTokens;
        uint256 balanceBefore = address(this).balance;

        ROUTER.swapExactTokensForETH(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountBNB = address(this).balance - balanceBefore;
        uint256 totalBNBShares = totalShares - liquidityShare / 2;

        uint256 amountBNBLiquidity = amountBNB * liquidityShare / totalBNBShares / 2;
        uint256 amountBNBMarketing = amountBNB * marketingShare / totalBNBShares;
        uint256 amountBNBCharity = amountBNB * charityShare / totalBNBShares;
        uint256 amountBNBRewards = amountBNB * rewardShare / totalBNBShares;

        try distributor.deposit{value: amountBNBRewards}() {} catch {}
        (bool marketingSuccess,) = payable(marketingWallet).call{value: amountBNBMarketing, gas: transferGas}("");
        if (marketingSuccess) { emit DepositMarketing(marketingWallet, amountBNBMarketing); }
        (bool charitySuccess,) = payable(charityWallet).call{value: amountBNBCharity, gas: transferGas}("");
        if (charitySuccess) { emit DepositCharity(charityWallet, amountBNBCharity); }

        if (liquidityTokens > 0) {
            ROUTER.addLiquidityETH{value: amountBNBLiquidity}(
                address(this),
                liquidityTokens,
                0,
                0,
                address(this),
                block.timestamp
            );

            emit AutoLiquidity(amountBNBLiquidity, liquidityTokens);
        }
    }

    function _takeTax(address sender, address recipient, uint256 amount) private returns (uint256) {
        uint256 taxAmount = amount * _getTotalTax(sender, recipient) / DENOMINATOR;
        if (taxAmount > 0) { super._transfer(sender, address(this), taxAmount); }
        return amount - taxAmount;
    }

    function _getTotalTax(address sender, address recipient) private view returns (uint256) {
        if (isCEX[recipient]) { return 0; }
        if (isCEX[sender]) { return buyTax; }

        if (isMarketMaker[sender]) {
            return buyTax;
        } else if (isMarketMaker[recipient]) {
            return sellTax;
        } else {
            return transferTax;
        }
    }

    function _excludeAccounts() private {
        isWhitelisted[marketingWallet] = true;
        isDividendExempt[marketingWallet] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[pair] = true;
        isDividendExempt[DEAD] = true;
    }

    // Maintenance

    function preparePresale(address presale) external onlyOwner {
        require(!presaleInitialized, "Presale is already initialized");
        isWhitelisted[presale] = true;
        isDividendExempt[presale] = true;
        distributor.setShare(presale, 0);
        presaleInitialized = true;
        emit PreparePresale(presale);
    }

    function recoverBNB() external onlyOwner {
        uint256 amount = address(this).balance;
        (bool sent,) = payable(marketingWallet).call{value: amount, gas: transferGas}("");
        require(sent, "Tx failed");
        emit RecoverBNB(amount);
    }

    function recoverBEP20(IBEP20 token, address recipient) external onlyOwner {
        require(address(token) != address(this), "Can't withdraw MRFLOKI");
        uint256 amount = token.balanceOf(address(this));
        token.transfer(recipient, amount);
        emit RecoverBEP20(address(token), amount);
    }

    function enableTrading() external onlyOwner {
        tradingEnabled = true;
        emit EnableTrading();
    }

    function setMarketingWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "New marketing wallet is the zero address");
        isWhitelisted[marketingWallet] = false;
        isDividendExempt[marketingWallet] = false;
        isDividendExempt[newWallet] = true;
        emit SetMarketingWallet(newWallet, marketingWallet);
        marketingWallet = newWallet;
    }

    function setCharityWallet(address newWallet) external onlyOwner {
        require(newWallet != address(0), "New charity wallet is the zero address");
        emit SetCharityWallet(newWallet, charityWallet);
        charityWallet = newWallet;
    }

    function setTransferGas(uint256 gas) external onlyOwner {
        require(gas >= 21000 && gas <= 50000, "Invalid parameter");
        emit SetTransferGas(gas, transferGas);
        transferGas = gas;
    }

    function setIsWhitelisted(address account, bool value) external onlyOwner {
        require(account != pair, "Can't modify pair");
        isWhitelisted[account] = value;
        emit SetWhitelisted(account, value);
    }

    function setIsCEX(address account, bool value) external onlyOwner {
        require(account != pair, "Can't modify pair");
        isCEX[account] = value;
        emit SetCEX(account, value);
    }

    function setIsMarketMaker(address account, bool value) external onlyOwner {
        require(account != pair, "Can't modify pair");
        isMarketMaker[account] = value;
        emit SetMarketMaker(account, value);
    }

    function setIsDividendExempt(address account, bool exempt) external onlyOwner {
        require(account != address(this) && account != pair && account != marketingWallet, "Invalid account");

        isDividendExempt[account] = exempt;
        if (exempt) {
            distributor.setShare(account, 0);
        } else {
            distributor.setShare(account, balanceOf(account));
        }

        emit SetDividendExempt(account, exempt);
    }

    function setMinBalanceForDividends(uint256 amount) external onlyOwner {
        uint256 tokenAmount = amount * 10**decimals();
        require(tokenAmount <= 100000000 * 10**decimals(), "Invalid parameter");
        minBalanceForDividends = tokenAmount;
        emit SetMinBalanceForDividends(tokenAmount);
    }

    function setSwapBackSettings(bool enabled, uint256 amount) external onlyOwner {
        uint256 tokenAmount = amount * 10**decimals();
        swapEnabled = enabled;
        swapThreshold = tokenAmount;
        emit SetSwapBackSettings(enabled, tokenAmount);
    }

    function triggerSwapBack() external onlyOwner {
        _swapBack();
        emit TriggerSwapBack();
    }

    function setTaxes(uint256 newBuyTax, uint256 newSellTax, uint256 newTransferTax) external onlyOwner {
        require(newBuyTax <= 3000 && newSellTax <= 3500 && newTransferTax <= 1500, "Too high taxes");
        buyTax = newBuyTax;
        sellTax = newSellTax;
        transferTax = newTransferTax;
        emit SetTaxes(buyTax, sellTax, transferTax);
    }

    function setTaxShares(
        uint256 newRewardShare,
        uint256 newCharityShare,
        uint256 newLiquidityShare,
        uint256 newMarketingShare
    ) external onlyOwner {
        rewardShare = newRewardShare;
        charityShare = newCharityShare;
        liquidityShare = newLiquidityShare;
        marketingShare = newMarketingShare;
        totalShares = rewardShare + charityShare + liquidityShare + marketingShare;
        emit SetTaxShares(rewardShare, charityShare, liquidityShare, marketingShare);
    }

    function setDistributionCriteria(uint256 newPeriod, uint256 newMinDistribution) external onlyOwner {
        distributor.setDistributionCriteria(newPeriod, newMinDistribution);
    }

    function setGasLimit(uint256 newGasLimit) external onlyOwner {
        distributor.setGasLimit(newGasLimit);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IBEP20.sol";
import "./Ownable.sol";

contract BEP20 is IBEP20, Ownable {
    mapping (address => uint256) private _balances;
    mapping (address => mapping (address => uint256)) private _allowances;

    string private constant NAME = "MarioFloki";
    string private constant SYMBOL = "MRFLOKI";
    uint8 private constant DECIMALS = 18;
    uint256 private constant TOTAL_SUPPLY = 10**12 * 10**DECIMALS;

    constructor(address recipient) {
        _balances[recipient] = TOTAL_SUPPLY;
        emit Transfer(address(0), recipient, TOTAL_SUPPLY);
    }

    function getOwner() public view returns (address) {
        return owner();
    }

    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }

    function symbol() external pure returns (string memory) {
        return SYMBOL;
    }

    function name() external pure returns (string memory) {
        return NAME;
    }

    function totalSupply() public pure returns (uint256) {
        return TOTAL_SUPPLY;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function transfer(address recipient, uint256 amount) external returns (bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][msg.sender];
        require(currentAllowance >= amount, "BEP20: transfer amount exceeds allowance");

        _approve(sender, msg.sender, currentAllowance - amount);
        return true;
    }

    function increaseAllowance(address spender, uint256 addedValue) public returns (bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public returns (bool) {
        uint256 currentAllowance = _allowances[msg.sender][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");

        _approve(msg.sender, spender, currentAllowance - subtractedValue);
        return true;
    }

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "BEP20: transfer amount exceeds balance");
        _balances[sender] = senderBalance - amount;
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _approve(address owner, address spender, uint256 amount) internal {
        require(owner != address(0), "BEP20: approve from the zero address");
        require(spender != address(0), "BEP20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

import "./IBEP20.sol";
import "./IDEX.sol";

contract DividendDistributor {
    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IBEP20 constant BUSD = IBEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);
    IDEXRouter public constant ROUTER = IDEXRouter(0x10ED43C718714eb63d5aA57B78B54704E256024E);
    address immutable token;
    address[] shareHolders;
    uint256 currentIndex;

    mapping (address => Share) public shares;
    mapping (address => uint256) shareholderIndexes;
    mapping (address => uint256) shareholderClaims;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10**18;

    uint256 public gasLimit = 300000;
    uint256 public minPeriod = 1 hours;
    uint256 public minDistribution = 10**18;
    
    event Deposit(uint256 amount);
    event SetShare(address indexed account, uint256 amount);
    event Process();
    event DividendDistributed(address indexed to, uint256 amount);
    event SetDistributionCriteria(uint256 period, uint256 amount);
    event SetGasLimit(uint256 newGas, uint256 oldGas);

    modifier onlyToken() {
        require(msg.sender == token);
        _;
    }

    constructor () {
        token = msg.sender;
    }

    // Token interface

    function deposit() external payable onlyToken {
        if (msg.value > 0) {
            address[] memory path = new address[](2);
            path[0] = ROUTER.WETH();
            path[1] = address(BUSD);

            uint256 balanceBefore = BUSD.balanceOf(address(this));
            ROUTER.swapExactETHForTokens{value: msg.value}(
                0,
                path,
                address(this),
                block.timestamp
            );
            uint256 receivedAmount = BUSD.balanceOf(address(this)) - balanceBefore;

            totalDividends += receivedAmount;
            dividendsPerShare += dividendsPerShareAccuracyFactor * receivedAmount / totalShares;

            emit Deposit(msg.value);
        }
    }

    function setShare(address shareholder, uint256 amount) external onlyToken {
        if (shares[shareholder].amount > 0) {
            distributeDividend(shareholder);
        }

        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }

        totalShares = totalShares - shares[shareholder].amount + amount;
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);

        emit SetShare(shareholder, amount);
    }

    function process() external onlyToken {
        uint256 shareholderCount = shareHolders.length;
        if (shareholderCount == 0) { return; }

        uint256 gasLeft = gasleft();
        uint256 gasUsed;
        uint256 avgGasCost;
        uint256 iterations;

        while (gasUsed + avgGasCost < gasLimit && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) { currentIndex = 0; }

            if(shouldDistribute(shareHolders[currentIndex])){
                distributeDividend(shareHolders[currentIndex]);
            }

            gasUsed += gasLeft - gasleft();
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
            avgGasCost = gasUsed / iterations;
        }

        emit Process();
    }

    // Public

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder) public view returns (uint256) {
        if (shares[shareholder].amount == 0) { return 0; }

        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if (shareholderTotalDividends <= shareholderTotalExcluded) { return 0; }
        return shareholderTotalDividends - shareholderTotalExcluded;
    }

    // Private
    
    function shouldDistribute(address shareholder) private view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) private {
        if (shares[shareholder].amount == 0) { return; }

        uint256 amount = getUnpaidEarnings(shareholder);
        if (amount > 0) {
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised += amount;
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);

            totalDistributed += amount;
            BUSD.transfer(shareholder, amount);

            emit DividendDistributed(shareholder, amount);
        }
    }

    function getCumulativeDividends(uint256 share) private view returns (uint256) {
        return share * dividendsPerShare / dividendsPerShareAccuracyFactor;
    }

    function addShareholder(address shareholder) private {
        shareholderIndexes[shareholder] = shareHolders.length;
        shareHolders.push(shareholder);
    }

    function removeShareholder(address shareholder) private {
        shareHolders[shareholderIndexes[shareholder]] = shareHolders[shareHolders.length-1];
        shareholderIndexes[shareHolders[shareHolders.length-1]] = shareholderIndexes[shareholder];
        shareHolders.pop();
    }

    // Maintenance

    function setDistributionCriteria(uint256 newPeriod, uint256 newMinDistribution) external onlyToken {
        require(newPeriod <= 1 weeks && newMinDistribution <= 1 ether, "Invalid parameters");
        minPeriod = newPeriod;
        minDistribution = newMinDistribution;
        emit SetDistributionCriteria(newPeriod, newMinDistribution);
    }

    function setGasLimit(uint256 newGasLimit) external onlyToken {
        require(newGasLimit <= 500000 && newGasLimit >= 100000);
        emit SetGasLimit(newGasLimit, gasLimit);
        gasLimit = newGasLimit;
    }
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

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


// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

interface IDEXFactory {
    function createPair(address tokenA, address tokenB) external returns (address pair);
}

interface IDEXRouter {
    function factory() external pure returns (address);
    function WETH() external pure returns (address);

    function swapExactETHForTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable returns (uint[] memory amounts);
    function swapExactTokensForETH(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}


// SPDX-License-Identifier: MIT

pragma solidity 0.8.10;

abstract contract Ownable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        require(owner() == msg.sender, "Ownable: caller is not the owner");
        _;
    }

    constructor() {
        _owner = msg.sender;
        emit OwnershipTransferred(address(0), _owner);
    }

    function transferOwnership(address newOwner) public onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }

    function owner() internal view returns (address) {
        return _owner;
    }
}

