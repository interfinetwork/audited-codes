// SPDX-License-Identifier: MIT


/*

########################
##BigShibZilla (SHIBZ)##
########################

This Token will change your life (wife)!
The craziest Meme Coin in the history of Meme Coins!
When Lambo? Now Lambo!
Have you ever heard of winning iPhones and TVs just for holding Tokens?
Have you ever heard of winning a Tesla, Mustang or a Lamborghini?
Have you ever heard of Millions of Dollars of Giveaways?
But that’s not all, we will additionally give away Tokens and NFTs to random holders every Sunday.
Buy and lean back!



############
##Road Map##
############

•	Weekly Token giveaways
•	Weekly NFT giveaways
•	Presale on Pinksale
•	Launch on Pancakeswap
•	Huge Marketing Campaigns
•	Coinmarketcap in the first week
•	Coingecko in the first week
•	Play and Earn

•	Giveaways – once Volume is reached (in total):
o	$1,000,000			10x iPhones, 10x Samsung TVs
o	$5,000,000			40x iPhones, 40x Samsung TVs
o	$10,000,000			3x Tesla Model 3
o	$20,000,000			3x Ford Mustang GT 
o	$50,000,000			3x Lamborghini Huracan EVO
o	$100,000,000	 		10x 100,000$ Giveaway
o	$500,000,000	 		10x 1,000,000$ Giveaway
o	$1,000,000,000 		10x 2,000,000$ Giveaway
o	$10,000,000,000		10x 10,000,000$ Giveaway

           #                       #                       #                      
          ###                     ###                     ###                    
         #####                   #####                   #####                  
        #######                 #######                 #######                
       #########               #########               #########              
      ###########             ###########             ###########            
     #############           #############           #############          
    ###############         ###############         ###############        
   #################       #################       #################      
  ###################     ###################     ###################    
 #####################   #####################   #####################  
  ###################     ###################     ###################    
   #################       #################       #################      
    ###############         ###############         ###############        
     #############           #############           #############          
      ###########             ###########             ###########            
       #########               #########               #########              
        #######                 #######                 #######                
         #####                   #####                   #####                  
          ###                     ###                     ###                    
           #                       #                       #                             

 */


pragma solidity ^0.6.2;

import "./DividendPayingToken.sol";
import "./SafeMath.sol";
import "./IterableMapping.sol";
import "./Ownable.sol";
import "./IUniswapV2Pair.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Router.sol";


contract SHIBZ is ERC20, Ownable {
    using SafeMath for uint256;

    IUniswapV2Router02 public uniswapV2Router;
    address public  uniswapV2Pair;

    bool private swapping;
    bool public shibaBurnEnabled = true;

    SHIBZDividendTracker public dividendTracker;

    address public deadWallet = 0x000000000000000000000000000000000000dEaD;

    address public immutable shibaInu = address(0x2859e4544C4bB03966803b044A93563Bd2D0DD4D); //ShibaInu

    uint256 public swapTokensAtAmount = 50000000 * (10**18);
    uint256 public maxWalletToken = 50000000000 * (10**18);
    uint256 public shibBurnDivisor = 10;
    
    mapping(address => bool) public _isBlacklisted;
    
    uint256 public ShibaInuRewardsSellFee = 1;
    uint256 public LiquiditySellFee = 1;
    uint256 public MarketingSellFee = 1;
    uint256 public ShibBurnSellFee = 1;
    uint256 public AutoBurnSellFee = 1;
    uint256 public totalSellFees = ShibaInuRewardsSellFee.add(LiquiditySellFee).add(MarketingSellFee).add(ShibBurnSellFee).add(AutoBurnSellFee);
    
    uint256 public ShibaInuRewardsBuyFee = 1;
    uint256 public LiquidityBuyFee = 1;
    uint256 public MarketingBuyFee = 1;
    uint256 public ShibBurnBuyFee = 1;
    uint256 public AutoBurnBuyFee = 1;
    uint256 public totalBuyFees = ShibaInuRewardsBuyFee.add(LiquidityBuyFee).add(MarketingBuyFee).add(ShibBurnBuyFee).add(AutoBurnBuyFee);

    address payable public _marketingWalletAddress = payable(0x08d7572880E610A1Bb8c2b19ca4b24C6a0228218);
    
    // use by default 300,000 gas to process auto-claiming dividends
    uint256 public gasForProcessing = 300000;

     // exlcude from fees and max transaction amount
    mapping (address => bool) private _isExcludedFromFees;


    // store addresses that a automatic market maker pairs. Any transfer *to* these addresses
    // could be subject to a maximum transfer amount
    mapping (address => bool) public automatedMarketMakerPairs;
    
    event ShibaBurnEnabledUpdated(bool enabled);


    event UpdateDividendTracker(address indexed newAddress, address indexed oldAddress);

    event UpdateUniswapV2Router(address indexed newAddress, address indexed oldAddress);

    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);

    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);

    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event SendDividends(
        uint256 tokensSwapped,
        uint256 amount
    );

    event ProcessedDividendTracker(
        uint256 iterations,
        uint256 claims,
        uint256 lastProcessedIndex,
        bool indexed automatic,
        uint256 gas,
        address indexed processor
    );

    constructor() public ERC20("BigShibZilla", "SHIBZ") {

        dividendTracker = new SHIBZDividendTracker();


        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         // Create a uniswap pair for this new token
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;

        _setAutomatedMarketMakerPair(_uniswapV2Pair, true);

        // exclude from receiving dividends
        dividendTracker.excludeFromDividends(address(dividendTracker));
        dividendTracker.excludeFromDividends(address(this));
        dividendTracker.excludeFromDividends(owner());
        dividendTracker.excludeFromDividends(deadWallet);
        dividendTracker.excludeFromDividends(address(_uniswapV2Router));

        // exclude from paying fees or having max transaction amount
        excludeFromFees(owner(), true);
        excludeFromFees(_marketingWalletAddress, true);
        excludeFromFees(address(this), true);

        /*
            _mint is an internal function in ERC20.sol that is only called here,
            and CANNOT be called ever again
        */
        _mint(owner(), 50000000000 * (10**18));
    }

    receive() external payable {

    }

    function updateDividendTracker(address newAddress) public onlyOwner {
        require(newAddress != address(dividendTracker), "SHIBZ: The dividend tracker already has that address");

        SHIBZDividendTracker newDividendTracker = SHIBZDividendTracker(payable(newAddress));

        require(newDividendTracker.owner() == address(this), "SHIBZ: The new dividend tracker must be owned by the SHIBZ token contract");

        newDividendTracker.excludeFromDividends(address(newDividendTracker));
        newDividendTracker.excludeFromDividends(address(this));
        newDividendTracker.excludeFromDividends(owner());
        newDividendTracker.excludeFromDividends(address(uniswapV2Router));

        emit UpdateDividendTracker(newAddress, address(dividendTracker));

        dividendTracker = newDividendTracker;
    }

    function updateUniswapV2Router(address newAddress) public onlyOwner {
        require(newAddress != address(uniswapV2Router), "SHIBZ: The router already has that address");
        emit UpdateUniswapV2Router(newAddress, address(uniswapV2Router));
        uniswapV2Router = IUniswapV2Router02(newAddress);
        address _uniswapV2Pair = IUniswapV2Factory(uniswapV2Router.factory())
            .createPair(address(this), uniswapV2Router.WETH());
        uniswapV2Pair = _uniswapV2Pair;
    }

    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "SHIBZ: Account is already the value of 'excluded'");
        _isExcludedFromFees[account] = excluded;

        emit ExcludeFromFees(account, excluded);
    }

    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) public onlyOwner {
        for(uint256 i = 0; i < accounts.length; i++) {
            _isExcludedFromFees[accounts[i]] = excluded;
        }

        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }
    
    function SetSwapTokensAtAmount(uint256 _newAmount) external onlyOwner {
  	    swapTokensAtAmount = _newAmount * (10**18);
  	}
    
    function setMaxWalletTokend(uint256 _maxToken) external onlyOwner {
  	    maxWalletToken = _maxToken * (10**18);
  	}

    function setMarketingWallet(address payable wallet) external onlyOwner{
        _marketingWalletAddress = wallet;
    }
    
    function updateSellFees(uint256 rewardFee, uint256 _liquidityFee, uint256 _marketingFee, uint256 _ShibBurnFee, uint256 _burnFee) external onlyOwner{
        ShibaInuRewardsSellFee = rewardFee;
        LiquiditySellFee = _liquidityFee;
        MarketingSellFee = _marketingFee;
        ShibBurnSellFee = _ShibBurnFee;
        AutoBurnSellFee = _burnFee;
        totalSellFees = ShibaInuRewardsSellFee.add(LiquiditySellFee).add(MarketingSellFee).add(ShibBurnSellFee).add(AutoBurnSellFee);
    }
    
    function updateBuyFees(uint256 rewardFee, uint256 _liquidityFee, uint256 _marketingFee, uint256 _ShibBurnFee, uint256 _burnFee) external onlyOwner{
        ShibaInuRewardsBuyFee = rewardFee;
        LiquidityBuyFee = _liquidityFee;
        MarketingBuyFee = _marketingFee;
        ShibBurnBuyFee = _ShibBurnFee;
        AutoBurnBuyFee = _burnFee;
        totalBuyFees = ShibaInuRewardsBuyFee.add(LiquidityBuyFee).add(MarketingBuyFee).add(ShibBurnBuyFee).add(AutoBurnBuyFee);
    }

    function setAutomatedMarketMakerPair(address pair, bool value) public onlyOwner {
        require(pair != uniswapV2Pair, "SHIBZ: The PancakeSwap pair cannot be removed from automatedMarketMakerPairs");

        _setAutomatedMarketMakerPair(pair, value);
    }
    
    function blacklistAddress(address account, bool value) external onlyOwner{
        _isBlacklisted[account] = value;
    }
    
    function ShibBurnDivisor(uint256 divisor) external onlyOwner{
       shibBurnDivisor = divisor;
    }
    
    function SetShibBurnEnabled(bool _enabled) public onlyOwner {
        shibaBurnEnabled = _enabled;
        emit ShibaBurnEnabledUpdated(_enabled);
    }


    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "SHIBZ: Automated market maker pair is already set to that value");
        automatedMarketMakerPairs[pair] = value;

        if(value) {
            dividendTracker.excludeFromDividends(pair);
        }

        emit SetAutomatedMarketMakerPair(pair, value);
    }


    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 500000, "SHIBZ: gasForProcessing must be between 200,000 and 500,000");
        require(newValue != gasForProcessing, "SHIBZ: Cannot update gasForProcessing to same value");
        emit GasForProcessingUpdated(newValue, gasForProcessing);
        gasForProcessing = newValue;
    }

    function updateClaimWait(uint256 claimWait) external onlyOwner {
        dividendTracker.updateClaimWait(claimWait);
    }

    function getClaimWait() external view returns(uint256) {
        return dividendTracker.claimWait();
    }

    function getTotalDividendsDistributed() external view returns (uint256) {
        return dividendTracker.totalDividendsDistributed();
    }

    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    function withdrawableDividendOf(address account) public view returns(uint256) {
        return dividendTracker.withdrawableDividendOf(account);
    }

    function dividendTokenBalanceOf(address account) public view returns (uint256) {
        return dividendTracker.balanceOf(account);
    }

    function excludeFromDividends(address account) external onlyOwner{
        dividendTracker.excludeFromDividends(account);
    }

    function getAccountDividendsInfo(address account)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccount(account);
    }

    function getAccountDividendsInfoAtIndex(uint256 index)
        external view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return dividendTracker.getAccountAtIndex(index);
    }

    function processDividendTracker(uint256 gas) external {
        (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) = dividendTracker.process(gas);
        emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, false, gas, tx.origin);
    }

    function claim() external {
        dividendTracker.processAccount(msg.sender, false);
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfDividendTokenHolders() external view returns(uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }


    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Blacklisted address');
        
        bool excludedAccount = _isExcludedFromFees[from] || _isExcludedFromFees[to];
        
        if (automatedMarketMakerPairs[from] && !excludedAccount) {
            uint256 contractBalanceRecepient = balanceOf(to);
            require(contractBalanceRecepient + amount <= maxWalletToken, "Exceeds maximum wallet token amount.");
        }

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }

        uint256 contractTokenBalance = balanceOf(address(this));

        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != owner() &&
            to != owner()
        ) {
            swapping = true;

            uint256 marketingTokens = contractTokenBalance.mul(MarketingSellFee).div(totalSellFees.sub(AutoBurnSellFee));
            swapAndSendToFee(marketingTokens);

            uint256 swapTokens = contractTokenBalance.mul(LiquiditySellFee).div(totalSellFees.sub(AutoBurnSellFee));
            swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));
            swapAndSendDividends(sellTokens);
            
            uint256 ShibTokenBalance = IERC20(ShibaInu).balanceOf(address(this));
            if (shibaBurnEnabled && ShibTokenBalance > 0) {
                IERC20(ShibaInu).transfer(deadWallet, ShibTokenBalance.div(shibBurnDivisor));
            }
            
            

            swapping = false;
        }


        bool takeFee = !swapping;

        // if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
        }

        if(takeFee) {
            uint256 fees = amount.mul(totalBuyFees.sub(AutoBurnBuyFee)).div(100);
            uint256 burnShare = amount.mul(AutoBurnBuyFee).div(100);
            
            if(automatedMarketMakerPairs[to]) {
               fees = amount.mul(totalSellFees.sub(AutoBurnSellFee)).div(100);
               burnShare = amount.mul(AutoBurnSellFee).div(100);
               amount = amount.sub(fees.add(burnShare));
               super._transfer(from, address(this), fees);
               
               if(burnShare > 0) {
                  super._transfer(from, deadWallet, burnShare);
               } 
            }
            
            if(automatedMarketMakerPairs[from]){
               amount = amount.sub(fees.add(burnShare));
               super._transfer(from, address(this), fees);
               
               if(burnShare > 0) {
                   super._transfer(from, deadWallet, burnShare); 
               }
            }
            
        }

        super._transfer(from, to, amount);

        try dividendTracker.setBalance(payable(from), balanceOf(from)) {} catch {}
        try dividendTracker.setBalance(payable(to), balanceOf(to)) {} catch {}

        if(!swapping) {
            uint256 gas = gasForProcessing;

            try dividendTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
                emit ProcessedDividendTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
            }
            catch {

            }
        }
    }

    function swapAndSendToFee(uint256 tokens) private  {

        uint256 initialBalance = address(this).balance;

        swapTokensForEth(tokens);
        uint256 newBalance = address(this).balance.sub(initialBalance);
        payable(_marketingWalletAddress).transfer(newBalance);
    }

    function swapAndLiquify(uint256 tokens) private {
       // split the contract balance into halves
        uint256 half = tokens.div(2);
        uint256 otherHalf = tokens.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);

        emit SwapAndLiquify(half, newBalance, otherHalf);
    }


    function swapTokensForEth(uint256 tokenAmount) private {


        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );

    }

    function swapTokensForShibaInu(uint256 tokenAmount) private {

        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();
        path[2] = ShibaInu;

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {

        // approve token transfer to cover all possible scenarios
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

    }

    function swapAndSendDividends(uint256 tokens) private{
        uint256 initialShibaInuBalance = IERC20(ShibaInu).balanceOf(address(this));
        swapTokensForShibaInu(tokens);
        uint256 newBalance = (IERC20(ShibaInu).balanceOf(address(this))).sub(initialShibaInuBalance);
        uint256 holdersShare = newBalance.mul(ShibaInuRewardsSellFee).div(ShibaInuRewardsSellFee.add(ShibBurnSellFee));
        bool success = IERC20(ShibaInu).transfer(address(dividendTracker), holdersShare);

        if (success) {
            dividendTracker.distributeShibaInuDividends(holdersShare);
            emit SendDividends(tokens, holdersShare);
        }
    }
}

contract SHIBZDividendTracker is Ownable, DividendPayingToken {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;

    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    uint256 public claimWait;
    uint256 public immutable minimumTokenBalanceForDividends;

    event ExcludeFromDividends(address indexed account);
    event ClaimWaitUpdated(uint256 indexed newValue, uint256 indexed oldValue);

    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() public DividendPayingToken("SHIBZ_Dividen_Tracker", "SHIBZ_Dividend_Tracker") {
        claimWait = 3600;
        minimumTokenBalanceForDividends = 1000 * (10**18); //must hold 10000+ tokens
    }

    function _transfer(address, address, uint256) internal override {
        require(false, "SHIBZ_Dividend_Tracker: No transfers allowed");
    }

    function withdrawDividend() public override {
        require(false, "SHIBZ_Dividend_Tracker: withdrawDividend disabled. Use the 'claim' function on the main SHIBZ contract.");
    }

    function excludeFromDividends(address account) external onlyOwner {
        require(!excludedFromDividends[account]);
        excludedFromDividends[account] = true;

        _setBalance(account, 0);
        tokenHoldersMap.remove(account);

        emit ExcludeFromDividends(account);
    }

    function updateClaimWait(uint256 newClaimWait) external onlyOwner {
        require(newClaimWait >= 3600 && newClaimWait <= 86400, "SHIBZ_Dividend_Tracker: claimWait must be updated to between 1 and 24 hours");
        require(newClaimWait != claimWait, "SHIBZ_Dividend_Tracker: Cannot update claimWait to same value");
        emit ClaimWaitUpdated(newClaimWait, claimWait);
        claimWait = newClaimWait;
    }

    function getLastProcessedIndex() external view returns(uint256) {
        return lastProcessedIndex;
    }

    function getNumberOfTokenHolders() external view returns(uint256) {
        return tokenHoldersMap.keys.length;
    }



    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            uint256 secondsUntilAutoClaimAvailable) {
        account = _account;

        index = tokenHoldersMap.getIndexOfKey(account);

        iterationsUntilProcessed = -1;

        if(index >= 0) {
            if(uint256(index) > lastProcessedIndex) {
                iterationsUntilProcessed = index.sub(int256(lastProcessedIndex));
            }
            else {
                uint256 processesUntilEndOfArray = tokenHoldersMap.keys.length > lastProcessedIndex ?
                                                        tokenHoldersMap.keys.length.sub(lastProcessedIndex) :
                                                        0;


                iterationsUntilProcessed = index.add(int256(processesUntilEndOfArray));
            }
        }


        withdrawableDividends = withdrawableDividendOf(account);
        totalDividends = accumulativeDividendOf(account);

        lastClaimTime = lastClaimTimes[account];

        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function getAccountAtIndex(uint256 index)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        if(index >= tokenHoldersMap.size()) {
            return (0x0000000000000000000000000000000000000000, -1, -1, 0, 0, 0, 0, 0);
        }

        address account = tokenHoldersMap.getKeyAtIndex(index);

        return getAccount(account);
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
        if(lastClaimTime > block.timestamp)  {
            return false;
        }

        return block.timestamp.sub(lastClaimTime) >= claimWait;
    }

    function setBalance(address payable account, uint256 newBalance) external onlyOwner {
        if(excludedFromDividends[account]) {
            return;
        }

        if(newBalance >= minimumTokenBalanceForDividends) {
            _setBalance(account, newBalance);
            tokenHoldersMap.set(account, newBalance);
        }
        else {
            _setBalance(account, 0);
            tokenHoldersMap.remove(account);
        }

        processAccount(account, true);
    }

    function process(uint256 gas) public returns (uint256, uint256, uint256) {
        uint256 numberOfTokenHolders = tokenHoldersMap.keys.length;

        if(numberOfTokenHolders == 0) {
            return (0, 0, lastProcessedIndex);
        }

        uint256 _lastProcessedIndex = lastProcessedIndex;

        uint256 gasUsed = 0;

        uint256 gasLeft = gasleft();

        uint256 iterations = 0;
        uint256 claims = 0;

        while(gasUsed < gas && iterations < numberOfTokenHolders) {
            _lastProcessedIndex++;

            if(_lastProcessedIndex >= tokenHoldersMap.keys.length) {
                _lastProcessedIndex = 0;
            }

            address account = tokenHoldersMap.keys[_lastProcessedIndex];

            if(canAutoClaim(lastClaimTimes[account])) {
                if(processAccount(payable(account), true)) {
                    claims++;
                }
            }

            iterations++;

            uint256 newGasLeft = gasleft();

            if(gasLeft > newGasLeft) {
                gasUsed = gasUsed.add(gasLeft.sub(newGasLeft));
            }

            gasLeft = newGasLeft;
        }

        lastProcessedIndex = _lastProcessedIndex;

        return (iterations, claims, lastProcessedIndex);
    }

    function processAccount(address payable account, bool automatic) public onlyOwner returns (bool) {
        uint256 amount = _withdrawDividendOfUser(account);

        if(amount > 0) {
            lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
            return true;
        }

        return false;
    }
}
