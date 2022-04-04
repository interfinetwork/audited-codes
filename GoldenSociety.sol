// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

//import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";

import "./Periphery.sol";

interface IGoldToken is IERC20 {
    function nodeApprove(address sender, address spender, uint256 amount) external returns (bool);
}

contract GoldenSociety is Context, Ownable, Pausable {
    using SafeMath for uint;
    using SafeMath for uint256;

    NodeManager public manager;
    Pool public rewardPool;
    IGoldToken public goldToken;

    address public currentRouter;
    IJoeRouter02 public router;


    address public DEAD = 0x000000000000000000000000000000000000dEaD;
    address private WAVAX;
    address payable public marketingWallet = payable(0xF0c8f27FB20BBBD1b0a4B199f9f8c7aBD684A1e8);
    address payable public treasuryWallet = payable(0x4a0f00a7d6Ca0F8A78051DF9Ef648978d0C359ee);

    uint256 public claimLiquidityAmount = 0;
    uint256 public claimLiquidityThreshold = 10;
    uint public swapThreshold = 10;


    uint public maxNodes = 100;
    uint256 public claimFee = 50;

    struct NodeRatios {
        uint16 poolFee;
        uint16 liquidityFee;
        uint16 vaultFee;
        uint16 marketingFee;
        uint16 total;
    }

    NodeRatios public _nodeRatios = NodeRatios({
    poolFee : 55,
    liquidityFee : 35,
    vaultFee : 5,
    marketingFee : 5,
    total : 100
    });

    struct ClaimRatios {
        uint16 vaultFee;
        uint16 marketingFee;
        uint16 total;
    }

    ClaimRatios public _claimRatios = ClaimRatios({
    vaultFee : 50,
    marketingFee : 50,
    total : 100
    });

    bool private swapLiquify = true;

    event AutoLiquify(uint256 amountAVAX, uint256 amount);

    mapping(address => bool) public blacklist;



    constructor(address _manager, address _goldToken, address _router) Ownable() {
        manager = NodeManager(_manager);
        goldToken = IGoldToken(_goldToken);
        rewardPool = new Pool(_goldToken);
        currentRouter = _router;
        router = IJoeRouter02(currentRouter);
        WAVAX = router.WAVAX();
    }

    event Received(address, uint);

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function pause() external onlyOwner returns (bool) {
        _pause();
        return true;
    }

    function unpause() external onlyOwner returns (bool) {
        _unpause();
        return true;
    }

    function setBlacklisted(address user, bool _val) external onlyOwner {
        blacklist[user] = _val;
    }

    function setTreasury(address _treasuryWallet) external onlyOwner {
        treasuryWallet = payable(_treasuryWallet);
    }

    function approveTokenOnRouter() external onlyOwner {
        goldToken.approve(currentRouter, type(uint256).max);
    }

    function updatePoolAddress(address _rewardPool) external onlyOwner {
        rewardPool.pay(address(owner()), goldToken.balanceOf(address(rewardPool)));
        rewardPool = new Pool(_rewardPool);
    }

    function updateManager(NodeManager _newManager) external onlyOwner {
        manager = NodeManager(_newManager);
    }

    function setMarketing(address payable _marketingWallet) external onlyOwner {
        marketingWallet = _marketingWallet;
    }

    function setNodeRatios(uint16 _poolFee, uint16 _liquidityFee, uint16 _vaultFee, uint16 _marketingFee) external onlyOwner {
        _nodeRatios.poolFee = _poolFee;
        _nodeRatios.liquidityFee = _liquidityFee;
        _nodeRatios.vaultFee = _vaultFee;
        _nodeRatios.marketingFee = _marketingFee;

        _nodeRatios.total = _poolFee + _liquidityFee + _vaultFee + _marketingFee;
    }

    function setClaimRatios(uint16 _vaultFee, uint16 _marketingFee) external onlyOwner {
        _claimRatios.vaultFee = _vaultFee;
        _claimRatios.marketingFee = _marketingFee;
        _claimRatios.total = _vaultFee + _marketingFee;
    }

    function setClaimLiquidityThreshold(uint256 _amount) external onlyOwner {
        claimLiquidityThreshold = _amount;
    }

    function tokenApprovals() external onlyOwner {
        goldToken.approve(address(router), 2_000_000 * 10 ^ 18);
    }

    function setNewRouter(address _dexRouter) external onlyOwner() {
        router = IJoeRouter02(_dexRouter);
    }

    function updateMaxWallet(uint256 _maxWallet) external onlyOwner {
        maxNodes = _maxWallet;
    }

    function updateClaimFee(uint256 _claimFee) external onlyOwner {
        claimFee = _claimFee;
    }



    //    Liquidation

    // divide node creation tokens to wallets
    function swapNodeAmount(uint256 numTokensToSwap) internal {
        if (_nodeRatios.total == 0) {
            return;
        }

        uint256 amountToLiquify = ((numTokensToSwap * _nodeRatios.liquidityFee) / _nodeRatios.total) / 2;
        uint256 amountToRewardsPool = (numTokensToSwap * _nodeRatios.poolFee) / _nodeRatios.total;
        uint256 amountToMarketing = (numTokensToSwap * _nodeRatios.marketingFee) / _nodeRatios.total;
        uint256 amountToTreasury = (numTokensToSwap * _nodeRatios.vaultFee) / _nodeRatios.total;

        // RewardPool
        if (amountToRewardsPool > 0) {
            goldToken.transfer(address(rewardPool), amountToRewardsPool);
        }

        // MARKETING swap
        contractSwapToWallet(amountToMarketing, marketingWallet);

        // Treasury swap
        contractSwapToWallet(amountToTreasury, treasuryWallet);

        // Liquidity
        contractSwapToWallet(amountToLiquify, address(this));

        uint256 amountAVAX = address(this).balance;
        if (amountToLiquify > 0) {
            router.addLiquidityAVAX{value : amountAVAX}(
                address(goldToken),
                amountToLiquify,
                0,
                0,
                marketingWallet,
                block.timestamp
            );
            emit AutoLiquify(amountAVAX, amountToLiquify);
        }

    }

    //    divide claimed fees to wallets
    function swapClaimAmount(uint256 feeAmount) internal {
        // MARKETING swap
        uint256 amountToMarketingWallet = (feeAmount * _claimRatios.marketingFee) / _claimRatios.total;
        contractSwapToWallet(amountToMarketingWallet, marketingWallet);

        // Treasury swap
        uint256 amountToTreasury = (feeAmount * _claimRatios.vaultFee) / _claimRatios.total;
        contractSwapToWallet(amountToTreasury, treasuryWallet);
    }



    //    Nodes

    function canCreateNode(bool onlyTokens) external view returns (bool) {
        return _canCreateNode(_msgSender(), onlyTokens);
    }

    function _canCreateNode(address sender, bool onlyTokens) internal view returns (bool canCreate) {
        require(sender != address(0), 'ZERO address');
        canCreate = false;

        if (!onlyTokens && manager.nodeBalanceOf(sender) > 0 && manager.availableRewardsFor(sender) >= (manager.nodePriceFor(sender) / 2)) {
            canCreate = true;
        } else if (manager.cappedNodeCount() < manager.getNodeCap()) {
            canCreate = true;
        }

        if (manager.limitDailyNodes() && manager.dailyNodesCreatedFor(sender) >= 5)
            canCreate = false;
    }

    function createNodeWithTokens() whenNotPaused public {
        address sender = _msgSender();
        require(sender != address(0), "0");
        require(_canCreateNode(sender, true), 'cant create');
        uint256 nodePrice = manager.nodePriceFor(sender);
        require(nodePrice > 0, "error");
        require(goldToken.balanceOf(sender) >= nodePrice, "blnce");
        require(manager.nodeBalanceOf(sender) + 1 < maxNodes, "mxwlt");
//        require(goldToken.nodeApprove(sender, address(this), nodePrice), 'aprv');
        require(goldToken.transferFrom(_msgSender(), address(this), nodePrice), 'trfr');

        manager.createNode(sender, true);
        if ((goldToken.balanceOf(address(this)) > swapThreshold)) {
            uint256 contractTokenBalance = goldToken.balanceOf(address(this));
            swapNodeAmount(contractTokenBalance);
        }
    }

    function createNodeWithRewards() whenNotPaused public {
        address sender = _msgSender();
        require(sender != address(0), "0");
        require(blacklist[sender] == false, "blcklst");
        require(_canCreateNode(sender, false), 'cant create');

        uint256 claimAmount = manager.claim(_msgSender());
        uint256 nodePrice = manager.nodePriceFor(sender);
        require(claimAmount + goldToken.balanceOf(sender) >= nodePrice, "norwrd");

        require(manager.nodeBalanceOf(sender) < maxNodes, "mxwlt");
        manager.createNode(sender, false);

        if (claimAmount > nodePrice) {
            uint256 remainingClaim = claimAmount - nodePrice;
            uint256 claimFeeAmount = remainingClaim.mul(getClaimFee(sender)).div(100);
            uint256 excessRewards = remainingClaim - claimFeeAmount;
            rewardPool.pay(sender, excessRewards);

            swapClaimAmount(claimFeeAmount);
        } else if (claimAmount + goldToken.balanceOf(sender) >= nodePrice) {
            uint256 balanceToTransfer = nodePrice - claimAmount;
//            require(goldToken.nodeApprove(sender, address(this), balanceToTransfer), 'aprv');
            goldToken.transferFrom(sender, address(this), balanceToTransfer);
        }

        if ((goldToken.balanceOf(address(this)) > swapThreshold)) {
            uint256 contractTokenBalance = goldToken.balanceOf(address(this));
            swapNodeAmount(contractTokenBalance);
        }
    }

//    claim rewards
    function claim() public {
        address sender = _msgSender();
        require(sender != address(0), "0");
        require(blacklist[sender] == false, "blcklst");
        uint256 rewardAmount = manager.claim(sender);
        require(rewardAmount > 0, "norwrd");

        uint256 feeAmount = rewardAmount.mul(getClaimFee(sender)).div(100);
        require(feeAmount > 0, "nofee");

        uint256 realReward = rewardAmount - feeAmount;
        rewardPool.pay(sender, realReward);

        swapClaimAmount(feeAmount);
    }



    // Internal swap tokens for avax DRY
    function contractSwapToWallet(uint256 amountToSwap, address wallet) internal {
        address[] memory path = new address[](2);
        path[0] = address(goldToken);
        path[1] = WAVAX;
        rewardPool.pay(address(this), amountToSwap);
        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            wallet,
            block.timestamp
        );
    }

    function getClaimFee(address sender) public view returns (uint256) {
        require(sender != address(0), '0');
        return claimFee;
    }


}

// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

import "@openzeppelin/contracts/security/Pausable.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";

import "./Periphery.sol";

contract GoldToken is IERC20, Pausable, Ownable {

    string constant private _name = "Gold Society Token";
    string constant private _symbol = "GTEST";
    uint8 private _decimals = 18;

    mapping(address => uint256) _holders;
    mapping(address => mapping(address => uint256)) _allowances;

    address private WAVAX;
    address public DEAD = 0x000000000000000000000000000000000000dEaD;
    address private zero = 0x0000000000000000000000000000000000000000;

    address payable public marketingWallet = payable(0xF0c8f27FB20BBBD1b0a4B199f9f8c7aBD684A1e8); //change
    address payable private rewardsPool = payable(DEAD);
    address payable private treasuryWallet = payable(0x4a0f00a7d6Ca0F8A78051DF9Ef648978d0C359ee); //change

    mapping(address => bool) private _liquidityHolders;
    mapping(address => bool) _isFeeExcluded;


    struct Ratios {
        uint16 rewards;
        uint16 liquidity;
        uint16 marketing;
        uint16 treasury;
        uint16 total;
    }

    Ratios public _ratios = Ratios({
    rewards : 0,
    liquidity : 20,
    marketing : 40,
    treasury : 40,
    total : 100
    });

    struct SellRatios {
        uint16 sell1;
        uint16 sell2;
        uint16 sell3;
        uint16 sell4;
        uint16 sell5;
        uint16 transferFee;
        uint16 divisor;
    }

    SellRatios public _sellRatios = SellRatios({
        sell1: 400,
        sell2: 150,
        sell3: 175,
        sell4: 200,
        sell5: 300,
        transferFee: 500,
        divisor: 1000
    });

    NodeManager public manager;

    uint256 constant private startingSupply = 2_000_000;
    uint256 private _totalSupply = startingSupply * (10 ** _decimals);


    address currentRouterAddress;
    IJoeRouter02 router;

    address lpPair;
    mapping(address => bool) lpPairs;
    uint private timeSinceLastPair = 0;

    bool public tradingEnabled = false;
    bool public hasLiqBeenAdded = false;

    uint256 private snipeBlockAmt = 0;
    uint256 public snipersCaught = 0;
    bool private sameBlockActive = true;
    bool private sniperProtection = true;
    uint256 private _liqAddBlock = 0;
    mapping(address => bool) private _isSniper;


    uint private _maxTxAmount = 100 ether;
    uint private _maxWalletSize = 1000 ether;


    event ContractSwapEnabledUpdated(bool enabled);
    event AutoLiquify(uint256 amountAVAX, uint256 amount);
    event SniperCaught(address sniperAddress);


    bool public contractSwapEnabled = false;
    uint256 private swapThreshold = 100;
    uint256 private swapAmount = _totalSupply * 5 / 1000;
    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }



    constructor() Ownable() {
        _holders[msg.sender] = _totalSupply;

        _isFeeExcluded[owner()] = true;
        _isFeeExcluded[address(this)] = true;

        emit Transfer(zero, msg.sender, _totalSupply);
    }


    // Starting protection

    function setStartingProtections(uint8 _block) external onlyOwner {
        require(snipeBlockAmt == 0 && _block <= 5 && !hasLiqBeenAdded);
        snipeBlockAmt = _block;
    }

    function isSniper(address account) public view returns (bool) {
        return _isSniper[account];
    }

    function removeSniper(address account) external onlyOwner() {
        require(_isSniper[account], "no snipe.");
        _isSniper[account] = false;
    }

    function setProtectionSettings(bool antiSnipe, bool antiBlock) external onlyOwner() {
        sniperProtection = antiSnipe;
        sameBlockActive = antiBlock;
    }

    function setRouter(address _router) external onlyOwner {
        router = IJoeRouter02(_router);
        address get_pair = IJoeFactory(router.factory()).getPair(address(this), router.WAVAX());
        if (get_pair == address(0)) {
            lpPair = IJoeFactory(router.factory()).createPair(address(this), router.WAVAX());
            lpPairs[lpPair] = true;
        } else {
            lpPair = get_pair;
            lpPairs[lpPair] = true;
        }
        WAVAX = router.WAVAX();
        _approve(address(this), address(router), type(uint256).max);
    }

    function setManager(address _nodeManager) external onlyOwner {
        require(_nodeManager != address(0), '0');
        manager = NodeManager(_nodeManager);
    }


    // Pausing

    function pause() external onlyOwner returns (bool) {
        _pause();
        return true;
    }

    function unpause() external onlyOwner returns (bool) {
        _unpause();
        return true;
    }




    //    management / ratios

    function enableTrading() public onlyOwner {
        require(!tradingEnabled, "trading off");
        require(hasLiqBeenAdded, "no liq");
        _liqAddBlock = block.number;
        tradingEnabled = true;
    }

    function setExcludedFromFees(address account, bool enabled) public onlyOwner {
        _isFeeExcluded[account] = enabled;
    }

    function setLiquidityHolder(address account, bool enabled) public onlyOwner {
        _liquidityHolders[account] = enabled;
    }

    function setRatios(uint16 _rewards, uint16 _liquidity, uint16 _marketing, uint16 _treasury) external onlyOwner {
        _ratios.rewards = _rewards;
        _ratios.liquidity = _liquidity;
        _ratios.marketing = _marketing;
        _ratios.treasury = _treasury;
        _ratios.total = _rewards + _liquidity + _marketing + _treasury;
    }

    function setSellRatios(uint16 _sell1, uint16 _sell2, uint16 _sell3, uint16 _sell4, uint16 _sell5, uint16 _transferFee, uint16 _divisor) external onlyOwner {
        _sellRatios.sell1 = _sell1;
        _sellRatios.sell2 = _sell2;
        _sellRatios.sell3 = _sell3;
        _sellRatios.sell4 = _sell4;
        _sellRatios.sell5 = _sell5;
        _sellRatios.transferFee = _transferFee;
        _sellRatios.divisor = _divisor;
    }



    function setWallets(address payable marketing, address payable treasury, address payable rewards) external onlyOwner {
        marketingWallet = payable(marketing);
        treasuryWallet = payable(treasury);
        rewardsPool = payable(rewards);
    }



    //    TOKENOMICS

    function _hasLimits(address from, address to) private view returns (bool) {
        return from != owner()
        && to != owner()
        && tx.origin != owner()
        && !_liquidityHolders[to]
        && !_liquidityHolders[from]
        && !_isFeeExcluded[from]
        && !_isFeeExcluded[to]
        && to != DEAD
        && to != address(0)
        && from != address(this);
    }

    function isFeeExcluded(address account) public view returns (bool) {
        return _isFeeExcluded[account];
    }

    function setContractSwapSettings(bool _enabled) external onlyOwner {
        contractSwapEnabled = _enabled;
    }

    function setSwapSettings(uint256 thresholdPercent, uint256 thresholdDivisor, uint256 amountPercent, uint256 amountDivisor) external onlyOwner {
        swapThreshold = (_totalSupply * thresholdPercent) / thresholdDivisor;
        swapAmount = (_totalSupply * amountPercent) / amountDivisor;
    }

    function getCirculatingSupply() public view returns (uint256) {
        return (_totalSupply - (balanceOf(DEAD) + balanceOf(address(0))));
    }


    //    transferring

    function nodeApprove(address sender, address spender, uint256 amount) external returns (bool) {
        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
        return true;
    }

    function _transfer(address from, address to, uint256 amount) whenNotPaused internal returns (bool) {
        require(from != address(0), "f: 0");
        require(to != address(0), "t: 0");
        require(amount > 0, "tf == 0");
        if (_hasLimits(from, to)) {
            if (!tradingEnabled) {
                revert("trading off");
            }

            if (lpPairs[from] || lpPairs[to]) {
                require(amount <= _maxTxAmount, "max tx exceeded");
            }
            if (to != currentRouterAddress && !lpPairs[to]) {
                require(balanceOf(to) + amount <= _maxWalletSize, "maxWlt exceeded");
            }
        }

        bool takeFee = true;
        if (_isFeeExcluded[from] || _isFeeExcluded[to]) {
            takeFee = false;
        }

        return _finalizeTransfer(from, to, amount, takeFee);
    }

    function _finalizeTransfer(address from, address to, uint256 amount, bool takeFee) internal returns (bool) {
        if (sniperProtection) {
            if (isSniper(from) || isSniper(to)) {
                revert("snpr");
            }

            if (!hasLiqBeenAdded) {
                _checkLiquidityAdd(from, to);
                if (!hasLiqBeenAdded && _hasLimits(from, to)) {
                    revert("only owner");
                }
            } else {
                if (_liqAddBlock > 0 && lpPairs[from] && _hasLimits(from, to)) {
                    if (block.number - _liqAddBlock < snipeBlockAmt) {
                        _isSniper[to] = true;
                        snipersCaught ++;
                        emit SniperCaught(to);
                    }
                }
            }
        }

        _holders[from] -= amount;

        if (inSwap) {
            return _basicTransfer(from, to, amount);
        }

        uint256 contractTokenBalance = _holders[address(this)];
        if (contractTokenBalance >= swapAmount)
            contractTokenBalance = swapAmount;

        if (contractSwapEnabled && contractTokenBalance >= swapThreshold && !inSwap && !lpPairs[from]) {
            contractSwap(contractTokenBalance);
        }

        uint256 amountReceived = amount;

        if (takeFee) {
            amountReceived = takeTaxes(from, to, amount);
        }

        _holders[to] += amountReceived;

        emit Transfer(from, to, amountReceived);
        return true;
    }

    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _holders[recipient] += amount;
        emit Transfer(sender, recipient, amount);
        return true;
    }

    function getSellFee(address sender) internal view returns (uint) {
        require(sender != address(0), '0');
        uint nodeBalance = manager.nodeBalanceOf(sender);
        if (nodeBalance == 0) {
            return _sellRatios.sell1;
        } else if (nodeBalance <= 10) {
            return _sellRatios.sell2;
        } else if (nodeBalance > 10 && nodeBalance <= 20) {
            return _sellRatios.sell3;
        } else if (nodeBalance > 20 && nodeBalance <= 50) {
            return _sellRatios.sell4;
        } else if (nodeBalance > 50 && nodeBalance <= 100) {
            return _sellRatios.sell5;
        } else {
            return _sellRatios.divisor;
        }
    }

    function takeTaxes(address from, address to, uint256 amount) internal returns (uint256) {
        uint256 currentFee;
        if (from == lpPair) {
            currentFee = 0;
        } else if (to == lpPair) {
            currentFee = getSellFee(from);
        } else {
            currentFee = _sellRatios.transferFee;
        }

        if (currentFee == 0) {
            return amount;
        }

        uint256 feeAmount = amount * currentFee / _sellRatios.divisor;

        _holders[address(this)] += feeAmount;
        emit Transfer(from, address(this), feeAmount);

        return amount - feeAmount;
    }

    function contractSwap(uint256 numTokensToSwap) internal swapping {
        if (_ratios.total == 0) {
            return;
        }

        if (_allowances[address(this)][address(router)] != type(uint256).max) {
            _allowances[address(this)][address(router)] = type(uint256).max;
        }

        uint256 amountToLiquify = ((numTokensToSwap * _ratios.liquidity) / (_ratios.total)) / 2;
        uint256 amountToRewardsPool = (numTokensToSwap * _ratios.rewards) / (_ratios.total);

        if (amountToRewardsPool > 0) {
            emit Transfer(address(this), rewardsPool, amountToRewardsPool);
        }

        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = WAVAX;

        router.swapExactTokensForAVAXSupportingFeeOnTransferTokens(
            numTokensToSwap - amountToLiquify - amountToRewardsPool,
            0,
            path,
            address(this),
            block.timestamp
        );

        uint256 amountAVAX = address(this).balance;
        uint256 amountAVAXLiquidity = ((amountAVAX * _ratios.liquidity) / (_ratios.total)) / 2;


        if (amountToLiquify > 0) {
            router.addLiquidityAVAX{value : amountAVAXLiquidity}(
                address(this),
                amountToLiquify,
                0,
                0,
                owner(),
                block.timestamp
            );
            emit AutoLiquify(amountAVAXLiquidity, amountToLiquify);
        }


        if (address(this).balance > 0) {
            amountAVAX = address(this).balance;
            treasuryWallet.transfer((amountAVAX * _ratios.treasury) / (_ratios.treasury + _ratios.marketing));
            marketingWallet.transfer(address(this).balance);
        }
    }

    //    called on transfer, will enable contract when coins are transferred to Pool
    function _checkLiquidityAdd(address from, address to) private {
        require(!hasLiqBeenAdded, "liq added");
        if (!_hasLimits(from, to) && to == lpPair) {

            _liqAddBlock = block.number;
            _liquidityHolders[from] = true;
            hasLiqBeenAdded = true;

            contractSwapEnabled = true;
            emit ContractSwapEnabledUpdated(true);
        }
    }

    function multiSendTokens(address[] memory accounts, uint256[] memory amounts) external {
        require(accounts.length == amounts.length, "");
        for (uint8 i = 0; i < accounts.length; i++) {
            require(_holders[msg.sender] >= amounts[i]);
            _transfer(msg.sender, accounts[i], amounts[i] * 10 ** _decimals);
        }
    }

    //    ERC20 override

    receive() external payable {}

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transfer(msg.sender, recipient, amount);
    }

    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if (_allowances[sender][msg.sender] != type(uint256).max) {
            _allowances[sender][msg.sender] -= amount;
        }

        return _transfer(sender, recipient, amount);
    }

    function totalSupply() external view override returns (uint256) {return _totalSupply;}

    function decimals() external view override returns (uint8) {return _decimals;}

    function symbol() external pure override returns (string memory) {return _symbol;}

    function name() external pure override returns (string memory) {return _name;}

    function getOwner() external view override returns (address) {return owner();}

    function balanceOf(address account) public view override returns (uint256) {return _holders[account];}

    function allowance(address holder, address spender) external view override returns (uint256) {return _allowances[holder][spender];}

    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function _approve(address sender, address spender, uint256 amount) private {
        require(sender != address(0), "ERC20: approve from the 0");
        require(spender != address(0), "ERC20: approve to the 0");

        _allowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
    }


}


// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

//import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoePair.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeFactory.sol";
import "@traderjoe-xyz/core/contracts/traderjoe/interfaces/IJoeRouter02.sol";


contract NodeManager is Ownable {
    using SafeMath for uint;

    struct NodeEntity {
        uint id;
        uint lastClaimTime;
        uint createdAt;
    }

    mapping(address => NodeEntity[]) nodes;
    uint public nodeReward = 5; //daily
    uint public claimableUnit = 10 minutes; //seconds
    uint public claimableUnitDivisor = (1 days / claimableUnit); // 86400 / claimableUnit

    struct NodePrice {
        uint price1;
        uint price2;
        uint price3;
        uint price4;
        uint price5;
    }

    NodePrice private _nodePrices = NodePrice({
    price1 : 20 ether,
    price2 : 25 ether,
    price3 : 30 ether,
    price4 : 45 ether,
    price5 : 50 ether
    });


    uint public cappedNodeCount = 0;
    uint public totalNodeCount = 0;


    struct NodeCapSettings {
        uint nodeCapDivisor;
        uint minNodeCapIncrease;
        uint capIncreasePer;
        uint capSetAt;
        uint nodeCap;
    }

    NodeCapSettings public nodeCapSettings = NodeCapSettings({
    nodeCapDivisor : 20,
    minNodeCapIncrease : 120,
    capIncreasePer : 1 hours,
    capSetAt : 0,
    nodeCap : 2400
    });

    uint public dailyNodeLimit = 5;
    bool public limitDailyNodes = true;

    mapping(address => bool) private _authorizedContracts;
    modifier onlyGSContracts {
        require(_authorizedContracts[msg.sender] == true, 'Unauthorized access');
        _;
    }

    constructor(address _goldToken) Ownable() {
        _authorizedContracts[_goldToken] = true;
        nodeCapSettings.capSetAt = block.timestamp;
    }

    //    Node price in tokens
    function nodePrice() external view returns (uint _nodePrice) {
        require(msg.sender != address(0), 'ZERO address');
        _nodePrice = _nodePriceFor(msg.sender);
    }

    function nodePriceFor(address sender) external view returns (uint _nodePrice) {
        require(sender != address(0), 'ZERO address');
        _nodePrice = _nodePriceFor(sender);
    }

    function dailyNodesCreated() external view returns (uint) {
        return _dailyNodesCreated(msg.sender);
    }

    function dailyNodesCreatedFor(address sender) external view returns (uint) {
        return _dailyNodesCreated(sender);
    }

    function _dailyNodesCreated(address sender) internal view returns (uint nodesToday) {
        require(sender != address(0), 'ZERO ADDRESS');
        nodesToday = 0;
        for (uint i = 0; i < nodes[sender].length; i++) {
            if (block.timestamp - nodes[sender][i].createdAt < 1 days) {
                nodesToday++;
            }
        }
    }

    //    Return the nodecount of an address
    function nodeBalanceOf(address sender) external view onlyGSContracts returns (uint) {
        require(sender != address(0), "ZERO ADDRESS");
        return _nodeCount(sender);
    }

    //    nodes for msg sender
    function nodeBalance() external view returns (uint) {
        require(msg.sender != address(0), "ZERO ADDRESS");
        return _nodeCount(msg.sender);
    }

    function createNode(address sender, bool onlyTokens) external onlyGSContracts returns (bool) {
        if (onlyTokens) {
            cappedNodeCount++;
        }
        NodeEntity memory _newNode = NodeEntity({id : totalNodeCount++, lastClaimTime : block.timestamp, createdAt : block.timestamp});
        nodes[sender].push(_newNode);
        return true;
    }

    function availableRewards() external view returns (uint) {
        require(msg.sender != address(0), '0');
        return _availableRewards(msg.sender);
    }

    function availableRewardsFor(address sender) external onlyGSContracts view returns (uint) {
        require(sender != address(0), 'ZERO ADDRESS');
        require(_nodeCount(sender) > 0, 'No nodes available');
        return _availableRewards(sender);
    }

    function _availableRewards(address sender) internal view returns (uint _claimable) {
        _claimable = 0;
        for (uint i = 0; i < _nodeCount(sender); i++) {
            _claimable += _getRewardsForNode(sender, i);
        }
    }

    function _getRewardsForNode(address sender, uint _nodeIndex) internal view returns (uint) {
        NodeEntity memory _node = nodes[sender][_nodeIndex];

        if (_node.lastClaimTime == 0 || _node.lastClaimTime >= block.timestamp)
            return 0;

        uint _rewards = 0;
        uint claimableTime = block.timestamp.sub(_node.lastClaimTime);
        uint rewardPerUnit = _nodePrices.price1.div(100).mul(nodeReward).div(claimableUnitDivisor);
        uint rewardableUnits = claimableTime.div(claimableUnit);

        _rewards = rewardableUnits.mul(rewardPerUnit);
        return _rewards;
    }


    //    claim rewards to wallet and returns claimed amount
    function claim(address sender) external onlyGSContracts returns (uint claimable) {
        require(sender != address(0), 'ZERO ADDRESS');
        require(_nodeCount(sender) > 0, 'No nodes owned');
        claimable = 0;
        for (uint i = 0; i < _nodeCount(sender); i++) {
            claimable += _getRewardsForNode(sender, i);
            nodes[sender][i].lastClaimTime = block.timestamp;
        }
    }

    //    get cap increasy p /day
    function getDailyNodeCap() external view returns (uint) {
        return _dailyCap();
    }

    //    get total cap for node creation - also updates the cap if needed
    function getNodeCap() external view returns (uint) {
        return _totalCap();
    }

    function _nodeCount(address sender) internal view returns (uint) {
        return nodes[sender].length;
    }

    function capSetAt() external view returns (uint) {
        return nodeCapSettings.capSetAt;
    }

    function lastCapIncreaseAt() external view returns (uint) {
        uint nodeCapIncreases = Math.ceilDiv(
            block.timestamp - nodeCapSettings.capSetAt,
            nodeCapSettings.capIncreasePer
        ).sub(1);

        return nodeCapSettings.capSetAt.add(
            nodeCapSettings.capIncreasePer.mul(nodeCapIncreases)
        );
    }

    function capIncreasePer() external view returns (uint) {
        return nodeCapSettings.capIncreasePer;
    }

    function _dailyCap() internal view returns (uint _cap) {
        _cap = Math.ceilDiv(totalNodeCount, nodeCapSettings.nodeCapDivisor);
        if (_cap < nodeCapSettings.minNodeCapIncrease) {
            _cap = nodeCapSettings.minNodeCapIncrease;
        }
    }

    function _totalCap() internal view returns (uint _nodeCap) {
        _nodeCap = nodeCapSettings.nodeCap;
        uint nodeCapIncreases = Math.ceilDiv(
            block.timestamp - nodeCapSettings.capSetAt,
            nodeCapSettings.capIncreasePer
        ).sub(1);

        uint nodeCapFraction = Math.ceilDiv(
            _dailyCap(),
            uint(1 days).div(nodeCapSettings.capIncreasePer)
        );
        uint additionalCap = nodeCapFraction.mul(nodeCapIncreases);
        _nodeCap = nodeCapSettings.nodeCap.add(additionalCap);
    }

    //    Node price in tokens
    function _nodePriceFor(address sender) internal view returns (uint _nodePrice) {
        require(sender != address(0), 'ZERO address');
        if (_nodeCount(sender) <= 10) {
            _nodePrice = _nodePrices.price1;
        } else if (_nodeCount(sender) > 10 && _nodeCount(sender) <= 20) {
            _nodePrice = _nodePrices.price2;
        } else if (_nodeCount(sender) > 20 && _nodeCount(sender) <= 40) {
            _nodePrice = _nodePrices.price3;
        } else if (_nodeCount(sender) > 40 && _nodeCount(sender) <= 80) {
            _nodePrice = _nodePrices.price4;
        } else if (_nodeCount(sender) > 80 && _nodeCount(sender) <= 100) {
            _nodePrice = _nodePrices.price5;
        } else {
            _nodePrice = 10000 ether;
            // should not be possible but just in case 8-)
        }
        _nodePrice = _nodePrice;
    }


    //    Management

    function addAuthorizedContract(address _contractAddr) external onlyOwner {
        require(_contractAddr != address(0), 'ZERO ADDRESS');
        _authorizedContracts[_contractAddr] = true;
    }

    function removeAuthorizedContract(address _contractAddr) external onlyOwner {
        require(_contractAddr != address(0), 'ZERO ADDRESS');
        _authorizedContracts[_contractAddr] = false;
    }

    function updateDailyNodeLimit(bool _limitDailyNodes, uint _dailyNodeLimit) external onlyOwner {
        limitDailyNodes = _limitDailyNodes;
        dailyNodeLimit = _dailyNodeLimit;
    }

    function updateNodePrices(uint _price1, uint _price2, uint _price3, uint _price4, uint _price5) external onlyOwner returns (bool) {
        _nodePrices = NodePrice({
        price1 : _price1 * 10 ** 18,
        price2 : _price2 * 10 ** 18,
        price3 : _price3 * 10 ** 18,
        price4 : _price4 * 10 ** 18,
        price5 : _price5 * 10 ** 18
        });
        return true;
    }

    function updateReward(uint _reward) external onlyOwner {
        require(_reward >= 0 && _reward <= 5, 'Cannot have a reward lower than 0 or higher than 5');
        nodeReward = _reward;
    }

    function updateNodeCap(uint _nodeCapDivisor, uint _minNodeCapIncrease, uint _nodeCap) external onlyOwner {
        nodeCapSettings.nodeCapDivisor = _nodeCapDivisor;
        nodeCapSettings.minNodeCapIncrease = _minNodeCapIncrease;
        nodeCapSettings.capSetAt = block.timestamp;
        nodeCapSettings.nodeCap = _nodeCap;
    }
}

contract Pool is Ownable {
    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function pay(address _to, uint _amount) external onlyOwner returns (bool) {
        return token.transfer(_to, _amount);
    }
}

interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
   */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the token decimals.
   */
    function decimals() external view returns (uint8);

    /**
     * @dev Returns the token symbol.
   */
    function symbol() external view returns (string memory);

    /**
    * @dev Returns the token name.
  */
    function name() external view returns (string memory);

    /**
     * @dev Returns the bep token owner.
   */
    function getOwner() external view returns (address);

    /**
     * @dev Returns the amount of tokens owned by `account`.
   */
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

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
   * another (`to`).
   *
   * Note that `value` may be zero.
   */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}