// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Note that this pool has no minter key of the reward token.
// Instead, the governance will send reward to this pool at the beginning.
contract SingleStakingRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    bool initialized = false;       // is pool initialized
    address public operator;        // governance

    // Info of each user.
    struct UserInfo {
        uint256 amount;             // How many tokens the user has provided.
        uint256 rewardDebt;         // Reward debt.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token;               // Address of staking token contract.
        uint256 allocPoint;         // How many allocation points assigned to this pool. 
        uint256 lastRewardTime;     // Last time that reward token distribution occurs.
        uint256 accRewardPerShare;  // Accumulated reward token per share, times 1e18. See below.
        bool isStarted;             // if lastRewardBlock has passed
    }

    PoolInfo[] public poolInfo;
    IERC20 public stakingToken;
    IERC20 public rewardToken;

    // Withdrawal fees
    bool public enableFees = true;
    address public feeWallet;
    uint256[] public stakingTires = [21 days, 15 days, 7 days];
    uint256[] public feeTires = [500, 200, 100];

    // Info of each user that stakes tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    uint256 public poolStartTime;           // The time when reward token mining starts.
    uint256 public poolEndTime;             // The time when reward token mining ends.
    uint256 public totalRewards;            // The amount of reward tokens
    uint256 public runningTime = 30 days;   // Pool running time
    uint256 public rewardPerSecond;         // Amount of reward tokens per second

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor() public {
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "Caller is not the operator");
        _;
    }

    function init(address _stakingToken, address _rewardToken, address _feeWallet, uint256 _poolStartTime, uint256 _runningTime) public onlyOperator {
        require(!initialized, "already initialized");
        require(_poolStartTime > block.timestamp, "late");
        require(_stakingToken != address(0) && _rewardToken != address(0) && _feeWallet != address(0), "invalid addresses");

        stakingToken = IERC20(_stakingToken);
        rewardToken = IERC20(_rewardToken);
        feeWallet = _feeWallet;
        poolStartTime = _poolStartTime;
        runningTime = _runningTime;
        poolEndTime = poolStartTime + runningTime;

        totalRewards = rewardToken.balanceOf(address(this));
        require(totalRewards > 0, "pool is empty");

        rewardPerSecond = totalRewards.div(runningTime);

        _add(1, stakingToken, false, 0);

        initialized = true;
    }

    function getFeePercent() public view returns (uint256) {
        if (poolEndTime <= block.timestamp) {
            return 0;
        }

        uint256 timeLeft = poolEndTime.sub(block.timestamp);
        uint256 feePercent;
        for (uint256 i = 0; i < stakingTires.length; i++) {
            if (timeLeft >= stakingTires[i]) {
                feePercent = feeTires[i];
                break;
            }
        }

        return feePercent;
    }

    function _checkPoolDuplicate(IERC20 _token) private view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "Existing pool?");
        }
    }

    // Add a staking token to the pool. Can only be called by the owner.
    function _add(uint256 _allocPoint, IERC20 _token, bool _withUpdate, uint256 _lastRewardTime) private onlyOperator {
        _checkPoolDuplicate(_token);
        if (_withUpdate) {
            massUpdatePools();
        }

        if (block.timestamp < poolStartTime) {
            // chef is sleeping
            if (_lastRewardTime == 0) {
                _lastRewardTime = poolStartTime;
            } else {
                if (_lastRewardTime < poolStartTime) {
                    _lastRewardTime = poolStartTime;
                }
            }
        } else {
            // chef is cooking
            if (_lastRewardTime == 0 || _lastRewardTime < block.timestamp) {
                _lastRewardTime = block.timestamp;
            }
        }

        bool _isStarted = (_lastRewardTime <= poolStartTime) || (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({token: _token, allocPoint: _allocPoint, lastRewardTime: _lastRewardTime, accRewardPerShare: 0, isStarted: _isStarted}));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(rewardPerSecond);
            return poolEndTime.sub(_fromTime).mul(rewardPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(rewardPerSecond);
            return _toTime.sub(_fromTime).mul(rewardPerSecond);
        }
    }

    // View function to see pending reward token on frontend.
    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _reward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accRewardPerShare = accRewardPerShare.add(_reward.mul(1e18).div(tokenSupply));
        }

        return user.amount.mul(accRewardPerShare).div(1e18).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.timestamp <= pool.lastRewardTime) {
            return;
        }

        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (tokenSupply == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }

        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }

        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _reward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accRewardPerShare = pool.accRewardPerShare.add(_reward.mul(1e18).div(tokenSupply));
        }

        pool.lastRewardTime = block.timestamp;
    }

    // Deposit staking tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
         require(initialized, "not initialized");

        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeRewardTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        
        uint256 depositAmount;
        if (_amount > 0) {
            uint256 balanceBefore = pool.token.balanceOf(address(this));
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            uint256 balanceAfter = pool.token.balanceOf(address(this));
            depositAmount = balanceAfter.sub(balanceBefore);

            user.amount = user.amount.add(depositAmount);
        }

        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Deposit(_sender, _pid, depositAmount);
    }

    // Withdraw tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: wrong amount");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accRewardPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeRewardTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            uint256 fee = _amount.mul(getFeePercent()).div(10000);
            if (enableFees && fee > 0) {
                pool.token.safeTransfer(feeWallet, fee);
                pool.token.safeTransfer(_sender, _amount.sub(fee));
            } else {
                pool.token.safeTransfer(_sender, _amount);
            }
        }

        user.rewardDebt = user.amount.mul(pool.accRewardPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.token.safeTransfer(msg.sender, _amount);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe DIBS transfer function, just in case if rounding error causes pool to not have enough DIBSs.
    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 _balance = rewardToken.balanceOf(address(this));
        if (_balance > 0) {
            if (_amount > _balance) {
                rewardToken.safeTransfer(_to, _balance);
            } else {
                rewardToken.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setFeeWallet(address _feeWallet) external onlyOperator {
        feeWallet = _feeWallet;
    }

    function setFeesStatus(bool _enableFees) external onlyOperator {
        enableFees = _enableFees;
    }

    function setStakingTiersEntry(uint8 _index, uint256 _value) external onlyOperator {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < stakingTires.length, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value < stakingTires[_index - 1]);
        }

        if (_index < stakingTires.length - 1) {
            require(_value > stakingTires[_index + 1]);
        }

        stakingTires[_index] = _value;
    }

    function setFeeTiersEntry(uint8 _index, uint256 _value) external onlyOperator {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < feeTires.length, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 2000, "_value: out of range"); // [0.1%, 20%]
        feeTires[_index] = _value;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 10 days) {
            // do not allow to drain staking token if less than 10 days after pool ends
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }

        _token.safeTransfer(to, amount);
    }

    // Withdraw reward tokens. EMERGENCY ONLY.
    function drainPool(address to) public onlyOperator {
        rewardToken.safeTransfer(to, rewardToken.balanceOf(address(this)));
        enableFees = false; // disable withdrawal fees
    }
}