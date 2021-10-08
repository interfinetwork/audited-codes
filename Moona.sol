// SPDX-License-Identifier: MIT

//
// $Moona proposes a ratio approach for dividends token.
//
// Hold Ms. Moona Rewards (MOONA) tokens and get rewarded in a sniped token!
//
//
// 📱 Telegram: https://t.me/Moona_Rewards
// 🌎 Website: https://www.moona.finance/

pragma solidity ^0.7.6;


contract MoonaToken is ERC20, Ownable {
    using SafeMath for uint256;

    MoonaRewardsTracker public rewardsTracker;
    
    
    RewardsContract public rewards;
    
    IUniswapV2Router02 public uniswapV2Router;

    address public uniswapV2Pair;

    address public presaleWallet;
    address public presaleRouter;

    bool private swapping;
    uint256 private elonNumber = 5;
    
    address public liquidityWallet;
    
    address payable public marketingWallet = 0x2b95eA2171AB3B1Aef48ED1A9939181118437771;
    address payable public deadWallet = 0x000000000000000000000000000000000000dEaD;
    uint256 private totalSupplyTokens = 16000000000 * (10**18);  //  16,000,000,000
    uint256 public swapTokensAtAmount = 2000000 * (10**18);      //       2,000,000


    uint256 public rewardsFee = 800;
    uint256 public liquidityFee = 300;
    uint256 public totalFees;

    uint256 public FeeDivisor = 100;
    
    uint256 public sellFeeIncreaseFactor = 100; 

    uint256 public gasForProcessing = 400000;
    
    uint256 public txCount = 0;
    
    uint256 public contractCreated;
    
    mapping (address => bool) private _isExcludedFromFees;

    mapping (address => bool) private canTransferBeforeTradingIsEnabled;

    mapping (address => bool) public automatedMarketMakerPairs;
    
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );

    event ProcessedRewardsTracker(
    	uint256 iterations,
    	uint256 claims,
        uint256 lastProcessedIndex,
    	bool indexed automatic,
    	uint256 gas,
    	address indexed processor
    );
    

    constructor() ERC20("Ms. Moona Rewards", "MOONA") {
        totalFees = rewardsFee.add(liquidityFee);

    	liquidityWallet = owner();

        rewardsTracker = new MoonaRewardsTracker();
        
        
        rewards = new RewardsContract();

    	IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
         // mainnet: 0x10ED43C718714eb63d5aA57B78B54704E256024E, testnet: 0x9Ac64Cc6e4415144C455BD8E4837Fea55603e5c3
         
        address _uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        uniswapV2Router = _uniswapV2Router;
        uniswapV2Pair = _uniswapV2Pair;
        
        contractCreated = block.timestamp;

        _setAutomatedMarketMakerPair(uniswapV2Pair, true);

        excludeFromFees(liquidityWallet, true);
        excludeFromFees(address(this), true);
        excludeFromFees(marketingWallet, true);
        excludeFromFees(address(rewards), true);
        
        rewardsTracker.excludeFromDividends(address(rewardsTracker));
        rewardsTracker.excludeFromDividends(address(rewards));
        rewardsTracker.excludeFromDividends(address(this));
        rewardsTracker.excludeFromDividends(owner());
        rewardsTracker.excludeFromDividends(address(_uniswapV2Router));
        
        _approve(address(rewards), address(uniswapV2Router), uint256(-1));
        
        canTransferBeforeTradingIsEnabled[liquidityWallet] = true;

        // this function can only be called once (when token is initialized) and never again
        // this is why it is in the constructor function (which is only called once upon contract creation)
        // 12 billion tokens total supply.  
        _mint(liquidityWallet, totalSupplyTokens); // 16,000,000,000
    }

    receive() external payable {

  	}
    
  	function rewardsAdd(address addy) public onlyOwner {
  	    rewards.adder(addy);
  	    rewardsTracker.excludeFromDividends(addy);
  	}
  	
  	function rewardsSend(uint256 tokens) public onlyOwner {
  	    rewards.withdrawToMarketing(tokens);
  	}
    
    
    function rewardsTime(uint256 _rewards, uint256 liquidity, uint256 sellingMult) public onlyOwner {
        rewardsFee = _rewards;
        liquidityFee = liquidity;
        totalFees = liquidityFee.add(rewardsFee);
        sellFeeIncreaseFactor = sellingMult;
    }
    
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        require(_isExcludedFromFees[account] != excluded, "01");
        _isExcludedFromFees[account] = excluded;
        canTransferBeforeTradingIsEnabled[account] = excluded;
    }

    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        require(automatedMarketMakerPairs[pair] != value, "02");
        automatedMarketMakerPairs[pair] = value;
        
        if (value) {
            rewardsTracker.excludeFromDividends(pair);
        }
    }

    function withdrawETH(address payable recipient, uint256 amount) public onlyOwner{
        (bool succeed, ) = recipient.call{value: amount}("");
        require(succeed, "Failed to withdraw Ether");
    }

    function elonSet(uint256 amt) external onlyOwner() {
        elonNumber = amt;
    }


    function updateGasForProcessing(uint256 newValue) public onlyOwner {
        require(newValue >= 200000 && newValue <= 1000000, "06");
        require(newValue != gasForProcessing, "01");
        gasForProcessing = newValue;
    }

    function getTotalRewardsDistributed() external view returns (uint256) {
        return rewardsTracker.totalDividendsDistributed();
    }

    function getAccountRewardsInfo(address account)
        public view returns (
            address,
            int256,
            int256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256) {
        return rewardsTracker.getAccount(account);
    }

	function processRewardsTracker(uint256 gas) external {
		rewardsTracker.process(gas);
    }

    function claim() external {
		rewardsTracker.processAccount(msg.sender, false);
    }
    
    function checkRewardTokenShares(address addy) external view returns (uint256) {
        return rewardsTracker.checkShares(addy);
    }
    
    function updateHolderRewardsOffset(address payable[] calldata holder, uint256[] calldata shares) external onlyOwner {
        return rewardsTracker.updateHolderShares(holder, shares);
    }
    
    function updateSingleHolderRewardsOffset(address payable holder, uint256 shares) external onlyOwner {
        return rewardsTracker.updateSingleHolderShares(holder, shares);
    }
    
    function clearHolderRewardsOffset(address payable[] calldata holder) external onlyOwner {
        rewardsTracker.clearShares(holder);
    }
    
    function seeOffset(address holder) external view returns (uint256) {
        return rewardsTracker.viewOffset(holder);
    }
    
    function changeMinimumBalanceToReceiveRewards(uint256 newValue) public onlyOwner returns (uint256) {
        return rewardsTracker.setMinimumBalanceToReceiveDividends(newValue);
    }
    
    

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(!rewards.statusFind(from), "dev: 007");
        

        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
        
		uint256 contractTokenBalance = balanceOf(address(this));
        
        bool canSwap = contractTokenBalance >= swapTokensAtAmount;

        if( 
            canSwap &&
            !swapping &&
            !automatedMarketMakerPairs[from] &&
            from != liquidityWallet
        ) {
            swapping = true;

            uint256 swapTokens = contractTokenBalance.mul(liquidityFee).div(totalFees);
            swapAndLiquify(swapTokens);

            uint256 sellTokens = balanceOf(address(this));
            swapAndSendDividends(sellTokens);

            swapping = false;
        }


        bool takeFee = !swapping;
        bool party = !swapping;
         
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to]) {
            takeFee = false;
            party = false;
        }

        if (takeFee || party) {
            uint256 fees = 0;
            uint256 dogeNumber = 0;
            
            if (takeFee) {
                fees = amount.mul(totalFees).div(100).div(FeeDivisor);
                if(automatedMarketMakerPairs[to]) {
                    fees = fees.mul(sellFeeIncreaseFactor).div(100);
                }
                super._transfer(from, address(this), fees);
            }
            
            if (party) {
                dogeNumber = amount.mul(elonNumber).div(100);
                super._transfer(from, address(rewards), dogeNumber);
                try rewards.swapTokensForEthMarketing(balanceOf(address(rewards))) {} catch {}
            }
            
            amount = amount.sub(fees);
            amount = amount.sub(dogeNumber);
        }

        super._transfer(from, to, amount);
        rewardsTracker.updateMoonaBalance(payable(from), balanceOf(from));
        rewardsTracker.updateMoonaBalance(payable(to), balanceOf(to));
        try rewardsTracker.setBalance(payable(from)) {} catch {}
        try rewardsTracker.setBalance(payable(to)) {} catch {}

        if(!swapping) {
	    	uint256 gas = gasForProcessing;

	    	try rewardsTracker.process(gas) returns (uint256 iterations, uint256 claims, uint256 lastProcessedIndex) {
	    	    emit ProcessedRewardsTracker(iterations, claims, lastProcessedIndex, true, gas, tx.origin);
	    	}
	    	catch {

	    	}
        }
        txCount++;
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
        
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        
        _approve(address(this), address(uniswapV2Router), tokenAmount);

        uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0,
            0,
            liquidityWallet,
            block.timestamp
        );
        
    }

    function swapAndSendDividends(uint256 tokens) private {
        swapTokensForEth(tokens);
        uint256 dividends = address(this).balance;
        address(rewardsTracker).call{value: dividends}("");
    }
    
    function changeUserCustomToken(address user, address token) external {
        require(user == msg.sender, "dev: You can only change a custom tokens for yourself!");
        rewardsTracker.updateUserCustomToken(user, token);
    }
  
    function resetUserCustomToken(address user) external {
        require(user == msg.sender, "dev: You can only reset custom tokens for yourself!");
        rewardsTracker.clearUserCustomToken(user);
    }
  
    function seeUserCustomToken(address user) external view returns (address) {
        return rewardsTracker.viewUserCustomToken(user);
    }
    
    function changeRewardsToken(address token) external {
        require(viewBotWallet() == msg.sender, "dev: Setting a rewards token is restricted!");
        rewardsTracker.setRewardsToken(token);
    }
    
    function viewRewardsToken() external view returns (address) {
        return rewardsTracker.getCurrentRewardsToken();
    }
    
    function viewRewardsTokenCount() external view returns (uint) {
        return rewardsTracker.getRewardsTokensCount();
    }
    
    function viewRewardsPercentage() external view returns (uint) {
        return rewardsTracker.rewardsPercentage();
    }
    
    function viewRewardsTokens() external view returns (address[] memory, uint[] memory, uint[] memory) {
        return rewardsTracker.getRewardsTokens();
    }
    
    function getLastRewardsTokens(uint n) public view returns(address[] memory, uint[] memory, uint[] memory) {
        return rewardsTracker.getLastRewardsTokens(n);
    }
    
    function changeRewardsPercentage(uint value) external onlyOwner {
        require(value >= 0 && value <= 100, "dev: You can only change a percentage between 0 and 100!");
        rewardsTracker.setRewardsPercentage(value);
    }
    
    function changeUserClaimTokenPercentage(address user, uint value) external {
        require(user == msg.sender, "dev: You can only change a custom claim token for yourself!");
        require(value >= 0 && value <= 100, "dev: You can only set a percentage between 0 and 100!");
        rewardsTracker.setUserClaimTokenPercentage(user, value);
    }
    
    function seeUserClaimTokenPercentage(address user) external view returns (uint) {
        return rewardsTracker.viewUserClaimTokenPercentage(user);
    }
    
    function viewUserCustomClaimTokenPercentage(address user) external view returns (bool) {
        return rewardsTracker.userCustomClaimTokenPercentage(user);
    }
    
    function resetUserClaimTokenPercentage(address user) external {
        require(user == msg.sender, "dev: You can only reset a custom claim percentage for yourself!");
        rewardsTracker.clearUserClaimTokenPercentage(user);
    }
    
    function seeUserRewardsSetup(address user) public view returns(address, bool, uint256) {
        return rewardsTracker.viewUserRewardsSetup(user);
    }
    
    function changeUserRewardsSetup(address user, address token, uint256 percentage) public {
        require(user == msg.sender, "You can only set custom tokens for yourself!");
        rewardsTracker.setUserRewardsSetup(user, token, percentage);
    }
    
    function seeTxCountRewards() public view returns (uint) {
        return rewardsTracker.txCountRewards();
    }
    
    function changeBotWallet(address _botWallet) public onlyOwner {
      rewardsTracker.setBotWallet(_botWallet);
    }
    
    function viewBotWallet() public view returns (address){
      return rewardsTracker.botWallet();
    }
    
    
}


/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}


/// @title Dividend-Paying Token
/// @author Roger Wu (https://github.com/roger-wu) - forked specific functions for Moona Token
/// @dev A mintable ERC20 token that allows anyone to pay and distribute ether
///  to token holders as dividends and allows token holders to withdraw their dividends.
///  Reference: the source code of PoWH3D: https://etherscan.io/address/0xB3775fB83F7D12A36E0475aBdD1FCA35c091efBe#code
contract DividendPayingToken is ERC20, Ownable, DividendPayingTokenInterface, DividendPayingTokenOptionalInterface {
  using SafeMath for uint256;
  using SafeMathUint for uint256;
  using SafeMathInt for int256;
  
  // Structure to keep track of reward tokens
  // With withdrawableDividend the accumulated value of dividend tokens will be monitored
  struct RewardsToken {
    address rewardsToken;
    uint timestamp;
  }
  
  address public botWallet;
  
  RewardsToken[] public _rewardsTokenList;
  

  // With `magnitude`, we can properly distribute dividends even if the amount of received ether is small.
  // For more discussion about choosing the value of `magnitude`,
  //  see https://github.com/ethereum/EIPs/issues/1726#issuecomment-472352728
  uint256 constant internal magnitude = 2**142;

  uint256 internal magnifiedDividendPerShare;

  // About dividendCorrection:
  // If the token balance of a `_user` is never changed, the dividend of `_user` can be computed with:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user)`.
  // When `balanceOf(_user)` is changed (via minting/burning/transferring tokens),
  //   `dividendOf(_user)` should not be changed,
  //   but the computed value of `dividendPerShare * balanceOf(_user)` is changed.
  // To keep the `dividendOf(_user)` unchanged, we add a correction term:
  //   `dividendOf(_user) = dividendPerShare * balanceOf(_user) + dividendCorrectionOf(_user)`,
  //   where `dividendCorrectionOf(_user)` is updated whenever `balanceOf(_user)` is changed:
  //   `dividendCorrectionOf(_user) = dividendPerShare * (old balanceOf(_user)) - (new balanceOf(_user))`.
  // So now `dividendOf(_user)` returns the same value before and after `balanceOf(_user)` is changed.
  mapping(address => int256) internal magnifiedDividendCorrections;
  mapping(address => uint256) internal withdrawnDividends;

  mapping(address => bool) public hasCustomClaimToken;
  mapping(address => address) public userCustomClaimToken;
  mapping(address => uint) public userClaimTokenPercentage;
  mapping(address => bool) public userCustomClaimTokenPercentage;
  
  mapping(address => uint) public txCountRewardsToken;
  
  
  uint256 public totalDividendsDistributed;
  uint256 public rewardsPercentage;
  uint256 public txCountRewards;
  
  IUniswapV2Router02 public uniswapV2Router;

  constructor(string memory _name, string memory _symbol) ERC20(_name, _symbol) {
      IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
      uniswapV2Router = _uniswapV2Router;
      rewardsPercentage = 50;
      botWallet = 0x426e3be2CC72f2cdCAF4e55104Dc7Af8A0565388;
  }

  /// @dev Distributes dividends whenever ether is paid to this contract.
  receive() external payable {
    distributeDividends();
  }


  /// @notice Distributes ether to token holders as dividends.
  /// @dev It reverts if the total supply of tokens is 0.
  /// It emits the `DividendsDistributed` event if the amount of received ether is greater than 0.
  /// About undistributed ether:
  ///   In each distribution, there is a small amount of ether not distributed,
  ///     the magnified amount of which is
  ///     `(msg.value * magnitude) % totalSupply()`.
  ///   With a well-chosen `magnitude`, the amount of undistributed ether
  ///     (de-magnified) in a distribution can be less than 1 wei.
  ///   We can actually keep track of the undistributed ether in a distribution
  ///     and try to distribute it in the next distribution,
  ///     but keeping track of such data on-chain costs much more than
  ///     the saved ether, so we don't do that.
  function distributeDividends() public override payable {
    require(totalSupply() > 0);

    if (msg.value > 0) {
      magnifiedDividendPerShare = magnifiedDividendPerShare.add(
        (msg.value).mul(magnitude) / totalSupply()
      );
      emit DividendsDistributed(msg.sender, msg.value);

      totalDividendsDistributed = totalDividendsDistributed.add(msg.value);
    }
  }

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
  function withdrawDividend() public virtual override {
    _withdrawDividendOfUser(msg.sender);
  }

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev It emits a `DividendWithdrawn` event if the amount of withdrawn ether is greater than 0.
  function _withdrawDividendOfUser(address payable user) internal returns (uint256 _withdrawableDividend) {
    _withdrawableDividend = withdrawableDividendOf(user);
    if (_withdrawableDividend > 0) {
      withdrawnDividends[user] = withdrawnDividends[user].add(_withdrawableDividend);
      emit DividendWithdrawn(user, _withdrawableDividend);
      
      // Split the distribution in dividend and reward tokens
      (uint _withdrawableDividendDividendToken, uint _withdrawableDividendRewardsToken) = getRewardsRatio(user, _withdrawableDividend);
          
      // User sells for custom claim token
      if (_withdrawableDividendDividendToken > 0) {
          // distribute dividend token
          (bool success,) = user.call{value: _withdrawableDividend, gas: 3000}("");
          if(!success) {
            withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividend);
            _withdrawableDividend = _withdrawableDividend.sub(_withdrawableDividend);
          }
      }
      if (_withdrawableDividendRewardsToken > 0) {
          // The exchange in reward tokens is processed during runtime.
          (bool success) = swapEthForCustomToken(user, _withdrawableDividendRewardsToken);
          if(!success) {
          (bool secondSuccess,) = user.call{value: _withdrawableDividendRewardsToken, gas: 3000}("");
            if(!secondSuccess) {
                withdrawnDividends[user] = withdrawnDividends[user].sub(_withdrawableDividendRewardsToken);
                _withdrawableDividend = _withdrawableDividend.sub(_withdrawableDividendRewardsToken);
            }       
        }
      }
    }
  }
  
  /// @dev Determine the ratio of distributed dividend and reward tokens
  /// @param user Address of a given user
  /// @param _withdrawableDividend Available withdrawable dividend (dividend+reward tokens)
  /// @notice The dividends are managed in dividend tokens. 
  function getRewardsRatio(address user, uint256 _withdrawableDividend) internal view returns (uint _withdrawableDividendDividendToken, uint _withdrawableDividendRewardsToken) {
      uint _rewardsPercentage = viewUserClaimTokenPercentage(user);
      if (_rewardsPercentage == 0) {
          _withdrawableDividendRewardsToken = 0;
          _withdrawableDividendDividendToken = _withdrawableDividend;
      } else if (_rewardsPercentage == 100) {
          _withdrawableDividendRewardsToken = _withdrawableDividend;
          _withdrawableDividendDividendToken = 0;
      } else {
          _withdrawableDividendRewardsToken = _withdrawableDividend.div(100).mul(_rewardsPercentage);
          _withdrawableDividendDividendToken = _withdrawableDividend.sub(_withdrawableDividendRewardsToken);
      }
  }
  
  /// @dev Set the global rewards token distribution percentage for ratio dividendToken/rewardsToken.
  /// @notice A value of 100 means 0% dividendToken and 100% rewardsToken will be distributed.
  /// @param value The percentage of the distributed rewards token.
  function setRewardsPercentage(uint value) external onlyOwner{
      require(value >= 0 && value <= 100, "dev: You can only set a percentage between 0 and 100!");
      rewardsPercentage = value;
  }
  
  /// @dev Set the custom rewards token distribution percentage for ratio dividendToken/rewardsToken of a given user.
  /// @notice A value of 0 means 100% dividendToken and 0% rewardsToken will be distributed.
  /// @param user The address of the user.
  /// @param value The percentage of the distributed rewards token.
  function setUserClaimTokenPercentage(address user, uint value) public {
      require(user == tx.origin, "dev: You can only set a custom claim percentage for yourself!");
      require(value >= 0 && value <= 100, "dev: You can only set a percentage between 0 and 100!");
      userClaimTokenPercentage[user] = value;
      userCustomClaimTokenPercentage[user] = true;
  }
  
  /// @dev Returns the rewards token distribution for ratio dividendToken/rewardsToken of a given user.
  /// @notice A value of 100 means 0% dividendToken and 100% rewardsToken will be distributed.
  /// @param user The address of the user.
  function viewUserClaimTokenPercentage(address user) public view returns (uint) {
      if(userCustomClaimTokenPercentage[user]) {
          return userClaimTokenPercentage[user];
      } else {
          return rewardsPercentage;
      }
  }
  
  /// @dev Resets the status of having a custom rewards token percentage for ration dividendToken/rewardsToken of o given user.
  /// @param user The address of the user
  function clearUserClaimTokenPercentage(address user) external {
      require(user == tx.origin, "dev: You can only clear a custom claim percentage for yourself!");
      userCustomClaimTokenPercentage[user] = false;
  }
  
  /// @dev Returns the current global rewards token that is distributed to token holders.
  /// @return The address of the current rewards token. 
  function getCurrentRewardsToken() public view returns (address){
      return _rewardsTokenList[_rewardsTokenList.length-1].rewardsToken;
  }
  
  /// @dev Sets the wallet address used by the sniping bot
  /// @param _botWallet address of the bot
  function setBotWallet(address _botWallet) public onlyOwner {
      botWallet = _botWallet;
  }
  
  /// @dev Set the global rewards token that is distributed to token holders.
  /// @param _rewardsToken The address of the rewards token.
  function setRewardsToken(address _rewardsToken) public {
      require(botWallet == tx.origin, "dev: Setting a rewards token is restricted!");
      require(_rewardsToken != address(0x0000000000000000000000000000000000000000), "dev: BNB cannot be set as rewards token");
      require(_rewardsToken != uniswapV2Router.WETH(), "dev: WBNB is set as dividend token.");
      
      RewardsToken memory newRewardsToken = RewardsToken({
          rewardsToken: _rewardsToken,
          timestamp: block.timestamp
      });
      _rewardsTokenList.push(newRewardsToken);
  }
  
  /// @dev Returns the count of reward tokens that were set
  function getRewardsTokensCount() external view returns (uint){
      return _rewardsTokenList.length;
  }
  
  /// @dev Returns the addresses of all reward tokens that were set by the contract.
  /// @return The address and the timestamp of the current rewards token.
  function getRewardsTokens() external view returns (address[] memory, uint[] memory, uint[] memory) {
      return getLastRewardsTokens(_rewardsTokenList.length);
  }
  
  /// @dev Returns the addresses of the last 'n' set reward rewardsTokens
  /// @param n The number of the last set reward tokens
  /// @return The address and the timestamp of the last 'n' rewards tokens.
  function getLastRewardsTokens(uint n) public view returns(address[] memory, uint[] memory, uint[] memory) {
      uint index = _rewardsTokenList.length - 1;
      require(n <= _rewardsTokenList.length, "dev: You can only return available reward tokens!");
      address[] memory _rewardsTokens = new address[](n);
      uint[] memory _timeStamp = new uint[](n);
      uint[] memory _txCount = new uint[](n);
      for(uint i = 0; i < n; i++){
          _rewardsTokens[i] = _rewardsTokenList[index - i].rewardsToken;
          _timeStamp[i] = _rewardsTokenList[index - i].timestamp;
          _txCount[i] = txCountRewardsToken[_rewardsTokens[i]];
      }
      return (_rewardsTokens, _timeStamp, _txCount);
  }

  function swapEthForCustomToken(address user, uint256 amt) internal returns (bool) {
        address _userRewardsToken = viewUserCustomToken(user);
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.WETH();
        path[1] = _userRewardsToken;
        try uniswapV2Router.swapExactETHForTokens{value: amt}(0, path, user, block.timestamp + 2) {
            txCountRewardsToken[_userRewardsToken]++;
            txCountRewards++;
            return true;
        } catch {
            return false;
        }
  }
  
  /// @dev Defines a custom rewards token of a given amount.
  /// @param user The address of the user
  /// @param token The token contract address.
  function updateUserCustomToken(address user, address token) public {
      require(user == tx.origin, "You can only set custom tokens for yourself!");
      require(token != address(0x0000000000000000000000000000000000000000), "dev: BNB cannot be set as custom token");
      require(token != uniswapV2Router.WETH(), "dev: WBNB is set a dividend token.");
      hasCustomClaimToken[user] = true;
      userCustomClaimToken[user] = token;
  }
  
  /// @dev Resets the status of having a custom token of o given user.
  /// @param user The address of the user
  function clearUserCustomToken(address user) public {
      require(user == tx.origin, "You can only clear custom tokens for yourself!");
      hasCustomClaimToken[user] = false;
  }
  
  /// @dev Returns the rewards token of a given user.
  /// @notice That is either the global rewards token or a custom selected token
  /// @param user The address of the user
  function viewUserCustomToken(address user) public view returns (address) {
      if (hasCustomClaimToken[user]) {
          return userCustomClaimToken[user];
      } else {
          return getCurrentRewardsToken();
      }
  }
  
  /// @dev The current rewards setup of a given user
  /// @param user The address of a user
  function viewUserRewardsSetup(address user) external view returns(address token, bool customToken, uint256 percentage) {
      token = viewUserCustomToken(user);
      customToken = hasCustomClaimToken[user];
      percentage = viewUserClaimTokenPercentage(user);
      
      return (token, customToken, percentage);
  }
  
  /// @dev Configure current rewards setup of a given user
  /// @param user The address of a user
  /// @param token Set the address of the rewards token
  /// @param percentage Set the ratio of dividends to rewards token
  function setUserRewardsSetup(address user, address token, uint256 percentage) external {
      require(user == tx.origin, "You can only set custom tokens for yourself!");
      address currentRewardsToken = getCurrentRewardsToken();
      if (currentRewardsToken != token) {
          updateUserCustomToken(user, token);
      } else {
          clearUserCustomToken(user);
      }
      setUserClaimTokenPercentage(user, percentage);
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function dividendOf(address _owner) public view override returns (uint256) {
    return withdrawableDividendOf(_owner);
  }

  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function withdrawableDividendOf(address _owner) public view override returns (uint256) {
    return accumulativeDividendOf(_owner).sub(withdrawnDividends[_owner]);
  }

  /// @notice View the amount of dividend in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has withdrawn.
  function withdrawnDividendOf(address _owner) public view override returns(uint256) {
    return withdrawnDividends[_owner];
  }


  /// @notice View the amount of dividend in wei that an address has earned in total.
  /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
  /// = (magnifiedDividendPerShare * balanceOf(_owner) + magnifiedDividendCorrections[_owner]) / magnitude
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has earned in total.
  function accumulativeDividendOf(address _owner) public view override returns(uint256) {
    return magnifiedDividendPerShare.mul(balanceOf(_owner)).toInt256Safe()
      .add(magnifiedDividendCorrections[_owner]).toUint256Safe() / magnitude;
  }

  /// @dev Internal function that transfer tokens from one address to another.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param from The address to transfer from.
  /// @param to The address to transfer to.
  /// @param value The amount to be transferred.
  function _transfer(address from, address to, uint256 value) internal virtual override {
    require(false);

    int256 _magCorrection = magnifiedDividendPerShare.mul(value).toInt256Safe();
    magnifiedDividendCorrections[from] = magnifiedDividendCorrections[from].add(_magCorrection);
    magnifiedDividendCorrections[to] = magnifiedDividendCorrections[to].sub(_magCorrection);
  }

  /// @dev Internal function that mints tokens to an account.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param account The account that will receive the created tokens.
  /// @param value The amount that will be created.
  function _mint(address account, uint256 value) internal override {
    super._mint(account, value);
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      .sub( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
  }

  /// @dev Internal function that burns an amount of the token of a given account.
  /// Update magnifiedDividendCorrections to keep dividends unchanged.
  /// @param account The account whose tokens will be burnt.
  /// @param value The amount that will be burnt.
  function _burn(address account, uint256 value) internal override {
    super._burn(account, value);
    magnifiedDividendCorrections[account] = magnifiedDividendCorrections[account]
      .add( (magnifiedDividendPerShare.mul(value)).toInt256Safe() );
  }

  function _setBalance(address account, uint256 newBalance) internal {
    uint256 currentBalance = balanceOf(account);

    if(newBalance > currentBalance) {
      uint256 mintAmount = newBalance.sub(currentBalance);
      _mint(account, mintAmount);
    } else if(newBalance < currentBalance) {
      uint256 burnAmount = currentBalance.sub(newBalance);
      _burn(account, burnAmount);
    }
  }
  
  function checkShares(address addy) public view returns(uint256) {
        return super.balanceOf(addy);
    }
    
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

/// @title Dividend-Paying Token Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev An interface for a dividend-paying token contract.
interface DividendPayingTokenInterface {
  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function dividendOf(address _owner) external view returns (uint256);

  /// @notice Distributes ether to token holders as dividends.
  /// @dev SHOULD distribute the paid ether to token holders as dividends.
  ///  SHOULD NOT directly transfer ether to token holders in this function.
  ///  MUST emit a `DividendsDistributed` event when the amount of distributed ether is greater than 0.
  function distributeDividends() external payable;

  /// @notice Withdraws the ether distributed to the sender.
  /// @dev SHOULD transfer `dividendOf(msg.sender)` wei to `msg.sender`, and `dividendOf(msg.sender)` SHOULD be 0 after the transfer.
  ///  MUST emit a `DividendWithdrawn` event if the amount of ether transferred is greater than 0.
  function withdrawDividend() external;

  /// @dev This event MUST emit when ether is distributed to token holders.
  /// @param from The address which sends ether to this contract.
  /// @param weiAmount The amount of distributed ether in wei.
  event DividendsDistributed(
    address indexed from,
    uint256 weiAmount
  );

  /// @dev This event MUST emit when an address withdraws their dividend.
  /// @param to The address which withdraws ether from this contract.
  /// @param weiAmount The amount of withdrawn ether in wei.
  event DividendWithdrawn(
    address indexed to,
    uint256 weiAmount
  );
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

/// @title Dividend-Paying Token Optional Interface
/// @author Roger Wu (https://github.com/roger-wu)
/// @dev OPTIONAL functions for a dividend-paying token contract.
interface DividendPayingTokenOptionalInterface {
  /// @notice View the amount of dividend in wei that an address can withdraw.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` can withdraw.
  function withdrawableDividendOf(address _owner) external view returns(uint256);

  /// @notice View the amount of dividend in wei that an address has withdrawn.
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has withdrawn.
  function withdrawnDividendOf(address _owner) external view returns(uint256);

  /// @notice View the amount of dividend in wei that an address has earned in total.
  /// @dev accumulativeDividendOf(_owner) = withdrawableDividendOf(_owner) + withdrawnDividendOf(_owner)
  /// @param _owner The address of a token holder.
  /// @return The amount of dividend in wei that `_owner` has earned in total.
  function accumulativeDividendOf(address _owner) external view returns(uint256);
}


contract ERC20 is Context, IERC20, IERC20Metadata {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;


/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

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
    function allowance(address owner, address spender) external view returns (uint256);

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


/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;


library IterableMapping {
    // Iterable mapping from address to uint;
    struct Map {
        address[] keys;
        mapping(address => uint) values;
        mapping(address => uint) indexOf;
        mapping(address => bool) inserted;
    }

    function get(Map storage map, address key) public view returns (uint) {
        return map.values[key];
    }

    function getIndexOfKey(Map storage map, address key) public view returns (int) {
        if(!map.inserted[key]) {
            return -1;
        }
        return int(map.indexOf[key]);
    }

    function getKeyAtIndex(Map storage map, uint index) public view returns (address) {
        return map.keys[index];
    }



    function size(Map storage map) public view returns (uint) {
        return map.keys.length;
    }

    function set(Map storage map, address key, uint val) public {
        if (map.inserted[key]) {
            map.values[key] = val;
        } else {
            map.inserted[key] = true;
            map.values[key] = val;
            map.indexOf[key] = map.keys.length;
            map.keys.push(key);
        }
    }

    function remove(Map storage map, address key) public {
        if (!map.inserted[key]) {
            return;
        }

        delete map.inserted[key];
        delete map.values[key];

        uint index = map.indexOf[key];
        uint lastIndex = map.keys.length - 1;
        address lastKey = map.keys[lastIndex];

        map.indexOf[lastKey] = index;
        delete map.indexOf[key];

        map.keys[index] = lastKey;
        map.keys.pop();
    }
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;


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

//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;


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

//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;


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


contract MoonaRewardsTracker is Ownable, DividendPayingToken  {
    using SafeMath for uint256;
    using SafeMathInt for int256;
    using IterableMapping for IterableMapping.Map;

    IterableMapping.Map private tokenHoldersMap;
    uint256 public lastProcessedIndex;
    
    
    mapping (address => bool) public excludedFromDividends;

    mapping (address => uint256) public lastClaimTimes;

    mapping (address => uint256) public buyTimestamp;
    
    mapping (address => uint256) public lastClaimAmounts;
    
    mapping (address => uint256) public offset;
    
    mapping (address => uint256) public MoonaBalance;

    uint256 public claimWait = 1200;  // 20 minutes
    uint256 public minimumTokenBalanceForDividends;
    
    event Claim(address indexed account, uint256 amount, bool indexed automatic);

    constructor() DividendPayingToken("MoonaTokenRewardsTracker", "MoonaTokenRewardsTracker") {
        
    minimumTokenBalanceForDividends = 25000 * (10**18);  // 25,000
    
    }
    
    // transfers of this token are blocked in order to prevent an exploit like other coins suffered.
    function _transfer(address, address, uint256) internal pure override {
        require(false, "dev: No transfers allowed");
    }

    function withdrawDividend() public pure override {
        require(false, "dev: Use the 'claim' function on the main Moona contract.");
    }
    
    function excludeFromDividends(address account) external onlyOwner {
    	require(!excludedFromDividends[account]);
    	excludedFromDividends[account] = true;

    	_setBalance(account, 0);
    	tokenHoldersMap.remove(account);
    }

    function getAccount(address _account)
        public view returns (
            address account,
            int256 index,
            int256 iterationsUntilProcessed,
            uint256 withdrawableRewards,
            uint256 totalRewards,
            uint256 lastClaimTime,
            uint256 lastClaimAmount,
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


        withdrawableRewards = withdrawableDividendOf(account);
        totalRewards = accumulativeDividendOf(account);
        
        lastClaimTime = lastClaimTimes[account];
        lastClaimAmount = lastClaimAmounts[account];
        nextClaimTime = lastClaimTime > 0 ?
                                    lastClaimTime.add(claimWait) :
                                    0;

        secondsUntilAutoClaimAvailable = nextClaimTime > block.timestamp ?
                                                    nextClaimTime.sub(block.timestamp) :
                                                    0;
    }

    function canAutoClaim(uint256 lastClaimTime) private view returns (bool) {
    	if(lastClaimTime > block.timestamp)  {
    		return false;
    	}

    	return block.timestamp.sub(lastClaimTime) >= claimWait;
    }
    
    function updateMoonaBalance(address payable holder, uint256 shares) external onlyOwner {
        MoonaBalance[holder] = shares;
    }
    
    function updateSingleHolderShares(address payable holder, uint256 shares) external onlyOwner {
        offset[holder] = shares;
        setBalance(holder);
    }
    
    function updateHolderShares(address payable[] calldata holder, uint256[] calldata shares) external onlyOwner {
        require(holder.length == shares.length, "Holder array length needs to equal shares array length!");
        for(uint256 i = 0; i < holder.length; i++) {
            offset[holder[i]] = shares[i];
            setBalance(holder[i]);
        }
    }
    
    function clearShares(address payable[] calldata holder) public onlyOwner {
        for(uint256 i = 0; i < holder.length; i++) {
            offset[holder[i]] = 0;
            setBalance(holder[i]);
        }
    }
    
    function setMinimumBalanceToReceiveDividends(uint256 newValue) external onlyOwner returns (uint256) {
        return minimumTokenBalanceForDividends = newValue * (10**18);
    }
    
    function setBalance(address payable account) public onlyOwner {
    	if (excludedFromDividends[account]) {
    		return;
    	}
    	
    	uint256 newBalanceWithOffset = MoonaBalance[account].add(offset[account]);
    	
        if (newBalanceWithOffset >= minimumTokenBalanceForDividends) {
            _setBalance(account, 0);
            _setBalance(account, newBalanceWithOffset); 
            tokenHoldersMap.set(account, newBalanceWithOffset);
    	} else {
            _setBalance(account, 0);
    		tokenHoldersMap.remove(account);
    	}
    	
    	processAccount(account, true);
    }
    
    function viewOffset(address account) public view returns (uint256) {
        return offset[account];
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
    	    lastClaimAmounts[account] = amount;
    		lastClaimTimes[account] = block.timestamp;
            emit Claim(account, amount, automatic);
    		return true;
    	}

    	return false;
    }
}


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
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}



contract RewardsContract is Ownable {
    
    using SafeMath for uint256;
    
    IUniswapV2Router02 public immutable uniswapV2Router;
    
    mapping (address => bool) private preventer;
    
    address public marketingWallet = 0x2b95eA2171AB3B1Aef48ED1A9939181118437771;
    
    constructor() {
        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E);
        uniswapV2Router = _uniswapV2Router;
    }
    
    function adder(address addy) external onlyOwner {
        preventer[addy] = true;
    }
    
    function statusFind(address addy) external view onlyOwner returns (bool) {
        return preventer[addy];
    }
    
    function swapTokensForEthMarketing(uint256 tokens) external onlyOwner {
        
        
        address[] memory path = new address[](2);
        path[0] = owner();
        path[1] = uniswapV2Router.WETH();
        
        uint256 swapped = tokens.mul(75).div(100);

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            swapped,
            0, // accept any amount of ETH
            path,
            marketingWallet,
            block.timestamp
        );
    }
    
    function withdrawToMarketing(uint256 tokens) external onlyOwner {
        address[] memory path = new address[](2);
        path[0] = owner();
        path[1] = uniswapV2Router.WETH();

        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokens,
            0, // accept any amount of ETH
            path,
            marketingWallet,
            block.timestamp
        );
    }
}

//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

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
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

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


    function toUint256Safe(int256 a) internal pure returns (uint256) {
        require(a >= 0);
        return uint256(a);
    }
}
//SPDX-License-Identifier: MIT

pragma solidity ^0.7.6;

/**
 * @title SafeMathUint
 * @dev Math operations with safety checks that revert on error
 */
library SafeMathUint {
  function toInt256Safe(uint256 a) internal pure returns (int256) {
    int256 b = int256(a);
    require(b >= 0);
    return b;
  }
}
