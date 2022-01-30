// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

contract RocketFarm is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 amount;
        uint256 rewardDebt;
        uint256 pendingRewards;
    }

    struct PoolInfo {
        IERC20 stakeToken;
        uint256 allocPoint;
        uint256 lastRewardBlock;
        uint256 accRewardPerShare;
        uint256 depositedAmount;
    }

    RocketToken public rocket;
    uint256 public rewardPerBlock;

    PoolInfo[] public poolInfo;
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    uint256 public totalAllocPoint = 0;
    uint256 public startBlock;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Claim(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    constructor(RocketToken _rocket, uint256 _rewardPerBlock, uint256 _startBlock) {
        rocket = _rocket;
        rewardPerBlock = _rewardPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    function addPool(uint256 _allocPoint, IERC20 _stakeToken, bool _update) public onlyOwner {
        if(_update) {
            massUpdatePools();
        }

        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint + _allocPoint;
        poolInfo.push(
            PoolInfo({
                stakeToken: _stakeToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accRewardPerShare: 0,
                depositedAmount: 0
            })
        );
    }

    function setAllocPoint(uint256 _pid, uint256 _allocPoint, bool _update) public onlyOwner {
        if(_update) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint - poolInfo[_pid].allocPoint + _allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    function pendingRewards(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accRewardPerShare = pool.accRewardPerShare;
        uint256 stakeSupply = pool.stakeToken.balanceOf(address(this));
        if(block.number > pool.lastRewardBlock && stakeSupply != 0) {
            uint256 multiplier = block.number - pool.lastRewardBlock;
            uint256 reward = ((multiplier * rewardPerBlock) * pool.allocPoint) / totalAllocPoint;
            accRewardPerShare = accRewardPerShare + ((reward * 1e12) / stakeSupply);
        }
        return ((user.amount * accRewardPerShare) / 1e12) - user.rewardDebt + user.pendingRewards;
    }

    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for(uint256 pid=0;pid<length;++pid) {
            updatePool(pid);
        }
    }

    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if(block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 stakeSupply = pool.stakeToken.balanceOf(address(this));
        if(stakeSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = block.number - pool.lastRewardBlock;
        uint256 reward = ((multiplier * rewardPerBlock) * pool.allocPoint) / totalAllocPoint;
        rocket.mint(address(this), reward);
        pool.accRewardPerShare = pool.accRewardPerShare + ((reward * 1e12) / stakeSupply);
        pool.lastRewardBlock = block.number;
    }

    function deposit(uint256 _pid, uint256 _amount, bool _withdrawRewards) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(_amount > 0, "Amount must be a positive number");
        updatePool(_pid);
        if(user.amount > 0) {
            uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
            if(pending > 0) {
                user.pendingRewards = user.pendingRewards + pending;
                if(_withdrawRewards) {
                    safeRewardTransfer(msg.sender, user.pendingRewards);
                    emit Claim(msg.sender, _pid, user.pendingRewards);
                    user.pendingRewards = 0;
                }
            }
        }
        if(_amount > 0) {
            pool.stakeToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount + _amount;
            pool.depositedAmount = pool.depositedAmount + _amount;
        }
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount, bool _withdrawRewards) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "Withdrawing more than your stake");
        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        if(pending > 0) {
            user.pendingRewards = user.pendingRewards + pending;
            if(_withdrawRewards) {
                safeRewardTransfer(msg.sender, user.pendingRewards);
                emit Claim(msg.sender, _pid, user.pendingRewards);
                user.pendingRewards = 0;
            }
        }
        if(_amount > 0) {
            user.amount = user.amount - _amount;
            pool.depositedAmount = pool.depositedAmount - _amount;
            pool.stakeToken.safeTransfer(address(msg.sender), _amount);
        }
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
        emit Withdraw(msg.sender, _pid, _amount);
    }

    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        pool.stakeToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        pool.depositedAmount = pool.depositedAmount - user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        user.pendingRewards = 0;
    }

    function claim(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        uint256 pending = ((user.amount * pool.accRewardPerShare) / 1e12) - user.rewardDebt;
        if(pending > 0 || user.pendingRewards > 0) {
            user.pendingRewards = user.pendingRewards + pending;
            safeRewardTransfer(msg.sender, user.pendingRewards);
            emit Claim(msg.sender, _pid, user.pendingRewards);
            user.pendingRewards = 0;
        }
        user.rewardDebt = (user.amount * pool.accRewardPerShare) / 1e12;
    }

    function safeRewardTransfer(address _to, uint256 _amount) internal {
        uint256 rewardBal = rocket.balanceOf(address(this));
        if(_amount > rewardBal) {
            rocket.transfer(_to, rewardBal);
        } else {
            rocket.transfer(_to, _amount);
        }
    }

    function setRewardPerBlock(uint256 _rewardPerBlock) public onlyOwner {
        rewardPerBlock = _rewardPerBlock;      
    }
}