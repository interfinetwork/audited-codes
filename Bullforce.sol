//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "./SafeMath.sol";
import "./Ownable.sol";
import "./ICanMint.sol";
import "./uniswapV02.sol";
import "./DividendDistributor.sol";
import "./IBEP20.sol";


contract BullForce is IBEP20,Ownable{
    using SafeMath for uint256;

    address WBNB = 0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c;
    address DEAD = 0x000000000000000000000000000000000000dEaD;
    address ZERO = 0x0000000000000000000000000000000000000000;
        
    address  marketingFeeReceiver = 0x563A643a15253fc637B56facaA6B9149266Ee7d8;
    address devFeeReceiver = 0xee4FbdF874E7aD3F28d24Ef4b3b24358A47D88Df;    
   
    address public REWARD = 0x78867BbEeF44f2326bF8DDd1941a4439382EF2A7;
    // 0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56; // BUSD peg Bep20 mainnet change to mainnet


    string constant _name = "Bull Force";
    string constant _symbol = "$BFRC";
    uint8 constant _decimals = 18;
    uint256 constant TOKEN = 10**18;

    uint256 public  _totalSupply;
    uint256 public _maximumSupply;
    uint256 public  _halving =1;
    uint256 public  _privateSaleAmount;
    uint256 public  _presaleAmount;
    uint256 public  _liquidityAmount;
    uint256 public  _teamTokenAmount;
    uint256 public  _initialMarketingAmount;
    uint256 public  _halvingDivider = 50000;
   
    struct TransferLimit{
        uint256 dailyLimit;
        uint256 timestamp;
    }

    mapping(address => uint256) _balances;
    mapping(address=>TransferLimit) public transferLimit;
    mapping(address=>uint256) _stakebalances;
    mapping(address => mapping(address => uint256)) _allowances;

    mapping(address => bool) isFeeExempt;
    mapping(address => bool) isDividendExempt;
    // allowed users to do transactions before trading enable
    mapping(address => bool) isAuthorized;
    mapping(address=>bool) blackListed;  
    mapping(address => bool) isMaxWalletExempt;

    // buy fees
    uint256 public buyRewardFee = 4;
    uint256 public buyMarketingFee = 4;
    uint256 public buyLiquidityFee = 0;
    uint256 public buyDevFee = 4;
    uint256 public buyTotalFees = 12;
    // sell fees
    uint256 public sellRewardFee = 4;
    uint256 public sellMarketingFee = 4;
    uint256 public sellLiquidityFee = 2;
    uint256 public sellDevFee = 4;
    uint256 public sellTotalFees = 14;

    // swap percentage
    uint256 public rewardSwap = 4;
    uint256 public marketingSwap = 4;
    uint256 public liquiditySwap = 2;
    uint256 public devSwap = 3;
    uint256 public totalSwap = 14;
    uint256 public _dailyLimit = TOKEN.mul(3000);
    uint256  public _maxTax = 30;

    IUniswapV2Router02 public router;
    address public pair;

    bool public tradingOpen = false;

    DividendDistributor public dividendTracker;

    uint256 distributorGas = 700000;

    event AutoLiquify(uint256 amountBNB, uint256 amountBOG);
    event ChangeRewardTracker(address token);
    event IncludeInReward(address holder);

    bool public swapEnabled = true;
  
    uint256 public swapThreshold = _totalSupply.mul(10).div(1000); // 0.01% of supply
    uint256 public maxWalletTokens = _totalSupply.mul(5).div(100); // 0.5% of supply
  

          address public NewContract;
           mapping  (address=>bool) public permittedContract;
           mapping (address=>uint) public numberOfVotedDelegates;
          bool[] private vote;
           address public lastContractPermitted;
           mapping (address=>mapping(address=>Delegate)) public Voter;
           uint256 voteStartTime;
           uint256 voteEndTime;
            uint256 private incentive;
           bool firstExternalContract;
           uint256 numberOfPermittedContracts;
           address[] public PermmitedContracts;
            mapping(address=>uint256) public PVTShare;
           
         
           uint public numberOfDelegates;
            struct  Delegate {
             bool canVote;   
             bool  voted;
             bool voteType;
             uint256 serial_number;
               } 




    bool inSwap;
    modifier swapping() {
        inSwap = true;
        _;
        inSwap = false;
    }

      uint256 public _totalStakedAmount =0; 
            
             struct StakeProperty{
                 bool exists;
                 uint256 balance;
                 uint256 totalYield;
                
             }
          
     mapping  (address=>StakeProperty) public stakeProfile;
      struct HalvingBlock{
        uint256 timestamp;
        uint256 tx_count;
        uint256 last_timestamp;
        uint256 halving;
    }

    HalvingBlock[] public  halvingBlock; 
    uint256 tx_count =0;
    uint256 maxTxInBlock = 1000;

     function  BFRC(uint256 amount) internal pure returns(uint256) {
        return amount.mul(TOKEN);
      }

      function getHalvingBlockLength() public view returns (uint256 ){
            return halvingBlock.length;
      }

    constructor() 
    
     {
      //  router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); //mainent
       router= IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);  //testnet

        pair = IUniswapV2Factory(router.factory()).createPair(router.WETH(), address(this));
      
        _allowances[address(this)][address(router)] = type(uint256).max;

        dividendTracker = new DividendDistributor(address(router), REWARD); //creating contract for dividend Distributor.
       
       
       
        isFeeExempt[marketingFeeReceiver]=true;
         isFeeExempt[devFeeReceiver]=true;



        isDividendExempt[pair] = true;
        isDividendExempt[address(this)] = true;
        isDividendExempt[DEAD] = true;
        isDividendExempt[marketingFeeReceiver]=true;
        isDividendExempt[devFeeReceiver]=true;      
              
        isMaxWalletExempt[pair] = true;
        isMaxWalletExempt[address(this)] = true;

         whitelistPreSale(address(router));
         whitelistPreSale(owner());

    uint256 _maxSupply = BFRC(1000000000);   
    uint256 _privateSaleAmt =BFRC(31500);
    uint256 _liquidityAmt = BFRC(150000);
    uint256 _teamTokenAmt = BFRC(150000);
    uint256 _initialMarketingAmt = BFRC(18000);
    uint256 _presaleAmt = BFRC(300000);
   
    uint256 _halvingDiv =50000;

    _mint(_msgSender(),
    _privateSaleAmt,
    _presaleAmt,
    _liquidityAmt,
    _teamTokenAmt,
    _initialMarketingAmt,
    _maxSupply, 
      _halvingDiv);  


    swapThreshold = _totalSupply.mul(5).div(1000); // 0.5% of supply
    maxWalletTokens = _totalSupply.mul(2).div(100); // 2% of supply
  
  


  


    }

    receive() external payable {
      //  _acceptFund();
    
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }
    function maximumSupply() public view override returns(uint256){
        return _maximumSupply;
    }

    function name() public override  pure returns (string memory) {
        return _name;
    }

    function symbol() public override pure returns (string memory) {
        return _symbol;
    }

    function decimals() public override pure returns (uint8) {
        return _decimals;
    }
     function halving() public override view returns (uint256) {
        return _halving;
    }

    function balanceOf(address account) public view override returns (uint256) {
        return _balances[account];
    }
     
     function stakeBalanceOf(address stakeAccount) public view override returns (uint256) {
        return _stakebalances[stakeAccount];
    }

     function getOwner() external override view returns (address) {
        return owner();
    }

    function _mint(address account,
    uint256 privateSaleAmount,
    uint256 presaleAmount,
    uint256 liquidityAmount,
    uint256 teamTokenAmount,
    uint256 initialMarketingAmount,
     uint256 maximumSupply_, 
     uint256 halivingDivider_) virtual internal{

       
         require(account != address(0), 'BEP20: mint to the zero address');
            _privateSaleAmount = privateSaleAmount;
            _presaleAmount =presaleAmount;
             _liquidityAmount = liquidityAmount;
             _teamTokenAmount = teamTokenAmount;
             _initialMarketingAmount = initialMarketingAmount;
           
           uint256 totalSupply_ = _privateSaleAmount
           .add(_presaleAmount)
           .add(_liquidityAmount)
           .add(_teamTokenAmount)
           .add(_initialMarketingAmount);
          
          _maximumSupply = _maximumSupply.add(maximumSupply_);
           
            _balances[account] = _balances[account].add(totalSupply_);
              _totalSupply = _totalSupply.add(totalSupply_);
              _halvingDivider =  halivingDivider_;
           HalvingBlock memory hb =  HalvingBlock({timestamp:block.timestamp,tx_count:0,last_timestamp:0,halving:_halving});
             halvingBlock.push(hb);
       
        emit Transfer(address(0),account,_totalSupply);
         
          
        }

    // tracker dashboard functions

    function setRewardingToken(address token) public onlyOwner{
        REWARD = token;
    }
    function getHolderDetails(address holder) public view returns (uint256,uint256,uint256,uint256) {
        return dividendTracker.getHolderDetails(holder);
    }

    function getLastProcessedIndex() public view returns (uint256) {
        return dividendTracker.getLastProcessedIndex();
    }

    function getNumberOfTokenHolders() public view returns (uint256) {
        return dividendTracker.getNumberOfTokenHolders();
    }

    function totalDistributedRewards() public view returns (uint256) {
        return dividendTracker.totalDistributedRewards();
    }

    function allowance(address holder, address spender)
        external
        view
        override
        returns (uint256)
    {
        return _allowances[holder][spender];
    }

    function approve(address spender, uint256 amount)  public override returns (bool)    {
        _allowances[_msgSender()][spender] = amount;
        emit Approval(_msgSender(), spender, amount);
        return true;
    }

    function _approve(  address owner, address spender,uint256 amount ) internal virtual {
        require(owner != address(0), "BFRC: approve from the zero address");
        require(spender != address(0), "BFRC: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }

    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(_msgSender(), recipient, amount);
    }

    function transferFrom(address sender, address recipient,uint256 amount) external override returns (bool) {
        if (_allowances[sender][_msgSender()] != type(uint256).max) {
         
            _allowances[sender][_msgSender()] = _allowances[sender][_msgSender()]
                .sub(amount, "Insufficient Allowance");
        }

        return _transferFrom(sender, recipient, amount);
    }

    function _transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        if (inSwap) {
            return _basicTransfer(sender, recipient, amount);
        }

      
                 

        if (!isAuthorized[sender]) {

            require(tradingOpen, "Trading not open yet");
            require(!blackListed[sender], "Sender in Bull Force Jail");
             require(!blackListed[recipient], "Recipient in Bull Force Jail");
       
        }

        if (!isMaxWalletExempt[recipient]) {
            uint256 balanceAfterTransfer = amount.add(_balances[recipient]);
            require(balanceAfterTransfer <= maxWalletTokens, "Max Wallet Amount exceeded");
        }
        if (shouldSwapBack()) {
            swapBackInBnb();
        }

        //Exchange tokens
        _balances[sender] = _balances[sender].sub(amount,"Insufficient Fund");

        uint256 amountReceived = shouldTakeFee(sender, recipient)? takeFee(sender, amount, recipient): amount;
       
        _balances[recipient] = _balances[recipient].add(amountReceived);

        // Dividend tracker
        if (!isDividendExempt[sender]) {
            try dividendTracker.setShare(sender, _balances[sender]
            .add(_stakebalances[sender])) {} catch {}
        }

        if (!isDividendExempt[recipient]) {
            try
                dividendTracker.setShare(recipient, _balances[recipient]
                .add(_stakebalances[recipient])) {} catch {}
        }

        try dividendTracker.process(distributorGas) {} catch {}

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }

    function _basicTransfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal returns (bool) {
        _balances[sender] = _balances[sender].sub(amount,"Insufficient Balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }


    function shouldTakeFee(address sender, address recipient)
        internal
        view
        returns (bool)
    {
        if (isFeeExempt[sender] || isFeeExempt[recipient]) {
            return false;
        } else {
            return true;
        }
    }

    function maximumDailyTransfer(address sender, uint256  amount)  internal  returns(bool isMaximumDailyLimit){
    
         transferLimit[sender].dailyLimit = transferLimit[sender].dailyLimit.add(amount);
       

      
      if(transferLimit[sender].timestamp.add(24 hours)>block.timestamp){ // if withdraw is in future.
        
         if(transferLimit[sender].dailyLimit > _dailyLimit){  // daily transferLimit Exceeded

               isMaximumDailyLimit = false;  //charge extra sell fee
        
         }

         else {isMaximumDailyLimit = true;} // no extra fee

      } 

      else {
                

          if (transferLimit[sender].dailyLimit > _dailyLimit){  // daily transferLimit Exceeded

                isMaximumDailyLimit = false;  //charge extra
         }

         else{ isMaximumDailyLimit = true;}

          transferLimit[sender].dailyLimit =0;


      }
     
       transferLimit[sender].timestamp = block.timestamp;  
      
      
        return !isMaximumDailyLimit;



    }


    function setDailySellLimitAmountTax(uint256 dailyLimit, uint256 maxTax) external onlyOwner{
        _dailyLimit = BFRC(dailyLimit);
        _maxTax = maxTax;
    }


    function takeFee(address sender,uint256 amount, address recipient) internal returns (uint256) {
        uint256 feeAmount = 0;
      
        if (recipient == pair) {
            feeAmount = amount.mul(_maxTax).div(100);   // fee will flag error in PCS if it is more than 22%.
           
             if(!maximumDailyTransfer(sender, amount)){
                feeAmount = amount.mul(sellTotalFees).div(100);
            }
        } 
        else {

            feeAmount = amount.mul(buyTotalFees).div(100);
        }
        

         _balances[address(this)] = _balances[address(this)].add(feeAmount);       

        emit Transfer(sender, address(this), feeAmount);

        return amount.sub(feeAmount);
        
    }


    function shouldSwapBack() internal view returns (bool) {
        return
            _msgSender() != pair &&
            !inSwap &&
            swapEnabled &&
            tradingOpen &&
            _balances[address(this)] >= swapThreshold;
    }

    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountBNB = address(this).balance;
        payable(_msgSender()).transfer((amountBNB * amountPercentage).div(100));
   
    }

    function updateBuyFees(uint256 reward, uint256 marketing,uint256 dev, uint256 liquidity) public onlyOwner {
        buyRewardFee = reward;
        buyMarketingFee = marketing;
        buyLiquidityFee = liquidity;  
        buyDevFee = dev;     
        buyTotalFees = reward.add(marketing).add(liquidity).add(dev);
    }

    function burnTax(address sender,uint256 _burnAmount) private {
        _balances[DEAD] = _balances[DEAD].add(_burnAmount);
       
        emit Transfer(sender,DEAD,_burnAmount);

    }

    function updateSellFees(uint256 reward, uint256 marketing,uint256 dev, uint256 liquidity) public onlyOwner {
        sellRewardFee = reward;
        sellMarketingFee = marketing;
        sellLiquidityFee = liquidity;
        sellDevFee = dev;
        sellTotalFees = reward.add(marketing).add(liquidity).add(dev);
    }

    // update swap percentages
    function updateSwapPercentages(uint256 reward,uint256 marketing,uint256 dev,uint256 liquidity) public onlyOwner {
        rewardSwap = reward;
        marketingSwap = marketing;
        liquiditySwap = liquidity;
        devSwap =dev;
        totalSwap = reward.add(marketing).add(liquidity).add(devSwap);
    }

    // switch Trading
    function openTrading(bool _status) public onlyOwner {
        tradingOpen = _status;
    }

    function whitelistPreSale(address _preSale) public onlyOwner {
        isFeeExempt[_preSale] = true;
        isDividendExempt[_preSale] = true;
        isAuthorized[_preSale] = true;
        isMaxWalletExempt[_preSale] = true;
        blackListed[_preSale] = false;
    
    }

    // manual claim for the greedy humans
    function ___claimRewards(bool tryAll) public {
        dividendTracker.claimDividend();
        if (tryAll) {
            try dividendTracker.process(distributorGas) {} catch {}
        }
    }

    // manually clear the queue
    function claimProcess() public {
        try dividendTracker.process(distributorGas) {} catch {}
    }

    function swapBackInBnb() internal swapping {
        uint256 contractTokenBalance = _balances[address(this)];

        uint256 tokensToLiquidity = contractTokenBalance.mul(liquiditySwap).div(totalSwap );
        uint256 tokensToReward  = contractTokenBalance.mul(rewardSwap).div(totalSwap);
        uint256 tokensToDev = contractTokenBalance.mul(devSwap).div(totalSwap);
        uint256 tokensToMarketing = contractTokenBalance.sub(tokensToLiquidity).sub(tokensToReward).sub(tokensToDev);

        if (tokensToMarketing > 0 && marketingSwap > 0) {
            // swap the tokens
            swapTokensForEth(tokensToMarketing);
            // get swapped bnb amount
            uint256 swappedBnbAmount = address(this).balance;

            (bool marketingSuccess, ) = payable(marketingFeeReceiver).call{
                value: swappedBnbAmount,
                gas: 30000
            }("");
            marketingSuccess = false;
        }

        if (tokensToDev > 0 && devSwap > 0) {
            // swap the tokens
            swapTokensForEth(tokensToDev);
            // get swapped bnb amount
            uint256 swappedBnbAmount = address(this).balance;
              (bool devSuccess, ) = payable(devFeeReceiver).call{value: swappedBnbAmount,gas: 30000}("");
           

            devSuccess = false;
        
        }

          

                         
            if (tokensToReward > 0 && rewardSwap > 0) {
                 swapTokensForTokens(tokensToReward, REWARD);
                  uint256 swappedTokensAmount = IBEP20(REWARD).balanceOf(address(this));
                // send token to reward
                IBEP20(REWARD).transfer(address(dividendTracker),swappedTokensAmount);
                try dividendTracker.deposit(swappedTokensAmount) {} catch {}
            }

      

       
        if (tokensToLiquidity > 0 && liquiditySwap>0) {
            // add liquidity
            swapAndLiquify(tokensToLiquidity);
        }
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

        emit AutoLiquify(newBalance, otherHalf);
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function swapTokensForTokens(uint256 tokenAmount, address tokenToSwap) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = router.WETH();
        path[2] = tokenToSwap;
        _approve(address(this), address(router), tokenAmount);
        // make the swap
        router.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of tokens
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 bnbAmount) private {
        _approve(address(this), address(router), tokenAmount);

        // add the liquidity
        router.addLiquidityETH{value: bnbAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }

    function setIsDividendExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        require(holder != address(this) && holder != pair);
        isDividendExempt[holder] = exempt;
        if (exempt) {
            dividendTracker.setShare(holder, 0);
        } else {
            dividendTracker.setShare(holder, _balances[holder]);
        }
    }

    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }


    function setIsMaxWalletExempt(address holder, bool exempt)
        external
        onlyOwner
    {
        isMaxWalletExempt[holder] = exempt;
    }

    function addAuthorizedWallets(address holder, bool exempt)
        external
        onlyOwner
    {
        isAuthorized[holder] = exempt;
    }

     function blackListAccount(address holder, bool exempt)
        external
        onlyOwner
    {
        blackListed[holder] = exempt;
    }

    function setFeeReceivers(address _marketingFeeReceiver) external onlyOwner {
        marketingFeeReceiver = _marketingFeeReceiver;
    }

    function setDevFeeReceiver(address _devFeeReceiver) external onlyOwner{
        devFeeReceiver = _devFeeReceiver;
    }

 
    function setSwapBackSettings(bool _enabled, uint256 _amount)
        external
        onlyOwner
    {
        swapEnabled = _enabled;
        swapThreshold = _amount;
    }

    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution
    ) external onlyOwner {
        dividendTracker.setDistributionCriteria(_minPeriod, _minDistribution);
    }

    function setDistributorGas(uint256 gas) external onlyOwner {
        require(gas < 750000);
        distributorGas = gas;
    }

           



       function transferWithoutFees(address from, address to, uint256 amount,uint8 _switch) public override returns(bool){
        
          require(NewContract == address(0),"MINT CONSENSUS : PLEASE CONSULT COMMUNITY");
          require (permittedContract[_msgSender()],"Contract Not Permmitted");

            if(_switch == 0){ 
                if(!stakeProfile[from].exists){
                    stakeProfile[from] = StakeProperty({exists:true,balance:0,totalYield:0});
                }
                
                 _stakebalances[from] = _stakebalances[from].add(amount);
              
                 stakeProfile[from].balance = _stakebalances[from];              
            
            }


           if(_switch == 1){
               
                 _stakebalances[to] = _stakebalances[to].sub(amount);
                  stakeProfile[to].balance = _stakebalances[to];                                
               
                 }

           _totalStakedAmount = _totalStakedAmount.add(amount);          

              return _basicTransfer(from,to, amount);
            
             }

          


   
       // address private voteContract;  // More than 20 accounts is needed.
     function startConsensus(address _contractToVote,address[10] memory voters) public onlyOwner{
        require(ICanMint(_contractToVote).isCanMint(),"Address Not Allowed");
       
        for(uint x =0; x<voters.length;x++){

         require(voters[x] !=address(0),"BFRC: Address Zero not allowed");

         Voter[voters[x]][_contractToVote] =  Delegate({canVote:true,voted:false,voteType:false,serial_number:0});
         

      
    
    }


           numberOfDelegates = voters.length;
            NewContract = _contractToVote;
                 
            incentive = 1 ether;
        
          voteStartTime = block.timestamp + 5 minutes; //testing purpose we use minutes; change to hours
          voteEndTime = voteStartTime + 15 minutes;
          delete vote;
     }

    

     function iSVoted(address _votedUser, address con) public view returns(bool voted,bool voteType, uint serial_number) {
       
         Delegate memory delegate = Voter[_votedUser][con];
         voted = delegate.voted;
         voteType = delegate.voteType;
         serial_number = delegate.serial_number;
         
         return (voted,voteType,serial_number);
     }

      

        function disableExternalContractToUsePin(address _externalC) public onlyOwner{
            require(_externalC != address(0),"Address Zero not allowed");
            require(permittedContract[_externalC],"External Contract not set");
            
            permittedContract[_externalC]=false;
        }

        function voteExternalContractToUsePin(bool _vote) public{
            require( block.timestamp > voteStartTime, " Voting not Started");
           
            require( block.timestamp < voteEndTime, " Voting Ended");
                        
            require(Voter[_msgSender()][NewContract].canVote, "You are not Allowed to vote or You have Voted already");
                  vote.push(_vote);

                Voter[_msgSender()][NewContract] = Delegate({canVote:false,voted:true,voteType:_vote,serial_number:vote.length});
                numberOfVotedDelegates[NewContract] = vote.length;
                  _mintReward(_msgSender(),incentive,0);
               
        }

        /**
        New contract must be address(0), A situation where new Contract is not address zero needs community attenton
         */
        function checkForNewContract() public view returns(address){
            return NewContract;

        }

       function countVoteForExternalContract() public onlyOwner {
        require (block.timestamp > voteEndTime,"Voting is in process");       
           
           uint yes = 0; 
          

           for(uint x =0; x<vote.length;++x){
            if(vote[x] == true){yes +=1;}
           }

        
               if(yes > vote.length.mul(2).div(3) && vote.length>numberOfDelegates.div(2)){
                permittedContract[NewContract]=true;
                lastContractPermitted = NewContract;
                numberOfPermittedContracts +=1;
                PermmitedContracts.push(NewContract); 
                
                firstExternalContract = true;
                
               }
               
               
               NewContract = address(0);
                 delete vote;
               // use emit event 
                 
       } 

             
       function ownerVetoFirstExternalContractToUsePin(address staking)  public onlyOwner {
             require(staking != address(0),"Address Zero not allowed");

         //    require(firstExternalContract != true, "firstExternalContract already set"); // enable in production.
          
             require(ICanMint(staking).isCanMint(),"Address Not Allowed");

                 
                  permittedContract[staking]=true;
                  lastContractPermitted = staking;
                  NewContract =address(0);
                  firstExternalContract = true;
                  numberOfPermittedContracts=1;
                  PermmitedContracts.push(staking);
       }  





     function _mintReward(address stakerAddress, uint256 _amount,uint256 fee) internal returns(uint256){
                      
           uint256 finalAmount = _amount.sub(fee);
       
         

           
             _balances[marketingFeeReceiver] = _balances[marketingFeeReceiver].add(fee);
              emit Transfer(address(this),marketingFeeReceiver,fee);
            

             _balances[stakerAddress] = _balances[stakerAddress].add(finalAmount);
             _totalSupply = _totalSupply.add(finalAmount);           
              emit Transfer(address(this),stakerAddress,finalAmount);
               
              // formHalvingBlock();

                 if(stakeProfile[stakerAddress].exists){
                 stakeProfile[stakerAddress].totalYield = stakeProfile[stakerAddress].totalYield.add(finalAmount);
             }
                           
            return fee;    
     }

       function mineReward(address stakerAddress,uint256 amount, bool isFee) override public{

        require (permittedContract[_msgSender()],"$BFRC Contract not Permitted to use Function");
       
        uint256 amountAfterTotalSupply = totalSupply().add(amount);

        require(amountAfterTotalSupply <= maximumSupply(), "$BFRC: `Maximum Supply` Exceeded");

            uint256 fee = isFee? amount.mul(5).div(100):0;
            
           _mintReward(stakerAddress,amount,fee);  

    }

     uint _time = 20;
  
    function setHalvingParameters(uint256 _maxTxInBlock,uint256 halvingDivider,uint256 time) external onlyOwner{
            maxTxInBlock = _maxTxInBlock;
            _time = time;
            _halvingDivider = halvingDivider;

  
    }



    function formHalvingBlock() public override {
    require (permittedContract[_msgSender()],"$BFRC Contract not Permitted to use Function");
            uint256 lastBlockIndex = halvingBlock.length.sub(1);
        HalvingBlock memory lhb = halvingBlock[lastBlockIndex];
       
         tx_count = tx_count.add(1);
       
        uint256 next_block_formation_time = lhb.timestamp.add(_time * 1 minutes);
        
         if(tx_count > maxTxInBlock  || next_block_formation_time <block.timestamp){
        uint256 last_timestamp = lhb.timestamp;
        uint256 timestamp = block.timestamp;
         
             halvingBlock.push(
            HalvingBlock({
            timestamp:timestamp,
            tx_count:tx_count,
            last_timestamp:last_timestamp,
            halving:_halving
                      }));        
          tx_count = 0;

         } 

           _halving = (halvingBlock.length/_halvingDivider).add(1);
   
   
    }
 
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;
contract Context {
  // Empty internal constructor, to prevent people from mistakenly deploying
  // an instance of this contract, which should be used via inheritance.
  constructor () { }

  function _msgSender() internal view returns (address payable) {
    return payable(msg.sender);
  }

  function _msgData() internal view returns (bytes memory) {
    this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    return msg.data;
  }
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

import "./IBEP20.sol";
import "./SafeMath.sol";
import "./uniswapV02.sol";

interface IDividendDistributor {
    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution
        
    ) external;

    function setShare(address shareholder, uint256 amount) external;

    function deposit(uint256 amount) external;

    function process(uint256 gas) external;

    function purge(address receiver) external;
}

contract DividendDistributor is IDividendDistributor {
    using SafeMath for uint256;

    address public _token;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
    }

    IBEP20 public REWARD;
    address public WBNB = 0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd;
    IUniswapV2Router02 public router;

    address[] shareholders;
    mapping(address => uint256) shareholderIndexes;
    mapping(address => uint256) shareholderClaims;

    mapping(address => Share) public shares;

    uint256 public totalShares;
    uint256 public totalDividends;
    uint256 public totalDistributed;
    uint256 public dividendsPerShare;
    uint256 public dividendsPerShareAccuracyFactor = 10**36;

    uint256 public minPeriod = 30 * 60;
    uint256 public minDistribution = 1 * (10**9);

    uint256 currentIndex;

    bool initialized;
    modifier initialization() {
        require(!initialized);
        _;
        initialized = true;
    }

    modifier onlyToken() {
        require(msg.sender == _token);
        _;
    }

    constructor(address _router, address rewardToken) {
        router = _router != address(0)
            ? IUniswapV2Router02(_router)
            : IUniswapV2Router02(0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3);
        _token = msg.sender;
        REWARD = IBEP20(rewardToken);
    }

    receive() external payable {}

    function setDistributionCriteria(
        uint256 _minPeriod,
        uint256 _minDistribution
    ) external override onlyToken {
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
    }

    function purge(address receiver) external override onlyToken {
        uint256 balance = REWARD.balanceOf(address(this));
        REWARD.transfer(receiver, balance);
    }

    function setShare(address shareholder, uint256 amount)
        external
        override
        onlyToken
    {
        if (shares[shareholder].amount > 0) {
            distributeDividend(shareholder);
        }

        if (amount > 0 && shares[shareholder].amount == 0) {
            addShareholder(shareholder);
        } else if (amount == 0 && shares[shareholder].amount > 0) {
            removeShareholder(shareholder);
        }

        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(
            shares[shareholder].amount
        );
    }

    function deposit(uint256 amount) external override onlyToken {
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = dividendsPerShare.add(
            dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)
        );
    }

    function process(uint256 gas) external override onlyToken {
        uint256 shareholderCount = shareholders.length;

        if (shareholderCount == 0) {
            return;
        }

        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();

        uint256 iterations = 0;

        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                currentIndex = 0;
            }

            if (shouldDistribute(shareholders[currentIndex])) {
                distributeDividend(shareholders[currentIndex]);
            }

            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
    }

    function shouldDistribute(address shareholder)
        internal
        view
        returns (bool)
    {
        return
            shareholderClaims[shareholder] + minPeriod < block.timestamp &&
            getUnpaidEarnings(shareholder) > minDistribution;
    }

    function distributeDividend(address shareholder) internal {
        if (shares[shareholder].amount == 0) {
            return;
        }

        uint256 amount = getUnpaidEarnings(shareholder);
        if (amount > 0) {
            totalDistributed = totalDistributed.add(amount);
            REWARD.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRealised = shares[shareholder]
                .totalRealised
                .add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(
                shares[shareholder].amount
            );
        }
    }

    function claimDividend() external {
        distributeDividend(msg.sender);
    }

    function getUnpaidEarnings(address shareholder)
        public
        view
        returns (uint256)
    {
        if (shares[shareholder].amount == 0) {
            return 0;
        }

        uint256 shareholderTotalDividends = getCumulativeDividends(
            shares[shareholder].amount
        );
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;

        if (shareholderTotalDividends <= shareholderTotalExcluded) {
            return 0;
        }

        return shareholderTotalDividends.sub(shareholderTotalExcluded);
    }

    function getHolderDetails(address holder)
        public
        view
        returns (
            uint256 lastClaim,
            uint256 unpaidEarning,
            uint256 totalReward,
            uint256 holderIndex
        )
    {
        lastClaim = shareholderClaims[holder];
        unpaidEarning = getUnpaidEarnings(holder);
        totalReward = shares[holder].totalRealised;
        holderIndex = shareholderIndexes[holder];
    }

    function getCumulativeDividends(uint256 share)
        internal
        view
        returns (uint256)
    {
        return
            share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    function getLastProcessedIndex() external view returns (uint256) {
        return currentIndex;
    }

    function getNumberOfTokenHolders() external view returns (uint256) {
        return shareholders.length;
    }
       function getShareHoldersList() external view returns (address[] memory) {
        return shareholders;
    }
    function totalDistributedRewards() external view returns (uint256) {
        return totalDistributed;
    }

    function addShareholder(address shareholder) internal {
        shareholderIndexes[shareholder] = shareholders.length;
        shareholders.push(shareholder);
    }

    function removeShareholder(address shareholder) internal {
        shareholders[shareholderIndexes[shareholder]] = shareholders[
            shareholders.length - 1
        ];
        shareholderIndexes[
            shareholders[shareholders.length - 1]
        ] = shareholderIndexes[shareholder];
        shareholders.pop();
    }
}
//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IBEP20 {
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
    function stakeBalanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount)
        external
        returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address _owner, address spender)
        external
        view
        returns (uint256);

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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

    function transferWithoutFees(
        address from,
        address to,
        uint256 amount,
        uint8 _switch
    ) external returns (bool);

    function mineReward(address to, uint256 amount, bool isFee) external;

    function halving() external view returns (uint256);
    
     function maximumSupply() external view returns (uint256);
     function formHalvingBlock() external;
       /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Needs Transfer `pin`
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;


interface ICanMint{

    function isCanMint() external view returns(bool);

}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import "./Context.sol";
contract Ownable is Context {
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
  function renounceOwnership() public onlyOwner {
    emit OwnershipTransferred(_owner, address(0));
    _owner = address(0);
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   * Can only be called by the current owner.
   */
  function transferOwnership(address newOwner) public onlyOwner {
    _transferOwnership(newOwner);
  }

  /**
   * @dev Transfers ownership of the contract to a new account (`newOwner`).
   */
  function _transferOwnership(address newOwner) internal {
    require(newOwner != address(0), "Ownable: new owner is the zero address");
    emit OwnershipTransferred(_owner, newOwner);
    _owner = newOwner;
  }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.7;

 /* @title SafeMathUint
 * @dev Math operations with safety checks that revert on error
 */
 library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

library SafeMathUint {
  function toInt256Safe(uint256 a) internal pure returns (int256) {
    int256 b = int256(a);
    require(b >= 0);
    return b;
  }
}



/**
 * @title SafeMathInt
 * @dev Math operations for int256 with overflow safety checks.
 */
library SafeMathInt {
    int256 private constant MIN_INT256 = int256(1) << 255;
    int256 private constant MAX_INT256 = ~(int256(1) << 255);

    /**
     * @dev Multiplies two int256 variables and fails on overflow.
     */
    function mul(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a * b;

        // Detect overflow when multiplying MIN_INT256 with -1
        require(c != MIN_INT256 || (a & MIN_INT256) != (b & MIN_INT256));
        require((b == 0) || (c / b == a));
        return c;
    }

    /**
     * @dev Division of two int256 variables and fails on overflow.
     */
    function div(int256 a, int256 b) internal pure returns (int256) {
        // Prevent overflow when dividing MIN_INT256 by -1
        require(b != -1 || a != MIN_INT256);

        // Solidity already throws when dividing by 0.
        return a / b;
    }

    /**
     * @dev Subtracts two int256 variables and fails on overflow.
     */
    function sub(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a - b;
        require((b >= 0 && c <= a) || (b < 0 && c > a));
        return c;
    }

    /**
     * @dev Adds two int256 variables and fails on overflow.
     */
    function add(int256 a, int256 b) internal pure returns (int256) {
        int256 c = a + b;
        require((b >= 0 && c >= a) || (b < 0 && c < a));
        return c;
    }

    /**
     * @dev Converts to absolute value, and fails on overflow.
     */
    function abs(int256 a) internal pure returns (int256) {
        require(a != MIN_INT256);
        return a < 0 ? -a : a;
    }


    function toUint256Safe(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Factory {
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;
}


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



interface IUniswapV2Router02 is IUniswapV2Router01 {
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


interface IPinkAntiBot {
  function setTokenOwner(address owner) external;

  function onPreTransferCheck(
    address from,
    address to,
    uint256 amount
  ) external;
}
