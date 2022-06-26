// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

// Note that this pool has no minter key of MainToken (rewards).
// Instead, the governance will call MainToken distributeReward method and send reward to this pool at the beginning.
contract GenesisRewardPool is OwnableUpgradeable {// for development
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. MainToken to distribute.
        uint256 lastRewardTime; // Last time that MainToken distribution occurs.
        uint256 accMainTokenPerShare; // Accumulated MainToken per share, times 1e18. See below.
        bool isStarted; // if lastRewardBlock has passed
        bool isUpdated;
    }

    IERC20 public mainToken;
    address public mim;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The time when MainToken mining starts.
    uint256 public poolStartTime;

    // The time when MainToken mining ends.
    uint256 public poolEndTime;

    bool public updatedPoolNextPhase = false;

    uint256 public constant TOTAL_REWARD_POOL_2_NEXT_PHASE = 8568 ether; // 70% of (85% of 14400)
    uint256 public constant TOTAL_REWARD_POOL_1_NEXT_PHASE = 1836 ether; // 15% of (85% of 14400)
    uint256 public constant TOTAL_REWARD_POOL_0_NEXT_PHASE = 1836 ether; // 15% of (85% of 14400)


    // todo: TESTNET
    // uint256 public mainTokenPerSecond = 5.1 ether; // 18360 Token / (1h * 60min * 60s)
    // uint256 public runningTime = 1 hours; // 1 hours
    // uint256 public constant TOTAL_REWARDS = 18360 ether; //(85% of 21600)
    // END TESTNET

    // MAINNET
    uint256 public mainTokenPerSecond = 0.070833 ether; // 18360 Token / (72h * 60min * 60s)
    uint256 public runningTime = 72 hours;
    uint256 public constant TOTAL_REWARDS = 18360 ether; //(85% of 21600)
    // END MAINNET

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _token,
        uint256 _poolStartTime) {
        require(block.timestamp < _poolStartTime, "late");
        if (_token != address(0)) mainToken = IERC20(_token);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "GenesisPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "GenesisPool: existing pool?");
        }
    }

    // Add a new token to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperator {
        checkPoolDuplicate(_token);
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
        poolInfo.push(PoolInfo({token: _token, allocPoint: _allocPoint, lastRewardTime: _lastRewardTime, accMainTokenPerShare: 0, isStarted: _isStarted, isUpdated: false}));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's MainToken allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
        pool.isUpdated = true;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(mainTokenPerSecond);
            return poolEndTime.sub(_fromTime).mul(mainTokenPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(mainTokenPerSecond);
            return _toTime.sub(_fromTime).mul(mainTokenPerSecond);
        }
    }

    // View function to see pending MainToken on frontend.
    function pending(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMainTokenPerShare = pool.accMainTokenPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _mainTokenReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accMainTokenPerShare = accMainTokenPerShare.add(_mainTokenReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accMainTokenPerShare).div(1e18).sub(user.rewardDebt);
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
            uint256 _mainTokenReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accMainTokenPerShare = pool.accMainTokenPerShare.add(_mainTokenReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accMainTokenPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeMainTokenTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMainTokenPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accMainTokenPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeMainTokenTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accMainTokenPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        if (_amount > 0) {
            pool.token.safeTransfer(msg.sender, _amount);
        }
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe MainToken transfer function, just in case a rounding error causes pool to not have enough MainTokens.
    function safeMainTokenTransfer(address _to, uint256 _amount) internal {
        uint256 _mainTokenBalance = mainToken.balanceOf(address(this));
        if (_mainTokenBalance > 0) {
            if (_amount > _mainTokenBalance) {
                mainToken.safeTransfer(_to, _mainTokenBalance);
            } else {
                mainToken.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (MainToken or lps) if less than 90 days after pool ends
            require(_token != mainToken, "mainToken");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }

    function updatePoolNextPhase() external onlyOperator {
        require(!updatedPoolNextPhase, "only can update once");
        updatedPoolNextPhase = true;
        set(1, TOTAL_REWARD_POOL_1_NEXT_PHASE);
        set(0, TOTAL_REWARD_POOL_0_NEXT_PHASE);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IMainToken.sol";

contract NodePool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 lastTimeReward;
        uint256 timeStart;
    }

    struct UserTicket {
        uint256 numTicket;
    }

    struct DevFundInfo {
        uint256 lastRewardTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ShareToken to distribute per block.
        uint256 lastRewardTime; // Last time that ShareToken distribution occurs.
        uint256 accShareTokenPerShare; // Accumulated ShareToken per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
        uint256 lockTime; // 1 week, 2, weeks, 3 weeks
        uint256 totalPoolStaked; // total pool staked
    }

    IERC20 public shareToken;
    IMainToken public mainToken;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => UserTicket) public userTickets;
    uint256 public totalTickets = 0;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when wine mining starts.
    uint256 public poolStartTime;

    // The time when wine mining ends.
    uint256 public poolEndTime;

    uint256 public shareTokenPerSecond = 0.00134767 ether; // 42500 tokens / (365 days * 24h * 60min * 60s)
    uint256 public runningTime = 365 days; // 365 days
    uint256 public constant TOTAL_REWARDS = 42500 ether;

    uint256 public maxPercentToStake = 21; //21%

    uint256 public constant DAO_FUND_POOL_ALLOCATION = 3750 ether;
    uint256 public shareTokenPerSecondForDaoFund = 0.00011891 ether;
    uint256 public lastDaoFundRewardTime;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 3750 ether;
    uint256 public shareTokenPerSecondForDevFund = 0.00011891 ether;
    mapping(address => DevFundInfo) public devFundInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _shareToken,
        address _mainToken,
        uint256 _poolStartTime
    ) {
        require(block.timestamp < _poolStartTime, "late");
        if (_shareToken != address(0)) shareToken = IERC20(_shareToken);
        if (_mainToken != address(0)) mainToken = IMainToken(_mainToken);
        poolStartTime = _poolStartTime;
        lastDaoFundRewardTime = poolStartTime;
        address[] memory devFunds = mainToken.getDevFunds();
        for (uint8 i = 0; i < devFunds.length; i++) {
            devFundInfo[devFunds[i]].lastRewardTime = poolStartTime;
        }
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "NodePool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(uint256 _lockTime) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].lockTime != _lockTime, "NodePool: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime,
        uint256 _lockTime
    ) public onlyOperator {
        checkPoolDuplicate(_lockTime);
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
        bool _isStarted = (_lastRewardTime <= poolStartTime) ||
            (_lastRewardTime <= block.timestamp);
        poolInfo.push(
            PoolInfo({
                token: _token,
                allocPoint: _allocPoint,
                lastRewardTime: _lastRewardTime,
                accShareTokenPerShare: 0,
                isStarted: _isStarted,
                lockTime: _lockTime,
                totalPoolStaked: 0
            })
        );
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's ShareToken allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime)
        public
        view
        returns (uint256)
    {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime)
                return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecond);
            return poolEndTime.sub(_fromTime).mul(shareTokenPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime)
                return _toTime.sub(poolStartTime).mul(shareTokenPerSecond);
            return _toTime.sub(_fromTime).mul(shareTokenPerSecond);
        }
    }

    // View function to see pending Wine on frontend.
    function pendingShare(uint256 _pid, address _user)
        external
        view
        returns (uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accShareTokenPerShare = pool.accShareTokenPerShare;
        uint256 totalTokenStaked = pool.totalPoolStaked;
        if (block.timestamp > pool.lastRewardTime && totalTokenStaked != 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _shareTokenReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            
            accShareTokenPerShare = accShareTokenPerShare.add(
                _shareTokenReward.mul(1e18).div(totalTokenStaked)
            );
        }

        uint256 daoFundReward = pendingDaoFund(lastDaoFundRewardTime, block.timestamp, _user);
        uint256 devFundReward = pendingDevFund(devFundInfo[_user].lastRewardTime, block.timestamp, _user);

        uint256 pendingUser = user.amount.mul(accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
        return pendingUser.add(daoFundReward).add(devFundReward);
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
        uint256 totalTokenStaked = pool.totalPoolStaked;
        if (totalTokenStaked == 0) {
            pool.lastRewardTime = block.timestamp;
            return;
        }
        if (!pool.isStarted) {
            pool.isStarted = true;
            totalAllocPoint = totalAllocPoint.add(pool.allocPoint);
        }
        if (totalAllocPoint > 0) {
            uint256 _generatedReward = getGeneratedReward(
                pool.lastRewardTime,
                block.timestamp
            );
            uint256 _shareTokenReward = _generatedReward.mul(pool.allocPoint).div(
                totalAllocPoint
            );
            pool.accShareTokenPerShare = pool.accShareTokenPerShare.add(
                _shareTokenReward.mul(1e18).div(totalTokenStaked)
            );
        }
        pool.lastRewardTime = block.timestamp;
    }

    function pendingDaoFund(uint256 _fromTime, uint256 _toTime, address _user) internal view returns (uint256) {
        if (mainToken.isDaoFund(_user)) {
            if (_fromTime >= _toTime) return 0;
            if (_toTime >= poolEndTime) {
                if (_fromTime >= poolEndTime) return 0;
                if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecondForDaoFund);
                return poolEndTime.sub(_fromTime).mul(shareTokenPerSecondForDaoFund);
            } else {
                if (_toTime <= poolStartTime) return 0;
                if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(shareTokenPerSecondForDaoFund);
                return _toTime.sub(_fromTime).mul(shareTokenPerSecondForDaoFund);
            }
        }

        return 0;
    }

    function pendingDevFund(uint256 _fromTime, uint256 _toTime, address _user) internal view returns (uint256) {
        (bool _isDevFund, uint256 length) = mainToken.isDevFund(_user);
        if (_isDevFund) {
            if (_fromTime >= _toTime) return 0;
            if (_toTime >= poolEndTime) {
                if (_fromTime >= poolEndTime) return 0;
                if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecondForDevFund).div(length);
                return poolEndTime.sub(_fromTime).mul(shareTokenPerSecondForDevFund).div(length);
            } else {
                if (_toTime <= poolStartTime) return 0;
                if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(shareTokenPerSecondForDevFund).div(length);
                return _toTime.sub(_fromTime).mul(shareTokenPerSecondForDevFund).div(length);
            }
        }

        return 0;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        uint256 poolBalance = pool.totalPoolStaked;
        uint256 maxTokenCanStake = getMaxTokenCanStake();
        bool canStake = _amount.add(poolBalance) < maxTokenCanStake;
        require(canStake, "Max token stake < 20% Circulating supply");

        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeShareTokenTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
                user.timeStart = block.timestamp;
                user.lastTimeReward = block.timestamp;
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            pool.totalPoolStaked = pool.totalPoolStaked.add(_amount);
            user.amount = user.amount.add(_amount);
            user.timeStart = block.timestamp;

            uint256 numTicket = caculateTicket(_pid, _amount);
            userTickets[_sender].numTicket = userTickets[_sender].numTicket.add(numTicket);
            totalTickets = totalTickets.add(numTicket);
        }
        user.rewardDebt = user.amount.mul(pool.accShareTokenPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    function getMainTokenCirculatingSupply() public view returns (uint256) {
        uint256 totalSupply = mainToken.totalSupply();
        address[] memory excludedFromTotalSupply = mainToken.getExcluded();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(mainToken.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function getMaxTokenCanStake() public view returns (uint256) {
        uint256 totalSupply = mainToken.totalSupply();
        return totalSupply.mul(maxPercentToStake).div(3 * 100);
    }

    function getPoolAvailableStake(uint256 _pid) public view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        uint256 maxTokenCanStake = getMaxTokenCanStake();
        if (pool.totalPoolStaked >= maxTokenCanStake) {
            return 0;
        }

        return maxTokenCanStake.sub(pool.totalPoolStaked);
    }

    function getNumTicket(address who) public view returns (uint256) {
       return userTickets[who].numTicket;
    }

    function raffle() public view returns (uint256) {
        return totalTickets;
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool(_pid);
        uint256 _daoFundReward = pendingDaoFund(lastDaoFundRewardTime, block.timestamp, _sender);
        uint256 _devFundReward = pendingDevFund(devFundInfo[_sender].lastRewardTime, block.timestamp, _sender);
        if (_daoFundReward > 0) {
            safeShareTokenTransfer(_sender, _daoFundReward);
            lastDaoFundRewardTime = block.timestamp;
            emit RewardPaid(_sender, _daoFundReward);
        }

        if (_devFundReward > 0) {
            safeShareTokenTransfer(_sender, _devFundReward);
            devFundInfo[_sender].lastRewardTime = block.timestamp;
            emit RewardPaid(_sender, _devFundReward);
        }

        uint256 _pending = user.amount.mul(pool.accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
        uint256 timeStart = user.timeStart;
        if (_pending > 0) {
            uint256 duringTime = block.timestamp.sub(user.lastTimeReward);
            require(duringTime > pool.lockTime, "Not enough time to claim reward");
            safeShareTokenTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
            user.lastTimeReward = block.timestamp;
            timeStart = block.timestamp;
        }
        if (_amount > 0) {
            uint256 duringTime = block.timestamp.sub(user.timeStart);
            require(duringTime > pool.lockTime, "Not enough time to withdraw");
            pool.totalPoolStaked = pool.totalPoolStaked.sub(_amount);
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
            timeStart = block.timestamp;

            uint256 numTicket = caculateTicket(_pid, _amount);
            userTickets[_sender].numTicket = userTickets[_sender].numTicket.sub(numTicket);
            totalTickets = totalTickets.sub(numTicket);
        }
        
        user.timeStart = timeStart;
        user.rewardDebt = user.amount.mul(pool.accShareTokenPerShare).div(1e18);
        emit Withdraw(_sender, _pid, _amount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 _amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.totalPoolStaked = pool.totalPoolStaked.add(_amount);
        pool.token.safeTransfer(msg.sender, _amount);

        uint256 numTicket = caculateTicket(_pid, _amount);
        userTickets[msg.sender].numTicket = userTickets[msg.sender].numTicket.sub(numTicket);
        totalTickets = totalTickets.sub(numTicket);
        emit EmergencyWithdraw(msg.sender, _pid, _amount);
    }

    // Safe ShareToken transfer function, just in case if rounding error causes pool to not have enough ShareToken.
    function safeShareTokenTransfer(address _to, uint256 _amount) internal {
        uint256 _shareTokenBalance = shareToken.balanceOf(address(this));
        if (_shareTokenBalance > 0) {
            if (_amount > _shareTokenBalance) {
                shareToken.safeTransfer(_to, _shareTokenBalance);
            } else {
                shareToken.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function caculateTicket(uint256 _pid, uint256 _amount) internal pure returns (uint256) {
        if (_pid == 0) {
            return _amount.div(100*1e18);
        } else if (_pid == 1) {
            return _amount.mul(2).div(100*1e18);
        } else if (_pid == 2) {
            return _amount.mul(3).div(100*1e18);
        }
        return 0;
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 amount,
        address to
    ) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (ShareToken or lps) if less than 90 days after pool ends
            require(_token != shareToken, "shareToken");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "../interfaces/IMainToken.sol";

// Note that this pool has no minter key of ShareToken (rewards).
// Instead, the governance will call ShareToken distributeReward method and send reward to this pool at the beginning.
contract ShareTokenRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    struct DevFundInfo {
        uint256 lastRewardTime;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. ShareToken to distribute per block.
        uint256 lastRewardTime; // Last time that ShareToken distribution occurs.
        uint256 accShareTokenPerShare; // Accumulated ShareToken per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    IERC20 public shareToken;
    address public mainToken;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when ShareToken mining starts.
    uint256 public poolStartTime;

    // The time when ShareToken mining ends.
    uint256 public poolEndTime;

    uint256 public shareTokenPerSecond = 0.017520 ether; // 552500 tokens / (365 days * 24h * 60min * 60s)
    uint256 public runningTime = 365 days; // 365 days
    uint256 public constant TOTAL_REWARDS = 552500 ether; // (85% of 700000)

    uint256 public constant DAO_FUND_POOL_ALLOCATION = 48750 ether;
    uint256 public shareTokenPerSecondForDaoFund = 0.001546 ether;
    uint256 lastDaoFundRewardTime;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 48750 ether;
    uint256 public shareTokenPerSecondForDevFund = 0.001546 ether;
    mapping(address => DevFundInfo) public devFundInfo;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _token,
        address _mainToken,
        uint256 _poolStartTime
    ) {
        require(block.timestamp < _poolStartTime, "late");
        if (_token != address(0)) shareToken = IERC20(_token);
        mainToken = _mainToken;
        poolStartTime = _poolStartTime;
        lastDaoFundRewardTime = poolStartTime;
        address[] memory devFunds = IMainToken(_mainToken).getDevFunds();
        for (uint8 i = 0; i < devFunds.length; i++) {
            devFundInfo[devFunds[i]].lastRewardTime = poolStartTime;
        }
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "ShareTokenRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "ShareTokenRewardPool: existing pool?");
        }
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _token,
        bool _withUpdate,
        uint256 _lastRewardTime
    ) public onlyOperator {
        checkPoolDuplicate(_token);
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
        bool _isStarted =
        (_lastRewardTime <= poolStartTime) ||
        (_lastRewardTime <= block.timestamp);
        poolInfo.push(PoolInfo({
            token : _token,
            allocPoint : _allocPoint,
            lastRewardTime : _lastRewardTime,
            accShareTokenPerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's ShareToken allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(
                _allocPoint
            );
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _from to _to block.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        if (_fromTime >= _toTime) return 0;
        if (_toTime >= poolEndTime) {
            if (_fromTime >= poolEndTime) return 0;
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecond);
            return poolEndTime.sub(_fromTime).mul(shareTokenPerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(shareTokenPerSecond);
            return _toTime.sub(_fromTime).mul(shareTokenPerSecond);
        }
    }

    // View function to see pending Wine on frontend.
    function pendingShare(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accShareTokenPerShare = pool.accShareTokenPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _shareTokenReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accShareTokenPerShare = accShareTokenPerShare.add(_shareTokenReward.mul(1e18).div(tokenSupply));
        }

        uint256 daoFundReward = pendingDaoFund(lastDaoFundRewardTime, block.timestamp, _user);
        uint256 devFundReward = pendingDevFund(devFundInfo[_user].lastRewardTime, block.timestamp, _user);

        uint256 pendingUser = user.amount.mul(accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
        return pendingUser.add(daoFundReward).add(devFundReward);
    }

    function pendingDaoFund(uint256 _fromTime, uint256 _toTime, address _user) internal view returns (uint256) {
        if (IMainToken(mainToken).isDaoFund(_user)) {
            if (_fromTime >= _toTime) return 0;
            if (_toTime >= poolEndTime) {
                if (_fromTime >= poolEndTime) return 0;
                if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecondForDaoFund);
                return poolEndTime.sub(_fromTime).mul(shareTokenPerSecondForDaoFund);
            } else {
                if (_toTime <= poolStartTime) return 0;
                if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(shareTokenPerSecondForDaoFund);
                return _toTime.sub(_fromTime).mul(shareTokenPerSecondForDaoFund);
            }
        }

        return 0;
    }

    function pendingDevFund(uint256 _fromTime, uint256 _toTime, address _user) internal view returns (uint256) {
        (bool _isDevFund, uint256 length) = IMainToken(mainToken).isDevFund(_user);
        if (_isDevFund) {
            if (_fromTime >= _toTime) return 0;
            if (_toTime >= poolEndTime) {
                if (_fromTime >= poolEndTime) return 0;
                if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(shareTokenPerSecondForDevFund).div(length);
                return poolEndTime.sub(_fromTime).mul(shareTokenPerSecondForDevFund).div(length);
            } else {
                if (_toTime <= poolStartTime) return 0;
                if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(shareTokenPerSecondForDevFund).div(length);
                return _toTime.sub(_fromTime).mul(shareTokenPerSecondForDevFund).div(length);
            }
        }

        return 0;
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
            uint256 _shareTokenReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accShareTokenPerShare = pool.accShareTokenPerShare.add(_shareTokenReward.mul(1e18).div(tokenSupply));
        }
        pool.lastRewardTime = block.timestamp;
    }

    // Deposit LP tokens.
    function deposit(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 _pending = user.amount.mul(pool.accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeShareTokenTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accShareTokenPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accShareTokenPerShare).div(1e18).sub(user.rewardDebt);
        uint256 _daoFundReward = pendingDaoFund(lastDaoFundRewardTime, block.timestamp, _sender);
        uint256 _devFundReward = pendingDevFund(devFundInfo[_sender].lastRewardTime, block.timestamp, _sender);
        if (_daoFundReward > 0) {
            safeShareTokenTransfer(_sender, _daoFundReward);
            lastDaoFundRewardTime = block.timestamp;
            emit RewardPaid(_sender, _daoFundReward);
        }

        if (_devFundReward > 0) {
            safeShareTokenTransfer(_sender, _devFundReward);
            devFundInfo[_sender].lastRewardTime = block.timestamp;
            emit RewardPaid(_sender, _devFundReward);
        }

        if (_pending > 0) {
            safeShareTokenTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accShareTokenPerShare).div(1e18);
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

    // Safe ShareToken transfer function, just in case if rounding error causes pool to not have enough ShareToken.
    function safeShareTokenTransfer(address _to, uint256 _amount) internal {
        uint256 _shareTokenBalance = shareToken.balanceOf(address(this));
        if (_shareTokenBalance > 0) {
            if (_amount > _shareTokenBalance) {
                shareToken.safeTransfer(_to, _shareTokenBalance);
            } else {
                shareToken.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 90 days) {
            // do not allow to drain core token (ShareToken or lps) if less than 90 days after pool ends
            require(_token != shareToken, "ShareToken");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/ITreasury.sol";

contract ShareWrapper {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    IERC20 public share;

    uint256 private _totalSupply;
    mapping(address => uint256) private _balances;

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return _balances[account];
    }

    function stake(uint256 amount) public virtual {
        _totalSupply = _totalSupply.add(amount);
        _balances[msg.sender] = _balances[msg.sender].add(amount);
        share.safeTransferFrom(msg.sender, address(this), amount);
    }

    function withdraw(uint256 amount) public virtual {
        uint256 memberShare = _balances[msg.sender];
        require(memberShare >= amount, "Boardroom: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = memberShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Boardroom is ShareWrapper, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct BoardroomSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    IERC20 public mainToken;
    ITreasury public treasury;

    mapping(address => Memberseat) public members;
    BoardroomSnapshot[] public boardroomHistory;

    uint256 public withdrawLockupEpochs;
    uint256 public rewardLockupEpochs;

    /* ========== EVENTS ========== */

    event Initialized(address indexed executor, uint256 at);
    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);
    event RewardPaid(address indexed user, uint256 reward);
    event RewardAdded(address indexed user, uint256 reward);

    /* ========== Modifiers =============== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Boardroom: caller is not the operator");
        _;
    }

    modifier memberExists() {
        require(balanceOf(msg.sender) > 0, "Boardroom: The member does not exist");
        _;
    }

    modifier updateReward(address member) {
        if (member != address(0)) {
            Memberseat memory seat = members[member];
            seat.rewardEarned = earned(member);
            seat.lastSnapshotIndex = latestSnapshotIndex();
            members[member] = seat;
        }
        _;
    }

    modifier notInitialized() {
        require(!initialized, "Boardroom: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */
    function initialize(
        IERC20 _mainToken,
        IERC20 _shareToken,
        ITreasury _treasury
    ) public notInitialized {
        mainToken = _mainToken;
        share = _shareToken;
        treasury = _treasury;

        BoardroomSnapshot memory genesisSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        boardroomHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 4; // Lock for 4 epochs (24h) before release withdraw
        rewardLockupEpochs = 2; // Lock for 2 epochs (12h) before release claimReward

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        require(_withdrawLockupEpochs >= _rewardLockupEpochs && _withdrawLockupEpochs <= 56, "_withdrawLockupEpochs: out of range"); // <= 2 week
        withdrawLockupEpochs = _withdrawLockupEpochs;
        rewardLockupEpochs = _rewardLockupEpochs;
    }

    /* ========== VIEW FUNCTIONS ========== */

    // =========== Snapshot getters

    function latestSnapshotIndex() public view returns (uint256) {
        return boardroomHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member) internal view returns (BoardroomSnapshot memory) {
        return boardroomHistory[getLastSnapshotIndexOf(member)];
    }

    function canWithdraw(address member) external view returns (bool) {
        return members[member].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch();
    }

    function canClaimReward(address member) external view returns (bool) {
        return members[member].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch();
    }

    function epoch() external view returns (uint256) {
        return treasury.epoch();
    }

    function nextEpochPoint() external view returns (uint256) {
        return treasury.nextEpochPoint();
    }

    function getMainTokenPrice() external view returns (uint256) {
        return treasury.getMainTokenPrice();
    }

    // =========== Member getters

    function rewardPerShare() public view returns (uint256) {
        return getLatestSnapshot().rewardPerShare;
    }

    function earned(address member) public view returns (uint256) {
        uint256 latestRPS = getLatestSnapshot().rewardPerShare;
        uint256 storedRPS = getLastSnapshotOf(member).rewardPerShare;

        return balanceOf(member).mul(latestRPS.sub(storedRPS)).div(1e18).add(members[member].rewardEarned);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function stake(uint256 amount) public override onlyOneBlock updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot stake 0");
        super.stake(amount);
        members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists updateReward(msg.sender) {
        require(amount > 0, "Boardroom: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Boardroom: still in withdraw lockup");
        claimReward();
        super.withdraw(amount);
        emit Withdrawn(msg.sender, amount);
    }

    function exit() external {
        withdraw(balanceOf(msg.sender));
    }

    function claimReward() public updateReward(msg.sender) {
        uint256 reward = members[msg.sender].rewardEarned;
        if (reward > 0) {
            require(members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "Boardroom: still in reward lockup");
            members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            members[msg.sender].rewardEarned = 0;
            mainToken.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Boardroom: Cannot allocate 0");
        require(totalSupply() > 0, "Boardroom: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        BoardroomSnapshot memory newSnapshot = BoardroomSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        boardroomHistory.push(newSnapshot);

        mainToken.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(mainToken), "mainToken");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "./lib/SafeMath.sol";

import "./lib/SafeMath8.sol";
import "./owner/Operator.sol";
import "./interfaces/IOracle.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract MainToken is ERC20Burnable, Operator, Initializable {
    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // Initial distribution for the first 24h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 18360 ether;
    
    uint256 public constant INITIAL_DEV_FUND_DISTRIBUTION = 1080 ether;
    uint256 public constant INITIAL_DAO_FUND_DISTRIBUTION = 2160 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    address public oracle;

	//todo: update to test
	uint256 private constant INITIAL_FRAGMENTS_SUPPLY = 1000 ether; // 1 ether

    // Rebase
	uint256 private constant MAX_UINT256 = ~uint256(0);
	uint256 private constant MAX_SUPPLY = ~uint128(0);
	uint256 public TOTAL_GONS;
	uint256 private _gonsPerFragment = 10**18;

	bool public rebaseAllowed = true;
	mapping(address => uint256) private _balances;
	mapping(address => mapping(address => uint256)) private _allowances;
	mapping(address => bool) private _isExcluded;
	address[] public excluded;
	address[] public devFunds;
	address public daoFund;
	uint256 private _totalSupply = 0;

    /* =================== Events =================== */
    event LogRebase(uint256 indexed epoch, uint256 totalSupply);
    event GrantExclusion(address indexed account);
	event RevokeExclusion(address indexed account);

    /**
     * @notice Constructs the MainToken ERC-20 contract.
     */
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        // Mints 1 token to contract creator for initial pool setup
        _mint(msg.sender, INITIAL_FRAGMENTS_SUPPLY);
    }

    function getDevFunds() external view returns (address[] memory)
	{
		return devFunds;
	}

	function getDaoFund() external view returns (address)
	{
		return daoFund;
	}

	function getExcluded() external view returns (address[] memory)
	{
		return excluded;
	}

    function disableRebase() external onlyOperator {
		rebaseAllowed = false;
	}
    
	// todo: update to => onlyOperator
	function rebase(uint256 epoch, uint256 supplyDelta, bool negative) external returns (uint256)
	{
		require(rebaseAllowed, 'Rebase is not allowed');
		// uint256 prevRebaseSupply = rebaseSupply();
		// uint256 prevTotalSupply = _totalSupply;

		uint256 total = _rebase(supplyDelta, negative);

		emit LogRebase(epoch, total);
		return total;
	}

    	/**
	 * @dev Notifies Fragments contract about a new rebase cycle.
	 * @param supplyDelta The number of new fragment tokens to add into circulation via expansion.
	 * Return The total number of fragments after the supply adjustment.
	 */
	function _rebase(uint256 supplyDelta, bool negative) internal virtual returns (uint256) {
		// if supply delta is 0 nothing to rebase
		// if rebaseSupply is 0 nothing can be rebased
		if (supplyDelta == 0 || rebaseSupply() == 0) {
			return _totalSupply;
		}

		uint256[] memory excludedBalances = _burnExcludedAccountTokens();

		if (negative) {
			_totalSupply = _totalSupply.sub(uint256(supplyDelta));
		} else {
			_totalSupply = _totalSupply.add(uint256(supplyDelta));
		}

		if (_totalSupply > MAX_SUPPLY) {
			_totalSupply = MAX_SUPPLY;
		}

		_gonsPerFragment = TOTAL_GONS.div(_totalSupply);

		_mintExcludedAccountTokens(excludedBalances);

		return _totalSupply;
	}

    /**
	* @dev Exposes the supply available for rebasing. Essentially this is total supply minus excluded accounts
	* @return rebaseSupply The supply available for rebase
	*/
	function rebaseSupply() public view returns (uint256) {
		uint256 excludedSupply = 0;
		for (uint256 i = 0; i < excluded.length; i++) {
			excludedSupply = excludedSupply.add(balanceOf(excluded[i]));
		}
		return _totalSupply.sub(excludedSupply);
	}

    /**
	* @dev Burns all tokens from excluded accounts
	* @return excludedBalances The excluded account balances before burn
	*/
	function _burnExcludedAccountTokens() private returns (uint256[] memory excludedBalances)
	{
		excludedBalances = new uint256[](excluded.length);
		for (uint256 i = 0; i < excluded.length; i++) {
			address account = excluded[i];
			uint256 balance = balanceOf(account);
			excludedBalances[i] = balance;
			if (balance > 0) _burn(account, balance);
		}

		return excludedBalances;
	}

    /**
	* @dev Mints tokens to excluded accounts
	* @param excludedBalances The amount of tokens to mint per address
	*/
	function _mintExcludedAccountTokens(uint256[] memory excludedBalances) private
	{
		for (uint256 i = 0; i < excluded.length; i++) {
			if (excludedBalances[i] > 0)
				_mint(excluded[i], excludedBalances[i]);
		}
	}

    /**
	 * @dev Grant an exclusion from rebases
	 * @param account The account to grant exclusion
	 *
	 * Requirements:
	 *
	 * - `account` must NOT already be excluded.
	 * - can only be called by `excluderRole`
	 */
	function grantRebaseExclusion(address account) public onlyOperator
	{
        if (_isExcluded[account]) return;
		require(excluded.length <= 100, 'Too many excluded accounts');
		_isExcluded[account] = true;
		excluded.push(account);
		emit GrantExclusion(account);
	}

	/**
	 * @dev Revokes an exclusion from rebases
	 * @param account The account to revoke
	 *
	 * Requirements:
	 *
	 * - `account` must already be excluded.
	 * - can only be called by `excluderRole`
	 */
	function revokeRebaseExclusion(address account) external onlyOperator
	{
		require(_isExcluded[account], 'Account is not already excluded');
		for (uint256 i = 0; i < excluded.length; i++) {
			if (excluded[i] == account) {
				excluded[i] = excluded[excluded.length - 1];
				_isExcluded[account] = false;
				excluded.pop();
				emit RevokeExclusion(account);
				return;
			}
		}
	}

    //---OVERRIDE FUNTION---
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address who) public view override returns (uint256) {
        if (_gonsPerFragment == 0) return 0;
		return _balances[who].div(_gonsPerFragment);
    }
        
    function _mint(address account, uint256 amount) internal virtual override {
		require(account != address(0), 'ERC20: transfer to the zero address');
		require(amount > 0, "ERC20: Can't mint 0 tokens");

		TOTAL_GONS = TOTAL_GONS.add(_gonsPerFragment.mul(amount));
		_totalSupply = _totalSupply.add(amount);

		_balances[account] = _balances[account].add(
			amount.mul(_gonsPerFragment)
		);

		emit Transfer(address(0), account, amount);
	}

    function _burn(address account, uint256 amount) internal virtual override {
		require(account != address(0), 'ERC20: burn from the zero address');
		uint256 accountBalance = _balances[account];
		require(
			accountBalance >= amount.mul(_gonsPerFragment),
			'ERC20: burn amount exceeds balance'
		);
		unchecked {
			_balances[account] = _balances[account].sub(
				amount.mul(_gonsPerFragment)
			);
		}

		TOTAL_GONS = TOTAL_GONS.sub(_gonsPerFragment.mul(amount));
		_totalSupply = _totalSupply.sub(amount);

		emit Transfer(account, address(0), amount);
	}

    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    function increaseAllowance(address spender, uint256 addedValue) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, _allowances[owner][spender] + addedValue);
        return true;
    }

    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual override returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = _allowances[owner][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual override {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 gonValue = amount.mul(_gonsPerFragment);
        uint256 fromBalance = _balances[from];
        require(fromBalance >= gonValue, "ERC20: transfer amount exceeds balance");
        _balances[from] = _balances[from].sub(gonValue);
        _balances[to] = _balances[to].add(gonValue);
        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    //---END OVERRIDE FUNTION---
    
    function _getPrice() internal view returns (uint256 _price) {
        try IOracle(oracle).consult(address(this), 1e18) {
            return uint256(_price);
        } catch {
            revert("MainToken: failed to fetch price from Oracle");
        }
    }

    function setOracle(address _oracle) public onlyOperator {
        require(oracle != address(0), "oracle address cannot be 0 address");
        oracle = _oracle;
    }

    /**
     * @notice Operator mints Token to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of Token to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);
        return balanceAfter > balanceBefore;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _genesisPool,
        address _daoFundAddress,
        address[] calldata _devFundAddress
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPool != address(0), "!_genesisPool");
        require(_daoFundAddress != address(0), "!_daoFundAddress");
        rewardPoolDistributed = true;
        _mint(_genesisPool, INITIAL_GENESIS_POOL_DISTRIBUTION);
        _mint(_daoFundAddress, INITIAL_DAO_FUND_DISTRIBUTION);
		daoFund = _daoFundAddress;
		devFunds = _devFundAddress;

        uint256 totalDevFund = _devFundAddress.length;
        uint256 devFundDistribution = INITIAL_DEV_FUND_DISTRIBUTION.div(totalDevFund);
        for (uint8 entryId = 0; entryId < totalDevFund; ++entryId) {
            _mint(_devFundAddress[entryId], devFundDistribution);
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }

	function enableDistributeReward() external onlyOperator {
		rewardPoolDistributed = false;
	}

	function isDevFund(address _address) external view returns (bool _isDevFund, uint256 length) {
	 	length = devFunds.length;
		uint8 count = 0; 
		for (uint8 entryId = 0; entryId < length; ++entryId) {
            if (devFunds[entryId] == _address) {
				count = count + 1;
			}
        }

		_isDevFund = count > 0;
	}

	function isDaoFund(address _address) external view returns (bool) {
		return _address == daoFund;
	}
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

import "./owner/Operator.sol";

contract ShareToken is ERC20Burnable, Operator {
    using SafeMath for uint256;

    // TOTAL MAX SUPPLY = 70,000 CFARM
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 650000 ether;
    uint256 public constant NODE_POOL_REWARD_ALLOCATION = 50000 ether;

    //todo: update to test
	uint256 private constant INITIAL_SUPPLY = 1000 ether; // 1 ether

    bool public rewardPoolDistributed = false;

    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {
        // mint 1 token for initial pools deployment
        _mint(msg.sender, INITIAL_SUPPLY);
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address _farmingPoolAddress,
        address _nodePoolAddress
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
         require(_farmingPoolAddress != address(0), "!_farmingPoolAddress");
        require(_nodePoolAddress != address(0), "!_nodePoolAddress");
        rewardPoolDistributed = true;
        _mint(_farmingPoolAddress, FARMING_POOL_REWARD_ALLOCATION);
        _mint(_nodePoolAddress, NODE_POOL_REWARD_ALLOCATION);
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }

    function enableDistributeReward() external onlyOwner {
		rewardPoolDistributed = false;
	}
}
// SPDX-License-Identifier: MIT

pragma solidity 0.8.13;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

import "./lib/Babylonian.sol";
import "./owner/Operator.sol";
import "./utils/ContractGuard.sol";
import "./interfaces/IBasisAsset.sol";
import "./interfaces/IOracle.sol";
import "./interfaces/IBoardroom.sol";
import "./interfaces/IMainToken.sol";

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    //todo: data for test => need to update
    uint256 public constant PERIOD = 1 hours; //6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public previousEpoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // core components
    address public mainToken;
    // address public gbond;
    address public shareToken;

    address public boardroom;
    address public oracle;

    // price
    uint256 public mainTokenPriceOne;
    uint256 public mainTokenPriceCeiling;
    uint256 public mainTokenPriceRebase;
    uint256 public consecutiveEpochHasPriceBelowOne = 0;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    /*===== Rebase ====*/
    uint256 private constant DECIMALS = 18;
    uint256 private constant ONE = uint256(10**DECIMALS);
    // Due to the expression in computeSupplyDelta(), MAX_RATE * MAX_SUPPLY must fit into an int256.
    // Both are 18 decimals fixed point numbers.
    uint256 private constant MAX_RATE = 10**6 * 10**DECIMALS;
    // MAX_SUPPLY = MAX_INT256 / MAX_RATE
    uint256 private constant MAX_SUPPLY = uint256(type(int256).max) / MAX_RATE;
    
    // Block timestamp of last rebase operation
    uint256 public lastRebaseTimestampSec;

    bool public rebaseStarted = false;

    uint256 private midpointRounding = 10**(DECIMALS - 4);

    uint256 public previousEpochMainPrice = 0;

    /*===== End Rebase ====*/
    
    uint256 public daoFundSharedPercent = 10; // 10%
    uint256 public devFundSharedPercent = 5; // 5%

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event BoardroomFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);
    event LogRebase(
        uint256 indexed epoch,
        uint256 requestedSupplyAdjustment,
        uint256 timestampSec
    );

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition() {
        require(block.timestamp >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(block.timestamp >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
    }

    modifier checkOperator() {
        require(
            IBasisAsset(mainToken).operator() == address(this) &&
                IBasisAsset(shareToken).operator() == address(this) &&
                Operator(boardroom).operator() == address(this),
            "Treasury: need more permission"
        );

        _;
    }

    modifier notInitialized() {
        require(!initialized, "Treasury: already initialized");

        _;
    }

    /* ========== VIEW FUNCTIONS ========== */

    function isInitialized() public view returns (bool) {
        return initialized;
    }

    // epoch
    function nextEpochPoint() public view returns (uint256) {
        return startTime.add(epoch.mul(PERIOD));
    }

    // oracle
    function getMainTokenPrice() public view returns (uint256) {
        try IOracle(oracle).consult(mainToken, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult MainToken price from the oracle");
        }
    }

    function getTwapPrice() public view returns (uint256) {
        try IOracle(oracle).twap(mainToken, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to twap MainToken price from the oracle");
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _mainToken,
        address _shareToken,
        address _oracle,
        address _boardroom,
        uint256 _startTime
    ) public notInitialized {
        mainToken = _mainToken;
        shareToken = _shareToken;
        oracle = _oracle;
        boardroom = _boardroom;
        startTime = _startTime;

        mainTokenPriceOne = 10**6; // This is to allow a PEG of 1 MainToken per USDC
        mainTokenPriceRebase = 8*10**5; // 0.8 USDC
        mainTokenPriceCeiling = mainTokenPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500000 ether, 1000000 ether, 1500000 ether, 2000000 ether, 5000000 ether, 10000000 ether, 20000000 ether, 50000000 ether];
        maxExpansionTiers = [450, 400, 350, 300, 250, 200, 150, 125, 100];

        IMainToken(mainToken).grantRebaseExclusion(address(this));
        IMainToken(mainToken).grantRebaseExclusion(address(boardroom));

        initialized = true;
        operator = msg.sender;

        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setBoardroom(address _boardroom) external onlyOperator {
        boardroom = _boardroom;
    }

    function grantRebaseExclusion(address who) external onlyOperator {
        IMainToken(mainToken).grantRebaseExclusion(who);
    }

    function setOracle(address _oracle) external onlyOperator {
        oracle = _oracle;
    }

    function setMainTokenPriceCeiling(uint256 _mainTokenPriceCeiling) external onlyOperator {
        require(_mainTokenPriceCeiling >= mainTokenPriceOne && _mainTokenPriceCeiling <= mainTokenPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        mainTokenPriceCeiling = _mainTokenPriceCeiling;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < 8) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < 9, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    /* ========== MUTABLE FUNCTIONS ========== */
    function syncPrice() external onlyOperator {
        try IOracle(oracle).sync() {} catch {
            revert("Treasury: failed to sync price from the oracle");
        }
    }

    function _updatePrice() internal onlyOperator {
        try IOracle(oracle).update() {} catch {
            revert("Treasury: failed to update price from the oracle");
        }
    }

    function getMainTokenCirculatingSupply() public view returns (uint256) {
        IMainToken mainTokenErc20 = IMainToken(mainToken);
        uint256 totalSupply = mainTokenErc20.totalSupply();
        address[] memory excludedFromTotalSupply = mainTokenErc20.getExcluded();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(mainTokenErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }
    
    function getShareTokenCirculatingSupply() public view returns (uint256) {
        IERC20 shareTokenErc20 = IERC20(shareToken);
        IMainToken mainTokenErc20 = IMainToken(mainToken);
        uint256 totalSupply = shareTokenErc20.totalSupply();
        address[] memory excludedFromTotalSupply = mainTokenErc20.getExcluded();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(shareTokenErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        
        return totalSupply.sub(balanceExcluded);
    }

    function getEstimatedReward() public view returns (uint256) {
        uint256 mainTokenTotalSupply = IMainToken(mainToken).totalSupply();
        uint256 percentage = _calculateMaxSupplyExpansionPercent(mainTokenTotalSupply);
        uint256 estimatedReward = mainTokenTotalSupply.mul(percentage).div(10000);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = estimatedReward.mul(daoFundSharedPercent).div(100);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = estimatedReward.mul(devFundSharedPercent).div(100);
        }

        return estimatedReward.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);
    }

    function _sendToBoardroom(uint256 _amount) internal {
        IMainToken mainTokenErc20 = IMainToken(mainToken);
        mainTokenErc20.mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(100);
            address daoFund = mainTokenErc20.getDaoFund();
            mainTokenErc20.transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(block.timestamp, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(100);
            address[] memory devFunds = mainTokenErc20.getDevFunds();
            uint256 length = devFunds.length;
            for (uint8 i = 0; i < length; i++) {
                mainTokenErc20.transfer(devFunds[i], _devFundSharedAmount.div(length));
            }
            emit DevFundFunded(block.timestamp, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(mainToken).safeApprove(boardroom, 0);
        IERC20(mainToken).safeApprove(boardroom, _amount);
        IBoardroom(boardroom).allocateSeigniorage(_amount);
        emit BoardroomFunded(block.timestamp, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _mainTokenSupply) internal view returns (uint256) {
        uint256 maxSupplyExpansionPercent;

        for (uint8 tierId = 7; tierId >= 0; --tierId) {
            if (_mainTokenSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updatePrice();
        if (epoch > 0) {
            previousEpochMainPrice = getMainTokenPrice();
            if (previousEpochMainPrice > mainTokenPriceCeiling) {
                // Expansion
                uint256 mainTokenTotalSupply = IMainToken(mainToken).totalSupply();
                uint256 _percentage = _calculateMaxSupplyExpansionPercent(mainTokenTotalSupply);
                uint256 _savedForBoardroom = mainTokenTotalSupply.mul(_percentage).div(10000);
                if (_savedForBoardroom > 0) {
                uint256 boardRoomAmount = IBoardroom(boardroom).totalSupply();
                if (boardRoomAmount > 0) {
                    _sendToBoardroom(_savedForBoardroom);
                } else {
                        // mint to DAOFund
                        address daoFund = IMainToken(mainToken).getDaoFund();
                        IMainToken(mainToken).mint(daoFund, _savedForBoardroom);
                }
                }
            }

            // Rebase
            if (previousEpochMainPrice < mainTokenPriceOne) {
                consecutiveEpochHasPriceBelowOne = consecutiveEpochHasPriceBelowOne.add(1);
            } else {
                consecutiveEpochHasPriceBelowOne = 0;
            }
            
            if (rebaseStarted && previousEpochMainPrice < mainTokenPriceOne) {
                _rebase();
                consecutiveEpochHasPriceBelowOne = 0;
            } else {
                rebaseStarted = false;
                // twap <= 0.8 USD => rebase
                // 10 consecutive epoch has twap < 1 USD => rebase
                if (previousEpochMainPrice <= mainTokenPriceRebase || consecutiveEpochHasPriceBelowOne == 10) {
                    _rebase();
                    consecutiveEpochHasPriceBelowOne = 0;
                }
            }
        }
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(mainToken), "mainToken");
        require(address(_token) != address(shareToken), "shareToken");
        _token.safeTransfer(_to, _amount);
    }

    function boardroomSetOperator(address _operator) external onlyOperator {
        IBoardroom(boardroom).setOperator(_operator);
    }

    function boardroomSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IBoardroom(boardroom).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function boardroomAllocateSeigniorage(uint256 amount) external onlyOperator {
        IBoardroom(boardroom).allocateSeigniorage(amount);
    }

    function boardroomGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IBoardroom(boardroom).governanceRecoverUnsupported(_token, _amount, _to);
    }

    function computeSupplyDelta() public view returns (bool negative, uint256 supplyDelta) {
        require(previousEpochMainPrice > 0, "previousEpochMainPrice invalid");
        uint256 targetRate = 10**DECIMALS;
        uint256 rate = previousEpochMainPrice.mul(10**DECIMALS).div(10**6);
        negative = rate < targetRate;
        uint256 rebasePercentage = ONE;
        if (negative) {
            rebasePercentage = targetRate.sub(rate).mul(ONE).div(targetRate);
        } else {
            rebasePercentage = rate.sub(targetRate).mul(ONE).div(targetRate);
        }

        supplyDelta = mathRound(getMainTokenCirculatingSupply().mul(rebasePercentage).div(ONE));
    }

    function mathRound(uint256 _value) internal view returns (uint256) {
        uint256 valueFloor = _value.div(midpointRounding).mul(midpointRounding);
        uint256 delta = _value.sub(valueFloor);
        if (delta >= midpointRounding.div(2)) {
            return valueFloor.add(midpointRounding);
        } else {
            return valueFloor;
        }
    }

    function _rebase() internal onlyOperator {
        require(epoch >= previousEpoch, "cannot rebase");
        (bool negative, uint256 supplyDelta) = computeSupplyDelta();

        if (supplyDelta > 0) {
            rebaseStarted = true;
            if (IERC20(mainToken).totalSupply().add(uint256(supplyDelta)) > MAX_SUPPLY) {
                supplyDelta = MAX_SUPPLY.sub(IERC20(mainToken).totalSupply());
            }

            uint256 supplyAfterRebase = IMainToken(mainToken).rebase(epoch, supplyDelta, negative);
            assert(supplyAfterRebase <= MAX_SUPPLY);
            previousEpoch = epoch;
        }
       
        emit LogRebase(epoch, supplyDelta, block.timestamp);
    }
    //==========END REBASE===========
}