// SPDX-License-Identifier: MIT
/***
 *    ██████╗  ██████╗ ██╗    ██╗███████╗██████╗ ███╗   ███╗ █████╗ ██████╗ ███████╗
 *    ██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝
 *    ██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝██╔████╔██║███████║██║  ██║█████╗  
 *    ██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══██║██║  ██║██╔══╝  
 *    ██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║██║ ╚═╝ ██║██║  ██║██████╔╝███████╗
 *    ╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 *                    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗                  
 *                    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║                  
 *                       ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║                  
 *                       ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║                  
 *                       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║                  
 *                       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝                  
 *                                                                                  
 */

// FLATTENED VERSION

// File: IAutomaticBuyback.sol


pragma solidity ^0.8.0;

interface IAutomaticBuyback {
    function initialize(address _pancakeRouterAddress, address _cumulatedTokenAddress, address _buybackTokenAddress) external;
    function trigger() external returns (bool buyback_executed);
    function changeBuybackPeriod(uint256 newPeriod) external;
    function updateRouterAddress(address newAddress) external;
    function changeCumulatedToken(address newCumulatedTokenAddress) external;
    function getAutomaticBuybackStatus() external view returns (
            address automatic_buyback_contract_address,
            uint256 next_buyback_timestamp,
            uint256 next_buyback_countdown,
            uint256 current_buyback_period,
            uint256 new_buyback_period,
            address current_cumulated_token,
            uint256 current_cumulated_balance,
            uint256 current_buyback_token_balance,
            uint256 total_buyed_back );
    event Initialized(address indexed _token, address cumulatedToken, address buybackToken, address pancakeRouter);
    event UpdatePancakeRouter(address new_router, address old_router);
    event ChangedBuybackPeriod(uint256 old_period, uint256 new_period, bool immediate);
    event NewBuybackTimestampSet(uint256 period, uint256 buyback_timestamp);
    event BuybackExecuted(uint amount_cumulatedToken, uint256 amount_buybackToken, uint256 buybackToken_current_balance, uint256 total_buyed_back_alltime);
    event ChangedAutomaticBuybackCumulatedToken(address old_cumulatedToken, address new_cumulatedToken);
}
// File: IReflectionManager.sol


pragma solidity ^0.8.0;

interface IReflectionManager {
    function initialize(address _rewardToken) external;
    function setShare(address shareholder, uint256 amount) external;
    function update_deposit(uint256 amount) external;
    function process(uint256 gas) external returns (uint256 currentIndex, uint256 iterations, uint256 claims, bool dismission_completed);
    function claimDividend(address shareholder) external;
    function dismissReflectionManager() external;
    function getUnpaidEarnings(address shareholder) external view returns (uint256);
    function setReflectionEnabledContract(address _contractAddress, bool _enableDisable) external;
    function setReflectionDisabledWallet(address _walletAddress, bool _disableEnable) external;
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution, uint256 _eligibilityThresholdShares) external;
    function setAutoDistributionExcludeFlag(address _shareholder, bool _exclude) external;
    function isDismission() external view returns (bool dismission_is_started, bool dismission_is_completed);
    function getAccountInfo(address shareholder) external view returns (
        uint256 index,
        uint256 currentShares,
        int256 iterationsUntilProcessed,
        uint256 withdrawableDividends,
        uint256 totalRealisedDividends,
        uint256 totalExcludedDividends,
        uint256 lastClaimTime,
        uint256 nextClaimTime,
        bool shouldAutoDistribute,
        bool excludedAutoDistribution,
        bool enabled );
    function getReflectionManagerInfo() external view returns (
        uint256 n_shareholders,
        uint256 current_index,
        uint256 manager_balance,
        uint256 total_shares,
        uint256 total_dividends,
        uint256 total_distributed,
        uint256 dividends_per_share,
        uint256 eligibility_threshold_shares,
        uint256 min_period,
        uint256 min_distribution,
        uint8 dismission );
    function getShareholderAtIndex(uint256 index) external view returns (address);

    event Initialized(address indexed caller, address _rewardToken);
    event Claim(address indexed shareholder, uint256 amount, bool indexed automatic);
    event setDistributionCriteriaUpdate(uint256 minPeriod, uint256 minDistribution, uint256 eligibilityThresholdShares);
    event setReflectionEnabledContractUpdate(address indexed _contractAddress, bool indexed _enableDisable);
    event setReflectionDisabledWalletUpdate(address indexed _walletAddress, bool indexed _disableEnable);
    event setAutoDistributionExcludeFlagUpdate(address indexed _shareholder, bool indexed _exclude);

}
// File: ILPLocker.sol


pragma solidity ^0.8.0;

interface ILPLocker {
    function initialize(uint256 _initial_unlock_ts) external;
    function withdrawLP(address _LPaddress, uint256 _amount, address _to) external;
    function updateLock(uint256 _newUnlockTimestamp) external;
    function getInfoLP(address _LPaddress) external view returns (address locker_address, uint256 LPbalance, uint256 unlock_timestamp, bool unlocked);
    event Initialized(address indexed _token, uint256 _initial_unlock_ts);
    event LPWithdrawn(address indexed _LPaddress, uint256 _amount, address indexed _to);
    event LPLockUpdated(uint256 _oldUnlockTimestamp, uint256 _newUnlockTimestamp);
}
// File: IPancakeSwap.sol

pragma solidity ^0.8.0;

// Interface of the PancakeSwap Router01 (Uniswap Fork) 
// https://docs.pancakeswap.finance/code/smart-contracts/pancakeswap-exchange/router-v2
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-01
interface IPancakeRouter01 {
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

// Interface of the PancakeSwap Router02 (Uniswap Fork) - Extends IPancakeSwapV2Router01
// https://docs.pancakeswap.finance/code/smart-contracts/pancakeswap-exchange/router-v2
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/router-02
interface IPancakeRouter02 is IPancakeRouter01 {
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

// https://docs.pancakeswap.finance/code/smart-contracts/pancakeswap-exchange/factory-v2
// https://docs.uniswap.org/protocol/V2/reference/smart-contracts/factory
interface IPancakeFactory  {
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

// PancakeSwap equivalent of: https://docs.uniswap.org/protocol/V2/reference/smart-contracts/pair
interface IPancakePair {
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
    event Cast(address indexed sender, uint amount0, uint amount1);
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
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;
    function initialize(address, address) external;
}
// File: Counters.sol

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset.
 */
library Counters {
    struct Counter {
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}
// File: Arrays.sol

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to array types.
 */
library Arrays {

    function findUpperBound(uint256[] storage array, uint256 element) internal view returns (uint256) {
        if (array.length == 0) {
            return 0;
        }

        uint256 low = 0;
        uint256 high = array.length;

        while (low < high) {
            uint256 mid = average(low, high);
            if (array[mid] > element) {
                high = mid;
            } else {
                low = mid + 1;
            }
        }

        if (low > 0 && array[low - 1] == element) {
            return low - 1;
        } else {
            return low;
        }
    }

    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow.
        return (a & b) + (a ^ b) / 2;
    }

}
// File: IBEP20.sol


pragma solidity ^0.8.0;

/**
 * @dev Interface of the BEP20 standard as defined in the EIP.
 */
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

// File: IBEP20Metadata.sol


pragma solidity ^0.8.0;


/**
 * @dev Interface for the optional metadata functions from the BEP20 standard.
 */
interface IBEP20Metadata is IBEP20 {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
}

// File: Context.sol


pragma solidity ^0.8.0;

/**
 * @dev Context Functions to be used instead of msg.sender and msg.data directly (see the issue with GSN meta-transactions)
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// File: Ownable.sol


pragma solidity ^0.8.0;


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
    address private _previousOwner;
    uint256 private _lockTime;
    
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event LockOwnership(address indexed owner, uint256 unlockTime);

    // The initial owner is the deployer
    constructor() {
        _transferOwnership(_msgSender());
    }

    // Returns the owner
    function owner() public view virtual returns (address) {
        return _owner;
    }

    // Modifier used for the administrative (owner) functions
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    // Transfer the ownership to another address
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    // Internal function to manage the ownership transfer operation
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }

    // Get the unlock time
    function getUnlockTime() public view returns (uint256) {
        return _lockTime;
    }

    // Locks the contract for owner for the amount of time provided (set a big time, like earth life, to lock forever)
    function lock(uint256 time) public virtual onlyOwner {
        _previousOwner = _owner;
        _lockTime = block.timestamp + time;
        _transferOwnership(address(0));
        emit LockOwnership(_previousOwner, _lockTime);
    }
    
    //Unlocks the contract for owner when _lockTime is passed
    function unlock() public virtual {
        require(_previousOwner == _msgSender(), "You don't have permission to unlock");
        require(block.timestamp > _lockTime , "Contract is locked until UnlockTime");
        _transferOwnership(_previousOwner);
    }
}

// File: SafeMath.sol


pragma solidity ^0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow checks (not available in Solidity as default)
 * Library to be used with unsigned integers (256 bit)
 */
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
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
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
        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }

    function toInt256Safe(uint256 a) internal pure returns (int256) {
        int256 b = int256(a);
        require(b >= 0);
        return b;
    }
}

// File: AutomaticBuyback.sol


pragma solidity ^0.8.0;

contract AutomaticBuyback is IAutomaticBuyback {
    using SafeMath for uint256;

    address private _token;                     // Caller Smart Contract
    bool private initialized;

    IBEP20 private cumulatedToken;              // Cumulated token (stablecoin BUSD)
    IBEP20 private buybackToken;                // The token to buyback using all the cumulatedToken balance
    uint256 private buybackPeriod;              // Buyback period in days. CAN ONLY BE 30 days, 60 days or 90 days
    uint256 private buybackPeriodNew;           // Used to update the buyback period
    uint256 private buyback_timestamp;          // The next buyback timestamp
    uint256 private totalBuyedBackAlltime;      // Total bought back alltime
    IPancakeRouter02 private pancakeRouter;     // The DEX router

    uint256 private constant TIME_UNIT = 1 days;
    uint256 private constant INSTANT_UPDATE_FORBIDDEN_TH = 7 * TIME_UNIT;          // Days before the buyback
    uint256 private constant CUMULATED_TOKEN_CHANGE_PERIOD_TH = 5 * TIME_UNIT;     // Days after the buyback

    modifier onlyToken() {
        require(msg.sender == _token, "Unauthorized"); _;
    }

    constructor () {}

    function initialize(address _pancakeRouterAddress, address _cumulatedTokenAddress, address _buybackTokenAddress) external override {
        require(!initialized, "AutomaticBuyback: already initialized!");
        initialized = true;
        _token = msg.sender;
        cumulatedToken = IBEP20(_cumulatedTokenAddress);
        buybackToken = IBEP20(_buybackTokenAddress);
        pancakeRouter = IPancakeRouter02(_pancakeRouterAddress);
        _changeBuybackPeriod(30);   // Set default period of 30 days
        emit Initialized(_token, address(cumulatedToken), address(buybackToken), address(pancakeRouter));
    }

    // Trigger to call at every transaction. If the buyback timestamp is reached the buyback will be executed, returning true
    // Otherwise nothing will be executed, returning false
    function trigger() external override onlyToken returns (bool buyback_executed) {
        if (block.timestamp >= buyback_timestamp) {
            // Execute the buyback
            _buybackAll();
            // Set next buyback
            if (buybackPeriodNew != buybackPeriod) {
                buybackPeriod = buybackPeriodNew;
            }
            buyback_timestamp = buyback_timestamp + buybackPeriod * TIME_UNIT;
            emit NewBuybackTimestampSet(buybackPeriod, buyback_timestamp);
            buyback_executed = true;
        } else {
            buyback_executed = false;
        } 
    }

    // External function to change the buyback period between 30, 60 or 90 days
    function changeBuybackPeriod(uint256 newPeriod) external override onlyToken {
        require(newPeriod != buybackPeriod, "AutomaticBuyback: the newPeriod must be different from the current period");
        require(newPeriod == 30 || newPeriod == 60 || newPeriod == 90, "AutomaticBuyback: the period must be 30, 60 or 90 (days)");
        _changeBuybackPeriod(newPeriod);
    }

    // Change the buyback period. It will be done immediately only if the new period is greater than the old period and the change
    // is done at least 7 days before the current buyback timestamp. Otherwise the change is done after the buyback
    function _changeBuybackPeriod(uint256 newPeriod) internal {
        if (buyback_timestamp == 0) {
            buyback_timestamp = block.timestamp + newPeriod * TIME_UNIT;
            emit ChangedBuybackPeriod(buybackPeriod, newPeriod, true);
            buybackPeriod = newPeriod;
            buybackPeriodNew = newPeriod;
            emit NewBuybackTimestampSet(buybackPeriod, buyback_timestamp);
            return;
        }
        if (newPeriod > buybackPeriod) {
            if (block.timestamp < buyback_timestamp - INSTANT_UPDATE_FORBIDDEN_TH) {
                // If before 7 days (INSTANT_UPDATE_FORBIDDEN_TH) from the buyback time, we can shift it, otherwise it will be changed after the buyback
                buyback_timestamp = (buyback_timestamp - buybackPeriod * TIME_UNIT) + newPeriod * TIME_UNIT;
                emit ChangedBuybackPeriod(buybackPeriod, newPeriod, true);
                buybackPeriod = newPeriod;
                buybackPeriodNew = newPeriod;
                emit NewBuybackTimestampSet(buybackPeriod, buyback_timestamp);
            } else {
                buybackPeriodNew = newPeriod;
                emit ChangedBuybackPeriod(buybackPeriod, newPeriod, false);
            }
        } else {
            // Set to update after the next buyback
            buybackPeriodNew = newPeriod;
            emit ChangedBuybackPeriod(buybackPeriod, newPeriod, false);
        }
    }


    // Buy the buybackToken using all the cumulated cumulatedToken in the contract
    // The buybackToken will be sent to the AutomatedBuyback contract (this) and can be burnt from the caller token
    // using the internal _burn() function or kept locked forever inside the AutomatedBuyback contract
    function _buybackAll() internal {
        uint256 tokenAmount = cumulatedToken.balanceOf(address(this));
        uint256 previousBuybackBalance = buybackToken.balanceOf(address(this));
        if (tokenAmount > 0) {
            address[] memory path = new address[](3);
            path[0] = address(cumulatedToken);
            path[1] = pancakeRouter.WETH();
            path[2] = address(buybackToken);
            cumulatedToken.approve(address(pancakeRouter), tokenAmount);
            // make the swap
            pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
                tokenAmount,
                0,
                path,
                address(this),
                block.timestamp
            );
        }
        uint256 currentBuybackBalance = buybackToken.balanceOf(address(this));
        totalBuyedBackAlltime = totalBuyedBackAlltime.add(currentBuybackBalance).sub(previousBuybackBalance);
        emit BuybackExecuted(tokenAmount, currentBuybackBalance.sub(previousBuybackBalance), currentBuybackBalance, totalBuyedBackAlltime);
    }


    // Update the router address 
    function updateRouterAddress(address newAddress) external override onlyToken {
        emit UpdatePancakeRouter(newAddress, address(pancakeRouter));
        pancakeRouter = IPancakeRouter02(newAddress);
    }


    // Change the cumulated token used for the automatic buyback. It must be called just before changing the cumulatedToken in the caller
    // After changing the token, the AutomaticBuyback contract is expecting to cumulate and use the new token
    function changeCumulatedToken(address newCumulatedTokenAddress) external override onlyToken {
        require(newCumulatedTokenAddress != address(buybackToken), "AutomaticBuyback: cumulatedToken cannot be buybackToken");
        // Only possible within the first 5 days (CUMULATED_TOKEN_CHANGE_PERIOD_TH) from the last buyback event
        require(block.timestamp <= (buyback_timestamp - buybackPeriod * TIME_UNIT) + CUMULATED_TOKEN_CHANGE_PERIOD_TH, "AutomaticBuyback: cannot change the cumulatedToken used NOW");
        emit ChangedAutomaticBuybackCumulatedToken(address(cumulatedToken), newCumulatedTokenAddress);
        // Do a forced internal buyback, without changing the next timestamp
        _buybackAll();
        // Now the cumulatedToken balance is zero, we can switch to the new cumulatedToken
        cumulatedToken = IBEP20(newCumulatedTokenAddress);
    }

    // Return the current status of the AutomaticBuyback and the countdown to the next automatic buyback event
    function getAutomaticBuybackStatus() public view override returns (
            address automatic_buyback_contract_address,
            uint256 next_buyback_timestamp,
            uint256 next_buyback_countdown,
            uint256 current_buyback_period,
            uint256 new_buyback_period,
            address current_cumulated_token,
            uint256 current_cumulated_balance,
            uint256 current_buyback_token_balance,
            uint256 total_buyed_back ) {
        automatic_buyback_contract_address = address(this);
        next_buyback_timestamp = buyback_timestamp;
        next_buyback_countdown = block.timestamp < buyback_timestamp ? buyback_timestamp - block.timestamp : 0;
        current_buyback_period = buybackPeriod;
        new_buyback_period = buybackPeriodNew;
        current_cumulated_token = address(cumulatedToken);
        current_cumulated_balance = cumulatedToken.balanceOf(address(this));
        current_buyback_token_balance = buybackToken.balanceOf(address(this));
        total_buyed_back = totalBuyedBackAlltime;
    }

}
// File: ReflectionManager.sol


pragma solidity ^0.8.0;

contract ReflectionManager is IReflectionManager {
    using SafeMath for uint256;

    address private _token;      // Caller Smart Contract
    IBEP20 public RWRD;         // Reward Token
    bool private initialized;

    struct Share {
        uint256 amount;
        uint256 totalExcluded;
        uint256 totalRealised;
        uint256 totalRemainings;
    }
    // shareholders MAP
    address[] private shareholders;
    mapping (address => uint256) private shareholderIndexes;    // starts from 1
    mapping (address => uint256) private shareholderClaims;
    mapping (address => Share) private shares;
    mapping (address => bool) private enabled_contracts;
    mapping (address => bool) private disabled_wallets;
    mapping (address => bool) private excluded_auto_distribution;

    uint256 private currentIndex;
    uint256 private totalShares;
    uint256 private totalDividends;
    uint256 private totalDistributed;
    uint256 private dividendsPerShare;
    uint256 private constant dividendsPerShareAccuracyFactor = 10 ** 36;

    uint256 private eligibilityThresholdShares = 2000 * (10**18);       // Min shares to be added as shareholder
    uint256 private minPeriod = 60 * 60;                     // Min period (s) between distributions (single shareholder)
    uint256 private minDistribution = 1 * (10**12);          // Min cumulated amount before distribution (single shareholder)

    bool private dismission_reflection_manager = false;     // Set to dismiss the reflection manager (before trashing it, eg. when migrating to a new RWRD token)
    bool private dismission_completed = false;              // Flag indicating the dismission is completed


    modifier onlyToken() {
        require(msg.sender == _token, "Unauthorized"); _;
    }

    constructor () {}

    function initialize(address _rewardToken) external override {
        require(!initialized, "ReflectionManager: already initialized!");
        initialized = true;
        _token = msg.sender;
        RWRD = IBEP20(_rewardToken);
        emit Initialized(_token, _rewardToken);
    }

    // Set or change the distribution parameters (minPeriod and minDistribution affect only for automatic distribution)
    function setDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution, uint256 _eligibilityThresholdShares) external override onlyToken {
        require(_minPeriod >= 10 minutes && _minPeriod <= 24 hours, "ReflectionManager: _minPeriod must be updated to between 10 minutes and 24 hours");
        eligibilityThresholdShares = _eligibilityThresholdShares;
        minPeriod = _minPeriod;
        minDistribution = _minDistribution;
        emit setDistributionCriteriaUpdate(minPeriod, minDistribution, eligibilityThresholdShares);
    }

    // Set the share of a user, with internal check of eligibility
    function setShare(address shareholder, uint256 amount) external override onlyToken {
        if (dismission_reflection_manager) { return; }
        // Distribute the reflection to the shareholder, if it has shares and not excluded from auto-distribution
        if(shares[shareholder].amount > 0) {
            if (!excluded_auto_distribution[shareholder]) {
                distributeDividend(shareholder, true);      // Discard outcome
            } else {
                // update unpaid remaining because we will "reshape" the slice of the cake
                shares[shareholder].totalRemainings = getUnpaidEarnings(shareholder);
            }  
        } 
        // Exclude all contracts not in enabled_contracts list, exclude all disabled wallets, exclude all shareholders below the threshold
        if (amount < eligibilityThresholdShares || disabled_wallets[shareholder] || (isContract(shareholder) && !enabled_contracts[shareholder]) || shareholder == address(0)) { 
            removeShareholder(shareholder);
            amount = 0;
        } else if (amount >= eligibilityThresholdShares) {
            addShareholder(shareholder);
        } else {
            removeShareholder(shareholder);
            amount = 0;
        }
    	// Update Shares
        totalShares = totalShares.sub(shares[shareholder].amount).add(amount);
        shares[shareholder].amount = amount;
        shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);     // reshape
    }

    // Add a Shareholder to the map (do nothing if already exists)
    function addShareholder(address shareholder) internal {
        // Add only if not exists
        if (shareholderIndexes[shareholder] == 0) {
            shareholderIndexes[shareholder] = shareholders.length + 1;
            shareholders.push(shareholder);
        }
    }

    // Remove a Shareholder from the map (do nothing if not exists)
    function removeShareholder(address shareholder) internal {
        if (shareholderIndexes[shareholder] == 0) {
            return;     // Not exists
        }
        shareholders[shareholderIndexes[shareholder] - 1] = shareholders[shareholders.length-1];
        shareholderIndexes[shareholders[shareholders.length-1]] = shareholderIndexes[shareholder];
        shareholderIndexes[shareholder] = 0;
        shareholders.pop();
    }

    // Update the Reflection state variable after a transfer into the contract. MUST always be called after a transfer into the ReflectionManager address, passing the exact transferred amount
    // The tokens transferred must be RWRD (token used for the reflection)
    function update_deposit(uint256 amount) external override onlyToken {
        if (dismission_reflection_manager) { return; }
        totalDividends = totalDividends.add(amount);
        dividendsPerShare = totalShares > 0 ? dividendsPerShare.add(dividendsPerShareAccuracyFactor.mul(amount).div(totalShares)) : 0;
    }

    // Process a certain number of accounts using the provided gas, saving the pointer (currentIndex) for the next call
    function process(uint256 gas) external override onlyToken returns (uint256, uint256, uint256, bool) {
        if (dismission_completed) { return (currentIndex, 0, 0, dismission_completed); }
        uint256 shareholderCount = shareholders.length;
        if (shareholderCount == 0) { return (currentIndex, 0, 0, dismission_completed); }
        uint256 gasUsed = 0;
        uint256 gasLeft = gasleft();
        uint256 iterations = 0;
        uint256 claims = 0;
        while (gasUsed < gas && iterations < shareholderCount) {
            if (currentIndex >= shareholderCount) {
                // Restart from the first
                currentIndex = 0;
                if (dismission_reflection_manager) {
                    // Set dismission completed (the contract can be dismissed and a new reflection manager,
                    // also with a new token, can be created by the caller contract).  
                    dismission_completed = true;
                    break;
                }
            }
            // Distribute the reflection for the indexed shareholder
            address shareholder_current_index = shareholders[currentIndex];
            if (shouldDistribute(shareholder_current_index) || (dismission_reflection_manager && !excluded_auto_distribution[shareholder_current_index])){
                bool distributed = distributeDividend(shareholder_current_index, true);
                if (distributed) { claims++; }
            }
            gasUsed = gasUsed.add(gasLeft.sub(gasleft()));
            gasLeft = gasleft();
            currentIndex++;
            iterations++;
        }
        return (currentIndex, iterations, claims, dismission_completed);
    }
    
    // Check if minPeriod passed and minDistribution amount reached, and if excluded from auto-distribution
    function shouldDistribute(address shareholder) internal view returns (bool) {
        return shareholderClaims[shareholder] + minPeriod < block.timestamp
                && getUnpaidEarnings(shareholder) > minDistribution
                && !excluded_auto_distribution[shareholder];
    }

    // Distribute the dividends of the shareholder
    // It can return false of the shares are zero, if there is nothing to distribute OR if the contract has not enough balance to process the shareholder
    // The last case can occur due to rounding issues. We have to simply wait for other deposits. The amount is moved to totalRemainings variable
    function distributeDividend(address shareholder, bool automatic) internal returns (bool) {
        if(shares[shareholder].amount == 0) { return false; }
        uint256 amount = getUnpaidEarnings(shareholder);
        if(amount > 0 && RWRD.balanceOf(address(this)) >= amount) {
            totalDistributed = totalDistributed.add(amount);
            RWRD.transfer(shareholder, amount);
            shareholderClaims[shareholder] = block.timestamp;
            shares[shareholder].totalRemainings = 0;
            shares[shareholder].totalRealised = shares[shareholder].totalRealised.add(amount);
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
            emit Claim(shareholder, amount, automatic);
            return true;
        } else if (amount > 0 && RWRD.balanceOf(address(this)) < amount) {
            shares[shareholder].totalRemainings = amount;
            shares[shareholder].totalExcluded = getCumulativeDividends(shares[shareholder].amount);
            return false;
        } else {
            return false;
        }
    }
    
    // Manual claim the reflection for a specific user (sending it to the user)
    function claimDividend(address shareholder) external override {
        distributeDividend(shareholder, false);     // discard outcome
    }

    // Start the dismission of the reflection manager (when migrating to a new reward token)
    function dismissReflectionManager() external override onlyToken {
        dismission_reflection_manager = true;   // Enable dismission mode
        currentIndex = 0;   // Restart the counter
    }

    // Calculate the unpaid dividends
    function getUnpaidEarnings(address shareholder) public view override returns (uint256) {
        if (shares[shareholder].amount == 0) { return 0; }
        uint256 shareholderTotalDividends = getCumulativeDividends(shares[shareholder].amount);
        uint256 shareholderTotalExcluded = shares[shareholder].totalExcluded;
        uint256 shareholdertotalRemainings = shares[shareholder].totalRemainings;
        if (shareholderTotalDividends <= shareholderTotalExcluded) { return shareholdertotalRemainings; }
        return shareholderTotalDividends.sub(shareholderTotalExcluded).add(shareholdertotalRemainings);
    }

    // Calculate the cumulative dividends
    function getCumulativeDividends(uint256 share) internal view returns (uint256) {
        return share.mul(dividendsPerShare).div(dividendsPerShareAccuracyFactor);
    }

    // Enable or disable a reflection-receiving smart contract (other contracts excluded by default)
    function setReflectionEnabledContract(address _contractAddress, bool _enableDisable) external override onlyToken {
        require(isContract(_contractAddress), "ReflectionManager: _contractAddress is not a contract");
        enabled_contracts[_contractAddress] = _enableDisable;
        emit setReflectionEnabledContractUpdate(_contractAddress, _enableDisable);
    }

    // Disable or re-enable a reflection-receiving wallet
    function setReflectionDisabledWallet(address _walletAddress, bool _disableEnable) external override onlyToken {
        disabled_wallets[_walletAddress] = _disableEnable;
        emit setReflectionDisabledWalletUpdate(_walletAddress, _disableEnable);
    }

    // Enable or disable the automatic claim for an address/shareholder
    function setAutoDistributionExcludeFlag(address _shareholder, bool _exclude) external override onlyToken {
        excluded_auto_distribution[_shareholder] = _exclude;
        emit setAutoDistributionExcludeFlagUpdate(_shareholder, _exclude);
    }

    // Get different information about a shareholder
    function getAccountInfo(address shareholder) public view override returns (
            uint256 shareholder_id,     // it is index+1, zero if shareholder not in list
            uint256 currentShares,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalRealisedDividends,
            uint256 totalExcludedDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            bool shouldAutoDistribute,
            bool excludedAutoDistribution,
            bool enabled ) {
        shareholder_id = shareholderIndexes[shareholder];
        currentShares = shares[shareholder].amount;
        iterationsUntilProcessed = -1;
        if (shareholder_id >= 1) {
            if ((shareholder_id - 1) >= currentIndex) {
                iterationsUntilProcessed = int256(shareholder_id - currentIndex);
            }
            else {
                uint256 processesUntilEndOfArray = shareholders.length > currentIndex ? (shareholders.length - currentIndex) : 0;
                iterationsUntilProcessed = int256(shareholder_id + processesUntilEndOfArray);
            }
        }
        withdrawableDividends = getUnpaidEarnings(shareholder);
        totalRealisedDividends = shares[shareholder].totalRealised;
        totalExcludedDividends = shares[shareholder].totalExcluded;
        lastClaimTime = shareholderClaims[shareholder];
        nextClaimTime = lastClaimTime > 0 ? lastClaimTime.add(minPeriod) : 0;
        shouldAutoDistribute = shouldDistribute(shareholder);
        excludedAutoDistribution = excluded_auto_distribution[shareholder];
        enabled = isContract(shareholder) ? enabled_contracts[shareholder] : !disabled_wallets[shareholder];
    }

    // Return dismission status
    function isDismission() public view override returns (bool dismission_is_started, bool dismission_is_completed) {
        dismission_is_started = dismission_reflection_manager;
        dismission_is_completed = dismission_completed;
    }

    // Returns global info of the reflection manager
    function getReflectionManagerInfo() public view override returns (
            uint256 n_shareholders,
            uint256 current_index,
            uint256 manager_balance,
            uint256 total_shares,
            uint256 total_dividends,
            uint256 total_distributed,
            uint256 dividends_per_share,
            uint256 eligibility_threshold_shares,
            uint256 min_period,
            uint256 min_distribution,
            uint8 dismission ) {
        n_shareholders = shareholders.length;
        current_index = currentIndex;
        manager_balance = RWRD.balanceOf(address(this));
        total_shares = totalShares;
        total_dividends = totalDividends;
        total_distributed = totalDistributed;
        dividends_per_share = dividendsPerShare;
        eligibility_threshold_shares = eligibilityThresholdShares;
        min_period = minPeriod;
        min_distribution = minDistribution;
        dismission = dismission_reflection_manager ? (dismission_completed ? 2 : 1) : 0;
    }

    // Get the address of a shareholder given the index (from 0)
    function getShareholderAtIndex(uint256 index) public view override returns (address) {
        return shareholders[index];
    }

    // Check if smart contract
    function isContract(address account) internal view returns (bool) {
        return account.code.length > 0;
    }

}

// File: LPLocker.sol


pragma solidity ^0.8.0;

contract LPLocker is ILPLocker {
    using SafeMath for uint256;

    address private _token;      // Caller Smart Contract
    bool private initialized;

    uint256 private unlock_ts;

    modifier onlyToken() {
        require(msg.sender == _token, "Unauthorized"); _;
    }

    constructor () {}

    function initialize(uint256 _initial_unlock_ts) external override {
        require(!initialized, "LPLocker: already initialized!");
        initialized = true;
        _token = msg.sender;
        // Set initial lock
        _updateLock(_initial_unlock_ts);
        emit Initialized(_token, _initial_unlock_ts);
    }

    // Withdraw the specified token (LP token) from the LPLocker, sending the amount (coerced to the balance available, wei unit) t0 the _to address
    // Possible only the lock expired (unlocked)
    function withdrawLP(address _LPaddress, uint256 _amount, address _to) external override onlyToken {
        require(block.timestamp > unlock_ts, "LPLocker: Lock not expired!");
        IBEP20 token_out = IBEP20(_LPaddress);
        if (token_out.balanceOf(address(this)) < _amount) {
            _amount = token_out.balanceOf(address(this));   // coerce
        }
        token_out.transfer(_to, _amount);
        emit LPWithdrawn(_LPaddress, _amount, _to);
    }

    // Update the Lock of the LPLocker
    function updateLock(uint256 _newUnlockTimestamp) external override onlyToken {
        _updateLock(_newUnlockTimestamp);
    }

    // Update the Lock of the LPLocker internal function
    function _updateLock(uint256 _newUnlockTimestamp) internal {
        // The new lock timestamp (in s) must be in the future (from now + 1 day) and greater than the stored unlock timestamp
        require(_newUnlockTimestamp > block.timestamp + 1 days && _newUnlockTimestamp > unlock_ts, "LPLocker: _newUnlockTimestamp must be > now + 1 day && > current unlock_ts");
        emit LPLockUpdated(unlock_ts, _newUnlockTimestamp);
        unlock_ts = _newUnlockTimestamp;
    }

    // Return the status of the LPLock vault, its address and the balance of the provided _LPaddress (if different from NULL address)
    function getInfoLP(address _LPaddress) public view override returns (address locker_address, uint256 LPbalance, uint256 unlock_timestamp, bool unlocked) {
        locker_address = address(this);
        if (_LPaddress != address(0)) {
            LPbalance = IBEP20(_LPaddress).balanceOf(locker_address);
        }
        unlock_timestamp = unlock_ts;
        unlocked = (block.timestamp > unlock_ts);
    }

}
// File: BEP20.sol


pragma solidity ^0.8.0;

/**
 * @dev Implementation of the {IBEP20} interface. The good default one.
 */
contract BEP20 is Context, IBEP20, IBEP20Metadata {
    using SafeMath for uint256;

    mapping(address => uint256) private _balances;
    mapping(address => mapping(address => uint256)) private _allowances;
    uint256 private _totalSupply;
    string private _name;
    string private _symbol;

    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    function name() public view virtual override returns (string memory) {
        return _name;
    }

    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view virtual override returns (uint256) {
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
        _approve(_msgSender(), spender, amount);
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

    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "BEP20: transfer from the zero address");
        require(recipient != address(0), "BEP20: transfer to the zero address");
        _beforeTokenTransfer(sender, recipient, amount);
        _balances[sender] = _balances[sender].sub(amount, "BEP20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: mint to the zero address");
        _beforeTokenTransfer(address(0), account, amount);
        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "BEP20: burn from the zero address");
        _beforeTokenTransfer(account, address(0), amount);
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

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual {}
}

// File: BEP20Snapshot.sol


// Derived from OpenZeppelin Contracts v4.4.1 (token/ERC20/extensions/ERC20Snapshot.sol)

pragma solidity ^0.8.0;




abstract contract BEP20Snapshot is BEP20 {
    // Inspired by Jordi Baylina's MiniMeToken to record historical balances:
    // https://github.com/Giveth/minimd/blob/ea04d950eea153a04c51fa510b068b9dded390cb/contracts/MiniMeToken.sol

    using Arrays for uint256[];
    using Counters for Counters.Counter;

    struct Snapshots {
        uint256[] ids;
        uint256[] values;
    }

    mapping(address => Snapshots) private _accountBalanceSnapshots;
    Snapshots private _totalSupplySnapshots;
    Counters.Counter private _currentSnapshotId;

    event Snapshot(uint256 id);

    function _snapshot() internal virtual returns (uint256) {
        _currentSnapshotId.increment();

        uint256 currentId = _getCurrentSnapshotId();
        emit Snapshot(currentId);
        return currentId;
    }

    function _getCurrentSnapshotId() internal view virtual returns (uint256) {
        return _currentSnapshotId.current();
    }

    function balanceOfAt(address account, uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _accountBalanceSnapshots[account]);

        return snapshotted ? value : balanceOf(account);
    }

    function totalSupplyAt(uint256 snapshotId) public view virtual returns (uint256) {
        (bool snapshotted, uint256 value) = _valueAt(snapshotId, _totalSupplySnapshots);
        return snapshotted ? value : totalSupply();
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);
        if (from == address(0)) {
            // mint
            _updateAccountSnapshot(to);
            _updateTotalSupplySnapshot();
        } else if (to == address(0)) {
            // burn
            _updateAccountSnapshot(from);
            _updateTotalSupplySnapshot();
        } else {
            // transfer
            _updateAccountSnapshot(from);
            _updateAccountSnapshot(to);
        }
    }

    function _valueAt(uint256 snapshotId, Snapshots storage snapshots) private view returns (bool, uint256) {
        require(snapshotId > 0, "BEP0Snapshot: id is 0");
        require(snapshotId <= _getCurrentSnapshotId(), "BEP20Snapshot: nonexistent id");
        uint256 index = snapshots.ids.findUpperBound(snapshotId);
        if (index == snapshots.ids.length) {
            return (false, 0);
        } else {
            return (true, snapshots.values[index]);
        }
    }

    function _updateAccountSnapshot(address account) private {
        _updateSnapshot(_accountBalanceSnapshots[account], balanceOf(account));
    }

    function _updateTotalSupplySnapshot() private {
        _updateSnapshot(_totalSupplySnapshots, totalSupply());
    }

    function _updateSnapshot(Snapshots storage snapshots, uint256 currentValue) private {
        uint256 currentId = _getCurrentSnapshotId();
        if (_lastSnapshotId(snapshots.ids) < currentId) {
            snapshots.ids.push(currentId);
            snapshots.values.push(currentValue);
        }
    }

    function _lastSnapshotId(uint256[] storage ids) private view returns (uint256) {
        if (ids.length == 0) {
            return 0;
        } else {
            return ids[ids.length - 1];
        }
    }
}
// File: POWERMADE.sol



/***
 *    ██████╗  ██████╗ ██╗    ██╗███████╗██████╗ ███╗   ███╗ █████╗ ██████╗ ███████╗
 *    ██╔══██╗██╔═══██╗██║    ██║██╔════╝██╔══██╗████╗ ████║██╔══██╗██╔══██╗██╔════╝
 *    ██████╔╝██║   ██║██║ █╗ ██║█████╗  ██████╔╝██╔████╔██║███████║██║  ██║█████╗  
 *    ██╔═══╝ ██║   ██║██║███╗██║██╔══╝  ██╔══██╗██║╚██╔╝██║██╔══██║██║  ██║██╔══╝  
 *    ██║     ╚██████╔╝╚███╔███╔╝███████╗██║  ██║██║ ╚═╝ ██║██║  ██║██████╔╝███████╗
 *    ╚═╝      ╚═════╝  ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝
 *                    ████████╗ ██████╗ ██╗  ██╗███████╗███╗   ██╗                  
 *                    ╚══██╔══╝██╔═══██╗██║ ██╔╝██╔════╝████╗  ██║                  
 *                       ██║   ██║   ██║█████╔╝ █████╗  ██╔██╗ ██║                  
 *                       ██║   ██║   ██║██╔═██╗ ██╔══╝  ██║╚██╗██║                  
 *                       ██║   ╚██████╔╝██║  ██╗███████╗██║ ╚████║                  
 *                       ╚═╝    ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═══╝                  
 *                                                                                  
 */

pragma solidity ^0.8.13;


contract POWERMADE is BEP20, BEP20Snapshot, Ownable {

    using SafeMath for uint256;

    IPancakeRouter02 public pancakeRouter;              // The DEX router
    address public pancakePair;                         // The liquidity pair
    mapping (address => bool) public automatedMarketMakerPairs;     // All the liquidity pairs (pancakePair included)
    bool private swapping;                              // Swapping flag (re-entrancy protection)
    uint256 public transactionsBeforeExecution = 10;    // Number of valid (only sells and valid transfers) transactions before execution of the internal features (eg. 10 = 7 dead + 3 executions)
    uint256 public tx_counter;     // Tx counter (only sells and valid transfers)
    uint256 public amountReflectionTax;
    uint256 public amountBuybackTax;
    uint256 public amountLiquidityTax;
    mapping (address => bool) private _isExcludedFromFees;      // Addresses excluded from the token tax
    mapping (address => bool) public multisenderSmartContract;  // Smart contracts or wallets used to send massive amount of tokens

    ReflectionManager public reflectionManager;         // The current (main) Reflection Manager
    ReflectionManager public reflectionManagerOld;      // Used if changing the reflection token
    BEP20 public reflectionToken;                       // The reflection token (BTCB)
    uint256 public gasForProcessing = 300000;           // Gas for processing the reflections

    AutomaticBuyback public automaticBuyback;           // The Automatic Buyback Manager
    BEP20 public automaticBuyback_cumulatedToken;       // The cumulated token for the buyback (BUSD)

    LPLocker public LP_locker;                          // The locker contract for the Automatic liquidity feature (destination of the LP)

    mapping(address => bool) private _isExcludedFromAntiWhale;
    uint256 public maxTransferAmountRate = 1000;    // default and minimum value will be 1000 / 1E6 = 0.001 (0.1% of the supply)
    bool private enableAntiwhale;                   // Limit max TX except BUY. Default disabled (false)
    mapping (address => bool) private _isTimelockExempt;    // Addresses excluded from Cooldown feature
    mapping (address => uint) private cooldownCheckpoint;
    bool private cooldownEnabled;                    // Deadtime between trades on AMM. Default disabled (false)
    uint256 public cooldownSellInterval = 10 * 1 minutes;   // Default cooldown Sell interval is 10 minutes
    uint256 public cooldownBuyInterval = 1 * 1 minutes;     // Default cooldown Buy interval is 1 minute

    mapping(address => bool) private _isBlacklisted;     // Blacklist for compliance
    mapping(address => bool) private _canSnapshot;       // Wallet allowed to do snapshots

    // Constants
    uint256 public constant REFLECTION_ELIGIBILITY_THRESHOLD = 2000 * (10**18);        // Amount of PWD needed for the reflection
    uint256 public constant REFLECTION_TAX = 2;
    uint256 public constant BUYBACK_AND_BURN_TAX = 3;
    uint256 public constant AUTOMATED_LIQUIDITY_TAX = 3;

    // Events
    event ExcludeFromFees(address indexed account, bool isExcluded);
    event ExcludeMultipleAccountsFromFees(address[] accounts, bool isExcluded);
    event ExcludeFromAntiWhale(address indexed account, bool isExcluded);
    event EnableDisableAntiWhale(bool indexed new_status);
    event SetAntiWhaleMaxTransferRate(uint256 newRate, uint256 oldRate);
    event ExcludeFromCooldown(address indexed account, bool isExcluded);
    event EnableDisableCooldown(bool indexed new_status);
    event SetCooldownSellPeriod(uint256 newPeriod, uint256 oldPeriod);
    event SetCooldownBuyPeriod(uint256 newPeriod, uint256 oldPeriod);
    event SetAutomatedMarketMakerPair(address indexed pair, bool indexed value);
    event SetMultisenderSmartContract(address indexed pair, bool indexed value);
    event SetNumberOfTransaction(uint256 new_value, uint256 old_value);
    event SetBlacklisted(address indexed account, bool old_status, bool new_status);
    event SetCanSnapshotWallet(address indexed account, bool indexed can_snapshot);
    event UpdatedPancakeRouter(address indexed newAddress, address indexed oldAddress, address indexed dexPair);
    event GasForProcessingUpdated(uint256 indexed newValue, uint256 indexed oldValue);
    event ReflectionTokenChanged(address old_token, address new_token, address old_manager, address new_manager);
    event WithdrawnStuckTokens(address indexed token_address, uint256 amount, address recipient);
    event ProcessedReflectionDistribution(
        uint256 currentIndex,
        uint256 iterations,
        uint256 claims,
        bool indexed automatic,
        bool dismission_completed,
        uint256 gas,
        address indexed processor
    );
    event ProcessedReflectionDistributionOLD(
        uint256 currentIndex,
        uint256 iterations,
        uint256 claims,
        bool indexed automatic,
        bool dismission_completed,
        uint256 gas,
        address indexed processor
    );
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 BNBreceived,
        uint256 tokensIntoLiqudity
    );
    event SwapAndSendAutomaticBuyback(
        uint256 tokensSwapped,
        uint256 amount
    );
    event SwapAndSendReflectionManager(
        uint256 tokensSwapped,
        uint256 amount
    );
    
 

    constructor(address TGE_destination) BEP20("Powermade", "PWD") {
        uint256 totalSupply = (14000000) * (10**18);    // 14M PWD

        // DEFAULT MAINNET TOKENS AND PANCAKESWAP ROUTER
        reflectionToken = BEP20(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c);    // BTCB Mainnet
        automaticBuyback_cumulatedToken = BEP20(0xe9e7CEA3DedcA5984780Bafc599bD69ADd087D56);    // BUSD Mainnet
        pancakeRouter = IPancakeRouter02(0x10ED43C718714eb63d5aA57B78B54704E256024E);   // Router Mainnet
        
        // Configure router and create liquidity pair
        pancakePair = IPancakeFactory(pancakeRouter.factory()).createPair(address(this), pancakeRouter.WETH());

        // Create the Reflection Manager
        reflectionManager = new ReflectionManager();
        reflectionManager.initialize(address(reflectionToken));
        reflectionManager.setDistributionCriteria(6 hours, 10**12, REFLECTION_ELIGIBILITY_THRESHOLD);   // 6 hours deadtime, 0.00001 BTCB threshold, 2000 PWD (immutable)
        // Create the AutomaticBuyback manager
        automaticBuyback = new AutomaticBuyback();
        automaticBuyback.initialize(address(pancakeRouter), address(automaticBuyback_cumulatedToken), address(this));
        // Create the Locker for the automated liquidity LP tokens
        LP_locker = new LPLocker();   // initial lock for 2 years
        LP_locker.initialize(block.timestamp + 2 * 365 days);

        // Add the AMM pair
        _setAutomatedMarketMakerPair(pancakePair, true);

        // Exclude from Reflection
        reflectionManager.setReflectionDisabledWallet(address(reflectionManager), true);
        reflectionManager.setReflectionDisabledWallet(address(this), true);
        reflectionManager.setReflectionDisabledWallet(owner(), true);
        reflectionManager.setReflectionDisabledWallet(TGE_destination, true);
        reflectionManager.setReflectionDisabledWallet(address(pancakeRouter), true);
        reflectionManager.setReflectionDisabledWallet(address(pancakePair), true);
        reflectionManager.setReflectionDisabledWallet(address(automaticBuyback), true);
        reflectionManager.setReflectionDisabledWallet(address(LP_locker), true);
        // Exclude from Tax system
        _excludeFromFees(owner(), true);
        _excludeFromFees(address(this), true);
        _excludeFromFees(TGE_destination, true);
        _excludeFromFees(address(automaticBuyback), true);
        _excludeFromFees(address(LP_locker), true);
        _excludeFromFees(address(reflectionManager), true);
        // Exclude from Anti-Whale
        _setExcludedFromAntiWhale(owner(), true);
        _setExcludedFromAntiWhale(address(this), true);
        _setExcludedFromAntiWhale(TGE_destination, true);
        _setExcludedFromAntiWhale(address(automaticBuyback), true);
        _setExcludedFromAntiWhale(address(LP_locker), true);
        _setExcludedFromAntiWhale(address(reflectionManager), true);
        // Exclude from Cooldown
        _setExcludedFromCooldown(owner(), true);
        _setExcludedFromCooldown(address(this), true);
        _setExcludedFromCooldown(TGE_destination, true);
        _setExcludedFromCooldown(address(automaticBuyback), true);
        _setExcludedFromCooldown(address(LP_locker), true);
        _setExcludedFromCooldown(address(reflectionManager), true);
        // Snapshot feature
        _setCanSnapshotWallet(owner(), true);
        _setCanSnapshotWallet(TGE_destination, true);
        
        // Create the tokens
        _mint(TGE_destination, totalSupply);

    }

    // Fallback to receive the BNB when converting PWD to BNB (inside _swapAndLiquify function)
    receive() external payable {}

    // Override needed for the BEP20Snapshot inheritance 
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override(BEP20, BEP20Snapshot) {
        super._beforeTokenTransfer(from, to, amount);
    }

    // Override the _transferOwnership to add the extra settings when changing the owner
    function _transferOwnership(address newOwner) internal override {
        if (address(reflectionManager) == address(0)) {
            super._transferOwnership(newOwner); 
            return;
        }
        // Previous owner will become a normal wallet
        reflectionManager.setReflectionDisabledWallet(owner(), false);
        _excludeFromFees(owner(), false);
        _setExcludedFromAntiWhale(owner(), false);
        _setExcludedFromCooldown(owner(), false);
        _setCanSnapshotWallet(owner(), false);
        // Call the parent, that will transfer the ownership
        super._transferOwnership(newOwner);     
        // Set the excludes for the new owner
        reflectionManager.setReflectionDisabledWallet(owner(), true);
        _excludeFromFees(owner(), true);
        _setExcludedFromAntiWhale(owner(), true);
        _setExcludedFromCooldown(owner(), true);
        _setCanSnapshotWallet(owner(), true);
    }



    // ALL THE MAGIC IS HERE
    function _transfer(address from, address to, uint256 amount) internal override {

        require(from != address(0), "BEP20: transfer from the zero address");
        require(to != address(0), "BEP20: transfer to the zero address");
        require(!_isBlacklisted[from] && !_isBlacklisted[to], 'Address Blacklisted');
        if(amount == 0) {
            super._transfer(from, to, 0);
            return;
        }
        
        // Things to be processed only if not inside internal swapping (reentrancy) and if not from a multi-sender smart contract
        if (!swapping && !multisenderSmartContract[from]) {
            // Apply Anti-whale
            _checkAntiWhale(from, to, amount);
            // Apply Cooldown
            _applyCooldown(from, to);
        }

        // Things to be processed only if not inside internal swapping (reentrancy), if not from a multi-sender smart contract AND NOT A BUY OPERATION
        if (!swapping &&        // Not swapping internal
            !automatedMarketMakerPairs[from] &&     // Not a buy operation (internal swaps will fail if during buy operations)
            from != owner() &&      // Not owner as source/destination
            to != owner() &&
            !multisenderSmartContract[from]     // Not multi-send contract
        ) {

            // Process the automatic Buyback&Burn (if needed). The buyback has an internal swapping
            swapping = true;
            bool buyback_executed = automaticBuyback.trigger();
            if (buyback_executed) {
                // Burn all the tokens at the automaticBuyback address, reducing the supply
                _burn(address(automaticBuyback), balanceOf(address(automaticBuyback)));
            }
            swapping = false;

            // Decide if we have to process the cumulated tax, swapping to the needed tokens (BTCB and BUSD)
            uint256 contractTokenBalance = balanceOf(address(this));
            uint256 executeSwapFeature = tx_counter.mod(transactionsBeforeExecution);
            bool canSwap = executeSwapFeature < 3 && contractTokenBalance > 0;
            tx_counter++;   // Increase the counter
            if (canSwap) {
                swapping = true;
                if (amountBuybackTax > 0 && executeSwapFeature == 0) {
                    _swapAndSendAutomaticBuyback(amountBuybackTax);
                }
                if (amountLiquidityTax > 0 && executeSwapFeature == 1) {
                    _swapAndLiquify(amountLiquidityTax);
                }
                if (amountReflectionTax > 0 && executeSwapFeature == 2) {
                    _swapAndSendReflectionManager(amountReflectionTax);
                }
                swapping = false;
            }
        }

        // If not swapping, take the tax. This will happen on all transactions, buy and sell
        bool takeFee = !swapping;
        // if any account belongs to _isExcludedFromFee account or is a multi-sender smart contract then remove the tax
        if(_isExcludedFromFees[from] || _isExcludedFromFees[to] || multisenderSmartContract[from]) {
            takeFee = false;
        }
        if(takeFee) {
            uint256 reflection_amount = amount.mul(REFLECTION_TAX).div(100);
            uint256 buyback_amount = amount.mul(BUYBACK_AND_BURN_TAX).div(100);
            uint256 liquidity_amount = amount.mul(AUTOMATED_LIQUIDITY_TAX).div(100);
            uint256 total_tax_amount = reflection_amount.add(buyback_amount).add(liquidity_amount);
            // Apply tax
            amount = amount.sub(total_tax_amount);
            // Cumulate the tax (PWD) inside the contract
            super._transfer(from, address(this), total_tax_amount);
            // Update the storage variables
            amountReflectionTax = amountReflectionTax.add(reflection_amount);
            amountBuybackTax = amountBuybackTax.add(buyback_amount);
            amountLiquidityTax = amountLiquidityTax.add(liquidity_amount);
        }

        // Do the transfer
        super._transfer(from, to, amount);

        // Update and process the ReflectionManager (if not swapping, see the internal function)
        _updateAndProcessReflectionManagers(from, to);

    }



    // Swap the given amount of PWD to the automaticBuyback_cumulatedToken (BUSD) and send it to the AutomaticBuyback SC address
    function _swapAndSendAutomaticBuyback(uint256 amount) private {
        // Swap amount and send it to the Automatic buyback SC
        uint256 received_amount = _swapPWDtoTokenAndSendToRecipient(automaticBuyback_cumulatedToken, amount, address(automaticBuyback));
        // Update the local variable
        amountBuybackTax = amountBuybackTax.sub(amount);
        emit SwapAndSendAutomaticBuyback(amount, received_amount);
    }


    // Swap the given amount of PWD to the reflectionToken (BTCB) and send it to the ReflectionManager, updating the dividend-per-shares
    function _swapAndSendReflectionManager(uint256 amount) private {
        // Swap amount and send it to the reflection manager directly 
        uint256 received_amount = _swapPWDtoTokenAndSendToRecipient(reflectionToken, amount, address(reflectionManager));
        // Update the reflection manager
        reflectionManager.update_deposit(received_amount);
        // Update the local variable
        amountReflectionTax = amountReflectionTax.sub(amount);
        emit SwapAndSendReflectionManager(amount, received_amount);
    }


    // Swap half of the PWD amount to BNB and use the two to add liquidity on the DEX pair
    function _swapAndLiquify(uint256 amount) private {
       // split the contract balance into halves
        uint256 half = amount.div(2);
        uint256 otherHalf = amount.sub(half);
        uint256 initialBalance = address(this).balance;     // To exclude BNB already present in the contract
        uint256 initialBalancePWD = balanceOf(address(this));     // To count remaining in PWD
        // swap the first half to BNB
        _swapPWDtoBNB(half);
        // Get the obtained BNBs
        uint256 newBalance = address(this).balance.sub(initialBalance);
        // add liquidity to the pair
        _addLiquidityPWDandBNBpair(otherHalf, newBalance);
        // Real amount of PWD used to provide liquidity, ideally equal to amount (half+otherHalf)
        uint256 realPWDamountUsed = initialBalancePWD.sub(balanceOf(address(this)));
        amountLiquidityTax = amountLiquidityTax.sub(realPWDamountUsed);
        emit SwapAndLiquify(half, newBalance, realPWDamountUsed);
    }    


    // Swap PWD to the specified BEP20 Token, for tokenAmount quantity of PWD, and send the received tokens to the recipient address
    function _swapPWDtoTokenAndSendToRecipient(BEP20 token, uint256 tokenAmount, address recipient) private returns (uint256 amount_received) {
        address[] memory path = new address[](3);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();
        path[2] = address(token);
        _approve(address(this), address(pancakeRouter), tokenAmount);
        uint256 initialBalance = token.balanceOf(recipient);
        // make the swap
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            tokenAmount,
            0,      // Accept any amount of converted Token
            path,
            recipient,      // Send to the given recipient address
            block.timestamp
        );
        return token.balanceOf(recipient).sub(initialBalance);
    }    


    // Swap PWD to BNB (WBNB) sending the BNB to the PWD token address (that has the receive() fallback)
    function _swapPWDtoBNB(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = pancakeRouter.WETH();
        _approve(address(this), address(pancakeRouter), tokenAmount);
        // make the swap
        pancakeRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,      // accept any amount of BNB
            path,
            address(this),      // Receive the BNB in the contract (fallback function)
            block.timestamp
        );
    }


    // Add the liquidity to the PWD-WBNB pair on the DEX, sending the LP tokens directly to the LPLocker Vault
    function _addLiquidityPWDandBNBpair(uint256 tokenAmount, uint256 BNBamount) private {
        _approve(address(this), address(pancakeRouter), tokenAmount);
        // add the liquidity
        pancakeRouter.addLiquidityETH{value: BNBamount}(
            address(this),      // PWD
            tokenAmount,
            0,      // slippage is unavoidable
            0,      // slippage is unavoidable
            address(LP_locker),
            block.timestamp
        );
    }


    // Internal private function to update the shares in the ReflectionManager ad process the distribution with the configured gas (if not in swapping)
    function _updateAndProcessReflectionManagers(address from, address to) private {

        // Update the shares 
        reflectionManager.setShare(from, balanceOf(from));
        reflectionManager.setShare(to, balanceOf(to));

        // Continue only if not swapping and not from a multi-sender contract
        if (!swapping && !multisenderSmartContract[from]) {  
            uint256 gas = gasForProcessing;
            // Process the distribution (managing also the condition of reflectionToken change)
            if (address(reflectionManagerOld) != address(0)) {
                bool is_old_dismission_completed;
                ( , is_old_dismission_completed) = reflectionManagerOld.isDismission();
                if (is_old_dismission_completed) {
                    delete reflectionManagerOld;        // Clear the variable (it will return to address(0))
                } else {
                    gas = gas.div(2);      // Split the gas between the processes (Old and New)
                    // Process old
                    try reflectionManagerOld.process(gas) returns (uint256 currentIndex, uint256 iterations, uint256 claims, bool dismission_completed) {
                        emit ProcessedReflectionDistributionOLD(currentIndex, iterations, claims, true, dismission_completed, gas, tx.origin);
                    } catch { }
                }
            }
            // Process the current (Always) 
            try reflectionManager.process(gas) returns (uint256 currentIndex, uint256 iterations, uint256 claims, bool dismission_completed) {
                emit ProcessedReflectionDistribution(currentIndex, iterations, claims, true, dismission_completed, gas, tx.origin);
            } catch { }            
        }

    }


    // Anti-Whale check: applied to ALL transaction except BUY from AMM pairs
    function _checkAntiWhale(address sender, address recipient, uint256 amount) view private {
        uint256 maxTransferAmount = totalSupply().mul(maxTransferAmountRate).div(1000000);
        if (enableAntiwhale && !automatedMarketMakerPairs[sender]) {
            if (!_isExcludedFromAntiWhale[sender] && !_isExcludedFromAntiWhale[recipient]) {
                require(amount <= maxTransferAmount, "AntiWhale: amount too high!");
            }
        }
    }


    // Cooldown feature applied only to buy and sell operations on the defined automatedMarketMakerPairs
    // Applied only if feature enabled and addresses are not exempt
    function _applyCooldown(address sender, address recipient) private {
        if (cooldownEnabled && !_isTimelockExempt[sender] && !_isTimelockExempt[recipient] 
        ) {
            if (automatedMarketMakerPairs[sender]) {
                // Buy event - the sender is the pair
                // Require the Buy cooldown time from the last buy or sell event of the user
                require(block.timestamp > cooldownCheckpoint[recipient] + cooldownBuyInterval,"Cooldown: please wait!");
                cooldownCheckpoint[recipient] = block.timestamp;
            } else if (automatedMarketMakerPairs[recipient]) {
                // Sell event - the recipient is the pair
                // Require the Sell cooldown time from the last buy or sell event of the user
                require(block.timestamp > cooldownCheckpoint[sender] + cooldownSellInterval,"Cooldown: please wait!");
                cooldownCheckpoint[sender] = block.timestamp;
            }
        }
    }

    // Trigger the execution of the Tax conversion manually
    function swapManual() public onlyOwner {
        uint256 contractTokenBalance = balanceOf(address(this));
        require(contractTokenBalance > 0 , "token balance zero");
        swapping = true;
        if (amountBuybackTax > 0) {
            _swapAndSendAutomaticBuyback(amountBuybackTax);
        }
        if (amountLiquidityTax > 0) {
            _swapAndLiquify(amountLiquidityTax);
        }
        if (amountReflectionTax > 0) {
            _swapAndSendReflectionManager(amountReflectionTax);
        }
        swapping = false;
    }


    // Set a liquidity pair
    function _setAutomatedMarketMakerPair(address pair, bool value) private {
        automatedMarketMakerPairs[pair] = value;
        if(value) {
            reflectionManager.setReflectionDisabledWallet(pair, true);
        }
        emit SetAutomatedMarketMakerPair(pair, value);
    }


    // Set a Multi-sender smart contract (i.e. used to send airdrops). In this case the gas-intensive features won't be triggered during the transaction
    function setMultisenderSmartContract(address multisender_sc, bool value) external onlyOwner {
        _requireNotInternalAddresses(multisender_sc, true);
        require(!automatedMarketMakerPairs[multisender_sc], "Configuration: multisender_sc unallowed");
        multisenderSmartContract[multisender_sc] = value;
        emit SetMultisenderSmartContract(multisender_sc, value);
    }

    // Exclude (or re-include) a single wallet (or smart contract) from the tax system 
    function excludeFromFees(address account, bool excluded) public onlyOwner {
        _requireNotInternalAddresses(account, false);
        _excludeFromFees(account, excluded);
    }

    // _excludeFromFees internal function
    function _excludeFromFees(address account, bool excluded) internal {
        if (_isExcludedFromFees[account] != excluded) {
            _isExcludedFromFees[account] = excluded;
            emit ExcludeFromFees(account, excluded);
        }
    }

    // Exclude (or re-include) multiple wallets (or smart contracts) from the tax system 
    function excludeMultipleAccountsFromFees(address[] calldata accounts, bool excluded) external onlyOwner {
        require(accounts.length <= 10, "Configuration: max 10 accounts");
        for(uint256 i = 0; i < accounts.length; i++) {
            _requireNotInternalAddresses(accounts[i], false);
            _isExcludedFromFees[accounts[i]] = excluded;
        }
        emit ExcludeMultipleAccountsFromFees(accounts, excluded);
    }

    // Check if an address is excluded from the tax system
    function isExcludedFromFees(address account) public view returns(bool) {
        return _isExcludedFromFees[account];
    }

    // Exclude (or re-include) a single wallet (or smart contract) from the anti-whale system 
    function setExcludedFromAntiWhale(address account, bool excluded) public onlyOwner {
        _requireNotInternalAddresses(account, false);
        _setExcludedFromAntiWhale(account, excluded);
    }

    // _setExcludedFromAntiWhale internal function
    function _setExcludedFromAntiWhale(address account, bool excluded) internal {
        if (_isExcludedFromAntiWhale[account] != excluded) {
            _isExcludedFromAntiWhale[account] = excluded;
            emit ExcludeFromAntiWhale(account, excluded);
        }  
    }

    // Check if an address is excluded from the anti-whale system
    function isExcludedFromAntiWhale(address account) public view returns(bool) {
        return _isExcludedFromAntiWhale[account];
    }

    // Enable or disable Anti-Whale system
    function setEnableAntiwhale(bool _val) public onlyOwner {
        enableAntiwhale = _val;
        emit EnableDisableAntiWhale(_val);
    }

    // Exclude (or re-include) a single wallet (or smart contract) from the cooldown system
    function setExcludedFromCooldown(address account, bool excluded) public onlyOwner {
        _requireNotInternalAddresses(account, false);
        _setExcludedFromCooldown(account, excluded);
    }

    // _setExcludedFromCooldown internal function
    function _setExcludedFromCooldown(address account, bool excluded) internal {
        if (_isTimelockExempt[account] != excluded) {
            _isTimelockExempt[account] = excluded;
            emit ExcludeFromCooldown(account, excluded);
        }  
    }

    // Enable or Disable a wallet that can call the makeSnapshot() function
    function setCanSnapshotWallet(address account, bool can_snapshot) public onlyOwner {
        _requireNotInternalAddresses(account, true);
        _setCanSnapshotWallet(account, can_snapshot);
    }

    // _setCanSnapshotWallet internal function
    function _setCanSnapshotWallet(address account, bool can_snapshot) internal {
        _canSnapshot[account] = can_snapshot;
        emit SetCanSnapshotWallet(account, can_snapshot);
    }

    // Check if an address is excluded from the Cooldown system
    function isExcludedFromCooldown(address account) public view returns(bool) {
        return _isTimelockExempt[account];
    }

    // Enable or disable Cooldown system
    function setEnableCooldown(bool _val) public onlyOwner {
        cooldownEnabled = _val;
        emit EnableDisableCooldown(_val);
    }

    // Set the transaction amount that is considered a "Whale" in terms of a percentage of the supply (minimum 0.1%)
    function setMaxTransferAmountRate(uint256 _val) external onlyOwner {
        // Minimum value is 1000, the 0.1% of the supply
        require(_val >= 1000, "AntiWhale: minimum value is 1000");
        emit SetAntiWhaleMaxTransferRate(_val, maxTransferAmountRate);
        maxTransferAmountRate = _val;
    }

    // Set the cooldown period when selling on the AMM pair (for the cooldown feature)
    function setCooldownSellPeriod(uint256 _period_seconds) external onlyOwner {
        require(_period_seconds >= 1 minutes && _period_seconds <= 24 hours, "Cooldown: period >= 1m and <= 24h");
        emit SetCooldownSellPeriod(_period_seconds, cooldownSellInterval);
        cooldownSellInterval = _period_seconds;
    }

    // Set the cooldown period when buying on the AMM pair (for the cooldown feature)
    function setCooldownBuyPeriod(uint256 _period_seconds) external onlyOwner {
        require(_period_seconds >= 0 && _period_seconds <= 1 hours, "Cooldown: period <= 1h");
        cooldownBuyInterval = _period_seconds;
        emit SetCooldownBuyPeriod(_period_seconds, cooldownBuyInterval);
    }

    // Add or remove a new AMM pair (PancakeSwap and/or different DEXs)
    function setAutomatedMarketMakerPair(address pair, bool value) external onlyOwner {
        _requireNotInternalAddresses(pair, true);
        require(!multisenderSmartContract[pair], "Configuration: pair unallowed");
        _setAutomatedMarketMakerPair(pair, value);
    }

    // Set the number of transactions between each feature execution sequence
    function setNumberOfTransactionsBeforeExecution(uint256 _numberOfTransactions) external onlyOwner {
        require(_numberOfTransactions >= 3 && _numberOfTransactions < 100, "Configuration: value >=3 and <= 99");
        emit SetNumberOfTransaction(_numberOfTransactions, transactionsBeforeExecution);
        transactionsBeforeExecution = _numberOfTransactions;
    }

    // Add an account to the blacklist in case of hacks or regulatory compliance
    function blacklistAddress(address account, bool value) external onlyOwner {
        _requireNotInternalAddresses(account, true);
        emit SetBlacklisted(account, _isBlacklisted[account], value);
        _isBlacklisted[account] = value;
    }

    // Check if an account is blacklisted
    function isBlacklistedAddress(address account) public view returns (bool) {
        return _isBlacklisted[account];
    }

    // Change the gas used for the Reflection distribution
    function updateGasForProcessing(uint256 newValue) external onlyOwner {
        require(newValue >= 200000 && newValue <= 700000, "Configuration: GasForProcessing must be between 200,000 and 700,000");
        if (gasForProcessing != newValue) {
            emit GasForProcessingUpdated(newValue, gasForProcessing);
            gasForProcessing = newValue;
        } 
    }

    // Change the thresholds for the automatic reflection distribution
    function setReflectionDistributionCriteria(uint256 _minPeriod, uint256 _minDistribution) external onlyOwner {
        reflectionManager.setDistributionCriteria(_minPeriod, _minDistribution, REFLECTION_ELIGIBILITY_THRESHOLD);
    }

    // Enable or disable a reflection-receiving smart contract (other contracts excluded by default)
    function setReflectionEnabledContract(address _contractAddress, bool _enableDisable) external onlyOwner {
        _requireNotInternalAddresses(_contractAddress, true);
        reflectionManager.setReflectionEnabledContract(_contractAddress, _enableDisable);
    }

    // Disable or re-enable a reflection-receiving wallet
    function setReflectionDisabledWallet(address _walletAddress, bool _disableEnable) external onlyOwner {
        _requireNotInternalAddresses(_walletAddress, true);
        reflectionManager.setReflectionDisabledWallet(_walletAddress, _disableEnable);
    }

    function _requireNotInternalAddresses(address _walletAddress, bool includePancake) internal view {
        require(_walletAddress != owner() && 
                _walletAddress != address(0) && 
                _walletAddress != address(this) && 
                _walletAddress != address(automaticBuyback) &&
                _walletAddress != address(LP_locker) &&
                _walletAddress != address(reflectionManager), 
                "Configuration: cannot modify the given address");
        if (includePancake) {
            require(_walletAddress != address(pancakeRouter) && 
                    _walletAddress != address(pancakePair), 
                    "Configuration: cannot modify the given address");
        }
    }

    // Enable or disable the Reflection automatic claim for an address/shareholder
    function setReflectionAutoDistributionExcludeFlag(address _shareholder, bool _exclude) external  onlyOwner {
        reflectionManager.setAutoDistributionExcludeFlag(_shareholder, _exclude);
    }

    // Return Reflection Info of an account (shareholder)
    function getReflectionAccountInfo(address shareholder) public view returns (
            uint256 shareholder_id,     // it is index+1, zero if shareholder not in list
            uint256 currentShares,
            int256 iterationsUntilProcessed,
            uint256 withdrawableDividends,
            uint256 totalRealisedDividends,
            uint256 totalExcludedDividends,
            uint256 lastClaimTime,
            uint256 nextClaimTime,
            bool shouldAutoDistribute,
            bool excludedAutoDistribution,
            bool enabled ) {
        return reflectionManager.getAccountInfo(shareholder);
    }

    // Get the address of a Reflection shareholder given the index (from 0)
    function getReflectionShareholderAtIndex(uint256 index) public view returns (address) {
        return reflectionManager.getShareholderAtIndex(index);
    }

    // Returns global info of the reflection manager
    function getReflectionManagerInfo() public view returns (
            uint256 n_shareholders,
            uint256 current_index,
            uint256 manager_balance,
            uint256 total_shares,
            uint256 total_dividends,
            uint256 total_distributed,
            uint256 dividends_per_share,
            uint256 eligibility_threshold_shares,
            uint256 min_period,
            uint256 min_distribution,
            uint8 dismission ) {
        return reflectionManager.getReflectionManagerInfo();
    }

    // Manually process the dividend distribution (everyone can call this function). Suggested gas between 200,000 and 700,000
    function processReflectionDistribution(uint256 gas) external {
        (uint256 currentIndex, uint256 iterations, uint256 claims, bool dismission_completed) = reflectionManager.process(gas);
        emit ProcessedReflectionDistribution(currentIndex, iterations, claims, false, dismission_completed, gas, tx.origin);
    }

    // Manually process the dividend distribution of the OLD (marked for dismission) Reflection Manager (everyone can call this function). Suggested gas between 200,000 and 700,000
    function processReflectionDistributionOLD(uint256 gas) external {
        require(address(reflectionManagerOld) != address(0), "reflectionManagerOld not exists");
        (uint256 currentIndex, uint256 iterations, uint256 claims, bool dismission_completed) = reflectionManagerOld.process(gas);
        if (dismission_completed) {
            // Clear the old Reflection Manager (set the address to NULL address)
            delete reflectionManagerOld;
        }
        emit ProcessedReflectionDistributionOLD(currentIndex, iterations, claims, false, dismission_completed, gas, tx.origin);
    }

    function changeReflectionManager(address newUninitializedReflectionManager, address newReflectionToken, uint256 _minDistribution) external onlyOwner {
        require(address(reflectionManagerOld) == address(0), "Configuration: reflectionManagerOld still exists");
        _check_get_pair(pancakeRouter, newReflectionToken, true);
        // Initialize the passed uninitialized reflection manager, using the provided token address and the given min distribution value
        ReflectionManager new_reflection_manager = ReflectionManager(newUninitializedReflectionManager);
        new_reflection_manager.initialize(newReflectionToken);
        // Configure the new reflection manager
        new_reflection_manager.setDistributionCriteria(6 hours, _minDistribution, REFLECTION_ELIGIBILITY_THRESHOLD);
        // Exclude from Reflection. Remember to add manually the other addresses if any
        new_reflection_manager.setReflectionDisabledWallet(address(reflectionManager), true);
        new_reflection_manager.setReflectionDisabledWallet(address(reflectionManagerOld), true);
        new_reflection_manager.setReflectionDisabledWallet(address(this), true);
        new_reflection_manager.setReflectionDisabledWallet(owner(), true);
        new_reflection_manager.setReflectionDisabledWallet(address(pancakeRouter), true);
        new_reflection_manager.setReflectionDisabledWallet(address(pancakePair), true);
        new_reflection_manager.setReflectionDisabledWallet(address(automaticBuyback), true);
        new_reflection_manager.setReflectionDisabledWallet(address(LP_locker), true);
        // Other excludes
        _excludeFromFees(address(new_reflection_manager), true);
        _setExcludedFromAntiWhale(address(new_reflection_manager), true);
        _setExcludedFromCooldown(address(new_reflection_manager), true);
        // Change the reflection token 
        BEP20 old_reflectionToken = reflectionToken;
        reflectionToken = BEP20(newReflectionToken);
        // Set the current ReflectionManager as OLD and assign the new ReflectionManager
        reflectionManagerOld = reflectionManager;   
        reflectionManager = new_reflection_manager;
        // Dismiss the old reflection manager
        reflectionManagerOld.dismissReflectionManager();
        emit ReflectionTokenChanged(address(old_reflectionToken), address(reflectionToken), address(reflectionManagerOld), address(reflectionManager));
    }

    // Manually claim the reflection rewards of the sender
    function claimReflection() external {
        reflectionManager.claimDividend(_msgSender());
    }

    // Manually claim the reflection rewards of a shareholder
    function claimReflectionShareholder(address shareholder) external {
        reflectionManager.claimDividend(shareholder);
    }

    // Withdraw LP tokens from the Lp vault (if unlocked)
    function LPLockerWithdrawLP(address _LPaddress, uint256 _amount, address _to) external onlyOwner {
        LP_locker.withdrawLP(_LPaddress, _amount, _to);
    }

    // Update the Lock timestamp of the LPLocker
    function LPLockerUpdateLock(uint256 _newUnlockTimestamp) external onlyOwner {
        LP_locker.updateLock(_newUnlockTimestamp);
    }

    // Return the status of the LPLock vault, its address and the balance of the provided _LPaddress (if different from NULL address)
    function getLPLockerInfoLP(address _LPaddress) public view returns (address locker_address, uint256 LPbalance, uint256 unlock_timestamp, bool unlocked) {
        return LP_locker.getInfoLP(_LPaddress);
    }

    // External function to change the automatic buyback period between 30, 60 or 90 days
    function changeBuybackPeriod(uint256 newPeriod) external onlyOwner {
        automaticBuyback.changeBuybackPeriod(newPeriod);
    }

    // Change the cumulated token used for the automatic buyback
    function changeBuybackCumulatedToken(address newCumulatedTokenAddress) external onlyOwner {
        _check_get_pair(pancakeRouter, newCumulatedTokenAddress, true);
        automaticBuyback.changeCumulatedToken(newCumulatedTokenAddress);
        automaticBuyback_cumulatedToken = BEP20(newCumulatedTokenAddress);
    }

    // Return the current status of the AutomaticBuyback and the countdown to the next automatic buyback event
    function getAutomaticBuybackStatus() public view returns (
            address automatic_buyback_contract_address,
            uint256 next_buyback_timestamp,
            uint256 next_buyback_countdown,
            uint256 current_buyback_period,
            uint256 new_buyback_period,
            address current_cumulated_token,
            uint256 current_cumulated_balance,
            uint256 current_buyback_token_balance,
            uint256 total_buyed_back ) {
        return automaticBuyback.getAutomaticBuybackStatus();
    }

    // Switch/Change PancakeSwap Router
    function updatePancakeRouter(address newAddress) external onlyOwner {
        require(newAddress != address(pancakeRouter), "The router already has that address");
        IPancakeRouter02 _newRouter = IPancakeRouter02(newAddress);
        (bool pair_exists, address get_pair) = _check_get_pair(_newRouter, address(this), false);
        //checks if pair already exists
        if (!pair_exists) {
            // Create the new pair
            pancakePair = IPancakeFactory(_newRouter.factory()).createPair(address(this), _newRouter.WETH());
        }
        else {
            pancakePair = get_pair;
        }
        _setAutomatedMarketMakerPair(pancakePair, true);
        emit UpdatedPancakeRouter(newAddress, address(pancakeRouter), address(pancakePair));
        pancakeRouter = _newRouter;
        // Update address for the automatic buyback manager
        automaticBuyback.updateRouterAddress(address(pancakeRouter));
    }

    // Helper function to check a pair on Pancake
    function _check_get_pair(IPancakeRouter02 router, address token_addr, bool required) internal view returns (bool pair_exists, address pair) {
        pair = IPancakeFactory(router.factory()).getPair(token_addr, router.WETH());
        pair_exists = (pair != address(0));
        if (required) {
            require(pair_exists, "Configuration: not existent pair");
        }
    }

    // Withdraw stuck tokens inside the contract. Stuck tokens can be BNB or another token
    // It will be impossible to withdraw the PWD cumulated inside the token itself
    // The refection (BTCB) and the Buyback (BUSD) are managed by separated contract so the only allowed token inside this contract is PWD
    function withdrawStuckTokens(address token_address, uint256 amount, address recipient) external onlyOwner {
        if (token_address == address(0)) {
            // Withdraw stuck BNB
            uint256 available_amount = address(this).balance;
            amount = amount > available_amount ? available_amount : amount;     //coerce
            payable(recipient).transfer(amount);
        } else {
            // Withdraw Stuck tokens
            require(token_address != address(this), "Cannot withdraw the PWD!");
            BEP20 token_bep20 = BEP20(token_address);
            uint256 available_amount = token_bep20.balanceOf(address(this));
            amount = amount > available_amount ? available_amount : amount;     //coerce
            token_bep20.transfer(recipient, amount);
        }
        emit WithdrawnStuckTokens(token_address, amount, recipient);
    }

    // Function used to create a Snapshot by allowed people 
    function makeSnapshot() external {
        require(_canSnapshot[_msgSender()], "Not authorized");
        _snapshot();
    }


}