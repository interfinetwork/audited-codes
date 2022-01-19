// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./SatoruFiToken.sol";
import "./Authorizable.sol";

// MasterChef is the master breeder of whatever creature the SatoruFiToken represents.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once SatoruFiToken is sufficiently
// distributed and the community can show to govern itself.
//
contract MasterChef is Ownable, Authorizable, ReentrancyGuard {
    using SafeMath
    for uint256;
    using SafeERC20
    for IERC20;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 rewardDebtAtBlock; // the last block user stake
        uint256 lastWithdrawBlock; // the last block a user withdrew at.
        uint256 firstDepositBlock; // the last block a user deposited at.
        uint256 blockdelta; //time passed since withdrawals
        uint256 lastDepositBlock;
        //
        // We do some fancy math here. Basically, any point in time, the amount of SatoruFiTokens
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accGovTokenPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accGovTokenPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    struct UserGlobalInfo {
        uint256 globalAmount;
        mapping(address => uint256) referrals;
        uint256 totalReferals;
        uint256 globalRefAmount;
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. SatoruFiTokens to distribute per block.
        uint256 lastRewardBlock; // Last block number that SatoruFiTokens distribution occurs.
        uint256 accGovTokenPerShare; // Accumulated SatoruFiTokens per share, times 1e12. See below.
    }

    // The Governance token
    SatoruFiToken public govToken;
    // Dev address.
    address public devaddr;
    // LP address
    address public liquidityaddr;
    // Community Fund Address
    address public comfundaddr;
    // Founder Reward
    address public founderaddr;
    // SatoruFiTokens created per block.
    uint256 public REWARD_PER_BLOCK;
    // Bonus muliplier for early SatoruFiToken makers.
    uint256[] public REWARD_MULTIPLIER; // init in constructor function
    uint256[] public HALVING_AT_BLOCK; // init in constructor function
    uint256[] public blockDeltaStartStage;
    uint256[] public blockDeltaEndStage;
    uint256[] public userFeeStage;
    uint256[] public devFeeStage;
    uint256 public FINISH_BONUS_AT_BLOCK;
    uint256 public userDepFee;
    uint256 public devDepFee;

    // The block number when SatoruFiToken mining starts.
    uint256 public START_BLOCK;

    uint256 public PERCENT_LOCK_BONUS_REWARD; // lock xx% of bounus reward in 3 year
    uint256 public PERCENT_FOR_DEV; // dev bounties + partnerships
    uint256 public PERCENT_FOR_LP; // LP fund
    uint256 public PERCENT_FOR_COM; // community fund
    uint256 public PERCENT_FOR_FOUNDERS; // founders fund

    // Info of each pool.
    PoolInfo[] public poolInfo;
    mapping(address => uint256) public poolId1; // poolId1 count from 1, subtraction 1 before using with poolInfo
    // Info of each user that stakes LP tokens. pid => user address => info
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(address => UserGlobalInfo) public userGlobalInfo;
    mapping(IERC20 => bool) public poolExistence;
    // Total allocation poitns. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(
        address indexed user,
        uint256 indexed pid,
        uint256 amount
    );
    event SendSatoruFiTokenReward(
        address indexed user,
        uint256 indexed pid,
        uint256 amount,
        uint256 lockAmount
    );
    event DevAddressChange(address indexed dev);
    event BonusFinishUpdate(uint256 _block);
    event HalvingUpdate(uint256[] block);
    event LpAddressUpdate(address indexed lpAddress);
    event ComAddressUpdate(address indexed comAddress);
    event FounderAddressUpdate(address indexed founderAddress);
    event RewardUpdate(uint256 amount);
    event RewardMulUpdate(uint256[] rewardMultiplier);
    event LockUpdate(uint256 PERCENT_LOCK_BONUS_REWARD);
    event LockdevUpdate(uint256 PERCENT_FOR_DEV);
    event LocklpUpdate(uint256 PERCENT_FOR_LP);
    event LockcomUpdate(uint256 PERCENT_FOR_COM);
    event LockfounderUpdate(uint256 PERCENT_FOR_FOUNDERS);
    event StarblockUpdate(uint256 START_BLOCK);
    event WithdrawRevised(address indexed user, uint256 block);
    event DepositRevised(address indexed user, uint256 amount);
    event StageStartSet(uint256[] blockStarts);
    event StageEndSet(uint256[] blockEnds);
    event UserFeeStageUpdate(uint256[] userFees);
    event DevFeeStageUpdate(uint256[] devFees);
    event DevDepFeeUpdate(uint256 devFeePerecnt);
    event UserDepFeeUpdate(uint256 usrDepFees);

    modifier nonDuplicated(IERC20 _lpToken) {
        require(!poolExistence[_lpToken], "MasterChef::nonDuplicated: duplicated");
        _;
    }

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "Pool does not exist");
        _;
    }

    constructor(
        SatoruFiToken _govToken,
        address _devaddr,
        address _liquidityaddr,
        address _comfundaddr,
        address _founderaddr,
        uint256 _rewardPerBlock,
        uint256 _startBlock,
        uint256 _halvingAfterBlock,
        uint256 _userDepFee,
        uint256 _devDepFee,
        uint256[] memory _rewardMultiplier,
        uint256[] memory _blockDeltaStartStage,
        uint256[] memory _blockDeltaEndStage,
        uint256[] memory _userFeeStage,
        uint256[] memory _devFeeStage
    ) public {
        govToken = _govToken;
        devaddr = _devaddr;
        liquidityaddr = _liquidityaddr;
        comfundaddr = _comfundaddr;
        founderaddr = _founderaddr;
        REWARD_PER_BLOCK = _rewardPerBlock;
        START_BLOCK = _startBlock;
        userDepFee = _userDepFee;
        devDepFee = _devDepFee;
        REWARD_MULTIPLIER = _rewardMultiplier;
        blockDeltaStartStage = _blockDeltaStartStage;
        blockDeltaEndStage = _blockDeltaEndStage;
        userFeeStage = _userFeeStage;
        devFeeStage = _devFeeStage;
        for (uint256 i = 0; i < REWARD_MULTIPLIER.length - 1; i++) {
            uint256 halvingAtBlock = _halvingAfterBlock.mul(i + 1).add(_startBlock).add(1);
            HALVING_AT_BLOCK.push(halvingAtBlock);
        }
        FINISH_BONUS_AT_BLOCK = _halvingAfterBlock
            .mul(REWARD_MULTIPLIER.length)
            .add(_startBlock);
        HALVING_AT_BLOCK.push(uint256(-1));
    }

    function poolLength() external view returns(uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(
        uint256 _allocPoint,
        IERC20 _lpToken,
        bool _withUpdate
    ) external onlyOwner nonDuplicated(_lpToken) {
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
            block.number > START_BLOCK ? block.number : START_BLOCK;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(
            PoolInfo({
                lpToken: _lpToken,
                allocPoint: _allocPoint,
                lastRewardBlock: lastRewardBlock,
                accGovTokenPerShare: 0
            })
        );
    }

    // Update the given pool's SatoruFiToken allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        bool _withUpdate
    ) external onlyOwner validatePoolByPid(_pid) {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(
            _allocPoint
        );
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 GovTokenForDev;
        uint256 GovTokenForFarmer;
        uint256 GovTokenForLP;
        uint256 GovTokenForCom;
        uint256 GovTokenForFounders;
        (
            GovTokenForDev,
            GovTokenForFarmer,
            GovTokenForLP,
            GovTokenForCom,
            GovTokenForFounders
        ) = getPoolReward(pool.lastRewardBlock, block.number, pool.allocPoint);
        govToken.mint(address(this), GovTokenForFarmer);
        pool.accGovTokenPerShare = pool.accGovTokenPerShare.add(
            GovTokenForFarmer.mul(1e12).div(lpSupply)
        );
        pool.lastRewardBlock = block.number;
        if (GovTokenForDev > 0) {
            govToken.mint(address(devaddr), GovTokenForDev);
            //Dev fund has xx% locked during the starting bonus period. After which locked funds drip out linearly each block over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(devaddr), GovTokenForDev.mul(75).div(100));
            }
        }
        if (GovTokenForLP > 0) {
            govToken.mint(liquidityaddr, GovTokenForLP);
            //LP + Partnership fund has only xx% locked over time as most of it is needed early on for incentives and listings. The locked amount will drip out linearly each block after the bonus period.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(liquidityaddr), GovTokenForLP.mul(45).div(100));
            }
        }
        if (GovTokenForCom > 0) {
            govToken.mint(comfundaddr, GovTokenForCom);
            //Community Fund has xx% locked during bonus period and then drips out linearly over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(comfundaddr), GovTokenForCom.mul(85).div(100));
            }
        }
        if (GovTokenForFounders > 0) {
            govToken.mint(founderaddr, GovTokenForFounders);
            //The Founders reward has xx% of their funds locked during the bonus period which then drip out linearly per block over 3 years.
            if (block.number <= FINISH_BONUS_AT_BLOCK) {
                govToken.lock(address(founderaddr), GovTokenForFounders.mul(95).div(100));
            }
        }
    }

    // |--------------------------------------|
    // [20, 30, 40, 50, 60, 70, 80, 99999999]
    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns(uint256) {
        uint256 result = 0;
        if (_from < START_BLOCK || _to > FINISH_BONUS_AT_BLOCK) return 0;

        for (uint256 i = 0; i < HALVING_AT_BLOCK.length; i++) {
            uint256 endBlock = HALVING_AT_BLOCK[i];

            if (_to <= endBlock) {
                uint256 m = _to.sub(_from).mul(REWARD_MULTIPLIER[i]);
                return result.add(m);
            }

            if (_from < endBlock) {
                uint256 m = endBlock.sub(_from).mul(REWARD_MULTIPLIER[i]);
                _from = endBlock;
                result = result.add(m);
            }
        }

        return result;
    }

    function getPoolReward(
        uint256 _from,
        uint256 _to,
        uint256 _allocPoint
    )
    public
    view
    returns(
        uint256 forDev,
        uint256 forFarmer,
        uint256 forLP,
        uint256 forCom,
        uint256 forFounders
    ) {
        uint256 multiplier = getMultiplier(_from, _to);
        uint256 amount =
            multiplier.mul(REWARD_PER_BLOCK).mul(_allocPoint).div(
                totalAllocPoint
            );
        uint256 SatoruFiTokenCanMint = govToken.cap().sub(govToken.totalSupply());
        uint256 mulFactor = PERCENT_FOR_DEV + PERCENT_FOR_LP + PERCENT_FOR_COM + PERCENT_FOR_FOUNDERS;
        uint256 checkAmount = amount + amount.mul(mulFactor).div(100);

        if (SatoruFiTokenCanMint < amount) {
            forDev = 0;
            forFarmer = SatoruFiTokenCanMint;
            forLP = 0;
            forCom = 0;
            forFounders = 0;
        } else if (SatoruFiTokenCanMint < checkAmount) {
            forDev = 0;
            forFarmer = amount;
            forLP = 0;
            forCom = 0;
            forFounders = 0;
        } else {
            forDev = amount.mul(PERCENT_FOR_DEV).div(100);
            forFarmer = amount;
            forLP = amount.mul(PERCENT_FOR_LP).div(100);
            forCom = amount.mul(PERCENT_FOR_COM).div(100);
            forFounders = amount.mul(PERCENT_FOR_FOUNDERS).div(100);
        }
    }

    // View function to see pending SatoruFiTokens on frontend.
    function pendingReward(uint256 _pid, address _user)
    external
    view
    validatePoolByPid(_pid)
    returns(uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accGovTokenPerShare = pool.accGovTokenPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply > 0) {
            uint256 GovTokenForFarmer;
            (, GovTokenForFarmer, , , ) = getPoolReward(
                pool.lastRewardBlock,
                block.number,
                pool.allocPoint
            );
            accGovTokenPerShare = accGovTokenPerShare.add(
                GovTokenForFarmer.mul(1e12).div(lpSupply)
            );
        }
        return user.amount.mul(accGovTokenPerShare).div(1e12).sub(user.rewardDebt);
    }

    function claimRewards(uint256[] memory _pids) external {
        for (uint256 i = 0; i < _pids.length; i++) {
            claimReward(_pids[i]);
        }
    }

    function claimReward(uint256 _pid) public validatePoolByPid(_pid) {
        updatePool(_pid);
        _harvest(_pid);
    }

    // lock 95% of reward if it comes from bonus time
    function _harvest(uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if (user.amount > 0) {
            uint256 pending =
                user.amount.mul(pool.accGovTokenPerShare).div(1e12).sub(
                    user.rewardDebt
                );
            uint256 masterBal = govToken.balanceOf(address(this));

            if (pending > masterBal) {
                pending = masterBal;
            }

            if (pending > 0) {
                govToken.transfer(msg.sender, pending);
                uint256 lockAmount = 0;
                if (user.rewardDebtAtBlock <= FINISH_BONUS_AT_BLOCK) {
                    lockAmount = pending.mul(PERCENT_LOCK_BONUS_REWARD).div(
                        100
                    );
                    govToken.lock(msg.sender, lockAmount);
                }

                user.rewardDebtAtBlock = block.number;

                emit SendSatoruFiTokenReward(msg.sender, _pid, pending, lockAmount);
            }

            user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
        }
    }

    function getGlobalAmount(address _user) external view returns(uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalAmount;
    }

    function getGlobalRefAmount(address _user) external view returns(uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.globalRefAmount;
    }

    function getTotalRefs(address _user) external view returns(uint256) {
        UserGlobalInfo memory current = userGlobalInfo[_user];
        return current.totalReferals;
    }

    function getRefValueOf(address _user, address _user2)
    external
    view
    returns(uint256) {
        UserGlobalInfo storage current = userGlobalInfo[_user];
        uint256 a = current.referrals[_user2];
        return a;
    }

    // Deposit LP tokens to MasterChef for SatoruFiToken allocation.
    function deposit(
        uint256 _pid,
        uint256 _amount,
        address _ref
    ) external nonReentrant validatePoolByPid(_pid) {
        require(
            _amount > 0,
            "MasterChef::deposit: amount must be greater than 0"
        );
        // require(_ref != address(0), "MasterChef::deposit: zero address for ref");
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserInfo storage devr = userInfo[_pid][devaddr];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];

        if (refer.referrals[msg.sender] > 0) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        } else {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] + _amount;
            refer.totalReferals = refer.totalReferals + 1;
            refer.globalRefAmount = refer.globalRefAmount + _amount;
        }

        current.globalAmount =
            current.globalAmount + _amount -
            _amount.mul(userDepFee).div(10000);

        updatePool(_pid);
        _harvest(_pid);
        pool.lpToken.safeTransferFrom(
            address(msg.sender),
            address(this),
            _amount
        );
        if (user.amount == 0) {
            user.rewardDebtAtBlock = block.number;
        }
        user.amount = user.amount.add(
            _amount.sub(_amount.mul(userDepFee).div(10000))
        );
        user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
        devr.amount = devr.amount.add(
            _amount.sub(_amount.mul(devDepFee).div(10000))
        );
        devr.rewardDebt = devr.amount.mul(pool.accGovTokenPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
        if (user.firstDepositBlock > 0) {} else {
            user.firstDepositBlock = block.number;
        }
        user.lastDepositBlock = block.number;
    }

    // Withdraw LP tokens from MasterChef.
    function withdraw(
        uint256 _pid,
        uint256 _amount,
        address _ref
    ) external nonReentrant validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        UserGlobalInfo storage refer = userGlobalInfo[_ref];
        UserGlobalInfo storage current = userGlobalInfo[msg.sender];
        require(user.amount >= _amount, "MasterChef::withdraw: not good");
        if (_ref != address(0)) {
            refer.referrals[msg.sender] = refer.referrals[msg.sender] - _amount;
            refer.globalRefAmount = refer.globalRefAmount - _amount;
        }
        current.globalAmount = current.globalAmount - _amount;

        updatePool(_pid);
        _harvest(_pid);

        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            if (user.lastWithdrawBlock > 0) {
                user.blockdelta = block.number - user.lastWithdrawBlock;
            } else {
                user.blockdelta = block.number - user.firstDepositBlock;
            }
            if (
                user.blockdelta == blockDeltaStartStage[0] ||
                block.number == user.lastDepositBlock
            ) {
                //25% fee for withdrawals of LP tokens in the same block this is to prevent abuse from flashloans
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[0]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[0]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[1] &&
                user.blockdelta <= blockDeltaEndStage[0]
            ) {
                //8% fee if a user deposits and withdraws in between same block and 59 minutes.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[1]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[1]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[2] &&
                user.blockdelta <= blockDeltaEndStage[1]
            ) {
                //4% fee if a user deposits and withdraws after 1 hour but before 1 day.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[2]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[2]).div(100)
                );
            } else if (
                user.blockdelta >= blockDeltaStartStage[3] &&
                user.blockdelta <= blockDeltaEndStage[2]
            ) {
                //2% fee if a user deposits and withdraws between after 1 day but before 3 days.
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[3]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[3]).div(100)
                );
            } else if (
                user.blockdelta > blockDeltaStartStage[4]
            ) {
                //1% fee if a user deposits and withdraws after 3 days
                pool.lpToken.safeTransfer(
                    address(msg.sender),
                    _amount.mul(userFeeStage[4]).div(100)
                );
                pool.lpToken.safeTransfer(
                    address(devaddr),
                    _amount.mul(devFeeStage[4]).div(100)
                );
            // } else if (
            //     user.blockdelta >= blockDeltaStartStage[5] &&
            //     user.blockdelta <= blockDeltaEndStage[4]
            // ) {
            //     //0.5% fee if a user deposits and withdraws if the user withdraws after 5 days but before 2 weeks.
            //     pool.lpToken.safeTransfer(
            //         address(msg.sender),
            //         _amount.mul(userFeeStage[5]).div(1000)
            //     );
            //     pool.lpToken.safeTransfer(
            //         address(devaddr),
            //         _amount.mul(devFeeStage[5]).div(1000)
            //     );
            // } else if (
            //     user.blockdelta >= blockDeltaStartStage[6] &&
            //     user.blockdelta <= blockDeltaEndStage[5]
            // ) {
            //     //0.25% fee if a user deposits and withdraws after 2 weeks.
            //     pool.lpToken.safeTransfer(
            //         address(msg.sender),
            //         _amount.mul(userFeeStage[6]).div(10000)
            //     );
            //     pool.lpToken.safeTransfer(
            //         address(devaddr),
            //         _amount.mul(devFeeStage[6]).div(10000)
            //     );
            // } else if (user.blockdelta > blockDeltaStartStage[7]) {
            //     //0.1% fee if a user deposits and withdraws after 4 weeks.
            //     pool.lpToken.safeTransfer(
            //         address(msg.sender),
            //         _amount.mul(userFeeStage[7]).div(10000)
            //     );
            //     pool.lpToken.safeTransfer(
            //         address(devaddr),
            //         _amount.mul(devFeeStage[7]).div(10000)
            //     );
            }
            user.rewardDebt = user.amount.mul(pool.accGovTokenPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
            user.lastWithdrawBlock = block.number;
        }
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY. This has the same 25% fee as same block withdrawals to prevent abuse of thisfunction.
    function emergencyWithdraw(uint256 _pid) external nonReentrant validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        //reordered from Sushi function to prevent risk of reentrancy
        uint256 amountToSend = user.amount.mul(75).div(100);
        uint256 devToSend = user.amount.mul(25).div(100);
        user.amount = 0;
        user.rewardDebt = 0;
        user.rewardDebtAtBlock = 0;
        user.lastWithdrawBlock = 0;
        user.firstDepositBlock = 0;
        user.blockdelta = 0;
        user.lastDepositBlock = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amountToSend);
        pool.lpToken.safeTransfer(address(devaddr), devToSend);
        emit EmergencyWithdraw(msg.sender, _pid, amountToSend);
    }

    // Safe GovToken transfer function, just in case if rounding error causes pool to not have enough GovTokens.
    function safeGovTokenTransfer(address _to, uint256 _amount) internal {
        uint256 govTokenBal = govToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > govTokenBal) {
            transferSuccess = govToken.transfer(_to, govTokenBal);
        } else {
            transferSuccess = govToken.transfer(_to, _amount);
        }
        require(transferSuccess, "MasterChef::safeGovTokenTransfer: transfer failed");
    }

    // Update dev address by the previous dev.
    function dev(address _devaddr) external onlyAuthorized {
        devaddr = _devaddr;
        emit DevAddressChange(devaddr);
    }

    // Update Finish Bonus Block
    function bonusFinishUpdate(uint256 _newFinish) external onlyAuthorized {
        FINISH_BONUS_AT_BLOCK = _newFinish;
        emit BonusFinishUpdate(FINISH_BONUS_AT_BLOCK);
    }

    // Update Halving At Block
    function halvingUpdate(uint256[] memory _newHalving) external onlyAuthorized {
        HALVING_AT_BLOCK = _newHalving;
        emit HalvingUpdate(HALVING_AT_BLOCK);
    }

    // Update Liquidityaddr
    function lpUpdate(address _newLP) external onlyAuthorized {
        liquidityaddr = _newLP;
        emit LpAddressUpdate(liquidityaddr);
    }

    // Update comfundaddr
    function comUpdate(address _newCom) external onlyAuthorized {
        comfundaddr = _newCom;
        emit ComAddressUpdate(comfundaddr);
    }

    // Update founderaddr
    function founderUpdate(address _newFounder) external onlyAuthorized {
        founderaddr = _newFounder;
        emit FounderAddressUpdate(founderaddr);
    }

    // Update Reward Per Block
    function rewardUpdate(uint256 _newReward) external onlyAuthorized {
        REWARD_PER_BLOCK = _newReward;
        emit RewardUpdate(REWARD_PER_BLOCK);
    }

    // Update Rewards Mulitplier Array
    function rewardMulUpdate(uint256[] memory _newMulReward)
    external
    onlyAuthorized {
        REWARD_MULTIPLIER = _newMulReward;
        emit RewardMulUpdate(REWARD_MULTIPLIER);
    }

    // Update % lock for general users
    function lockUpdate(uint256 _newlock) external onlyAuthorized {
        PERCENT_LOCK_BONUS_REWARD = _newlock;
        emit LockUpdate(PERCENT_LOCK_BONUS_REWARD);
    }

    // Update % lock for dev
    function lockdevUpdate(uint256 _newdevlock) external onlyAuthorized {
        PERCENT_FOR_DEV = _newdevlock;
        emit LockdevUpdate(PERCENT_FOR_DEV);
    }

    // Update % lock for LP
    function locklpUpdate(uint256 _newlplock) external onlyAuthorized {
        PERCENT_FOR_LP = _newlplock;
        emit LocklpUpdate(PERCENT_FOR_LP);
    }

    // Update % lock for COM
    function lockcomUpdate(uint256 _newcomlock) external onlyAuthorized {
        PERCENT_FOR_COM = _newcomlock;
        emit LockcomUpdate(PERCENT_FOR_COM);
    }

    // Update % lock for Founders
    function lockfounderUpdate(uint256 _newfounderlock) external onlyAuthorized {
        PERCENT_FOR_FOUNDERS = _newfounderlock;
        emit LockfounderUpdate(PERCENT_FOR_FOUNDERS);
    }

    // Update START_BLOCK
    function starblockUpdate(uint256 _newstarblock) external onlyAuthorized {
        START_BLOCK = _newstarblock;
        emit StarblockUpdate(START_BLOCK);
    }

    function getNewRewardPerBlock(uint256 pid1) external view returns(uint256) {
        uint256 multiplier = getMultiplier(block.number - 1, block.number);
        return
        multiplier
            .mul(REWARD_PER_BLOCK)
            .mul(poolInfo[pid1].allocPoint)
            .div(totalAllocPoint);
    }

    function userDelta(uint256 _pid) external view validatePoolByPid(_pid) returns(uint256) {
        UserInfo storage user = userInfo[_pid][msg.sender];
        if (user.lastWithdrawBlock > 0) {
            uint256 estDelta = block.number - user.lastWithdrawBlock;
            return estDelta;
        } else {
            uint256 estDelta = block.number - user.firstDepositBlock;
            return estDelta;
        }
    }

    function reviseWithdraw(
        uint256 _pid,
        address _user,
        uint256 _block
    ) external onlyAuthorized() validatePoolByPid(_pid) {
        UserInfo storage user = userInfo[_pid][_user];
        user.lastWithdrawBlock = _block;
        emit WithdrawRevised(_user, _block);
    }

    function reviseDeposit(
        uint256 _pid,
        address _user,
        uint256 _block
    ) external onlyAuthorized() validatePoolByPid(_pid) {
        UserInfo storage user = userInfo[_pid][_user];
        user.firstDepositBlock = _block;
        emit DepositRevised(_user, _block);
    }

    function setStageStarts(uint256[] memory _blockStarts)
    external
    onlyAuthorized() {
        blockDeltaStartStage = _blockStarts;
        emit StageStartSet(blockDeltaStartStage);
    }

    function setStageEnds(uint256[] memory _blockEnds) external onlyAuthorized() {
        blockDeltaEndStage = _blockEnds;
        emit StageEndSet(blockDeltaEndStage);
    }

    function setUserFeeStage(uint256[] memory _userFees)
    external
    onlyAuthorized() {
        userFeeStage = _userFees;
        emit UserFeeStageUpdate(userFeeStage);
    }

    function setDevFeeStage(uint256[] memory _devFees) external onlyAuthorized() {
        devFeeStage = _devFees;
        emit DevFeeStageUpdate(userFeeStage);
    }

    function setDevDepFee(uint256 _devDepFees) external onlyAuthorized() {
        devDepFee = _devDepFees;
        emit DevDepFeeUpdate(devDepFee);
    }

    function setUserDepFee(uint256 _usrDepFees) external onlyAuthorized() {
        userDepFee = _usrDepFees;
        emit UserDepFeeUpdate(userDepFee);
    }

    function reclaimTokenOwnership(address _newOwner) external onlyAuthorized() {
        govToken.transferOwnership(_newOwner);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Authorizable.sol";

// The SatoruFiToken
contract SatoruFiToken is ERC20, Ownable, Authorizable {
    uint256 private _cap;
    uint256 private _totalLock;
    uint256 public lockFromBlock;
    uint256 public lockToBlock;
    uint256 public manualMintLimit;
    uint256 public manualMinted = 0;

    mapping(address => uint256) private _locks;
    mapping(address => uint256) private _lastUnlockBlock;

    event Lock(address indexed to, uint256 value);
    event CapUpdate(uint256 _cap);
    event LockFromBlockUpdate(uint256 _block);
    event LockToBlockUpdate(uint256 _block);

    constructor(
      string memory _name,
      string memory _symbol,
      uint256 cap_,
      uint256 _manualMintLimit,
      uint256 _lockFromBlock,
      uint256 _lockToBlock
    ) public ERC20(_name, _symbol) {
        _cap = cap_;
        manualMintLimit = _manualMintLimit;
        lockFromBlock = _lockFromBlock;
        lockToBlock = _lockToBlock;
    }

    /**
     * @dev Returns the cap on the token's total supply.
     */
    function cap() external view returns (uint256) {
        return _cap;
    }

    // Update the total cap - can go up or down but wont destroy previous tokens.
    function capUpdate(uint256 _newCap) external onlyAuthorized {
        _cap = _newCap;
        emit CapUpdate(_cap);
    }

    // Update the lockFromBlock
    function lockFromUpdate(uint256 _newLockFrom) external onlyAuthorized {
        lockFromBlock = _newLockFrom;
        emit LockFromBlockUpdate(lockFromBlock);
    }

    // Update the lockToBlock
    function lockToUpdate(uint256 _newLockTo) external onlyAuthorized {
        lockToBlock = _newLockTo;
        emit LockToBlockUpdate(lockToBlock);
    }

    function unlockedSupply() external view returns (uint256) {
        return totalSupply().sub(_totalLock);
    }

    function lockedSupply() external view returns (uint256) {
        return totalLock();
    }

    function circulatingSupply() external view returns (uint256) {
        return totalSupply();
    }

    function totalLock() public view returns (uint256) {
        return _totalLock;
    }

    /**
     * @dev See {ERC20-_beforeTokenTransfer}.
     *
     * Requirements:
     *
     * - minted tokens must not cause the total supply to go over the cap.
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, amount);

        if (from == address(0)) {
            // When minting tokens
            require(
                totalSupply().add(amount) <= _cap,
                "ERC20Capped: cap exceeded"
            );
        }
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
    ) internal virtual override {
        super._transfer(sender, recipient, amount);
        _moveDelegates(_delegates[sender], _delegates[recipient], amount);
    }

    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterBreeder).
    function mint(address _to, uint256 _amount) external onlyOwner {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }

    function manualMint(address _to, uint256 _amount) external onlyAuthorized {
        require(manualMinted < manualMintLimit, "ERC20: manualMinted greater than manualMintLimit");
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
        manualMinted = manualMinted.add(_amount);
    }

    function totalBalanceOf(address _holder) external view returns (uint256) {
        return _locks[_holder].add(balanceOf(_holder));
    }

    function lockOf(address _holder) external view returns (uint256) {
        return _locks[_holder];
    }

    function lastUnlockBlock(address _holder) external view returns (uint256) {
        return _lastUnlockBlock[_holder];
    }

    function lock(address _holder, uint256 _amount) external onlyOwner {
        require(_holder != address(0), "ERC20: lock to the zero address");
        require(
            _amount <= balanceOf(_holder),
            "ERC20: lock amount over balance"
        );

        _transfer(_holder, address(this), _amount);

        _locks[_holder] = _locks[_holder].add(_amount);
        _totalLock = _totalLock.add(_amount);
        if (_lastUnlockBlock[_holder] < lockFromBlock) {
            _lastUnlockBlock[_holder] = lockFromBlock;
        }
        emit Lock(_holder, _amount);
    }

    function canUnlockAmount(address _holder) public view returns (uint256) {
        if (block.number < lockFromBlock) {
            return 0;
        } else if (block.number >= lockToBlock) {
            return _locks[_holder];
        } else {
            uint256 releaseBlock = block.number.sub(_lastUnlockBlock[_holder]);
            uint256 numberLockBlock =
                lockToBlock.sub(_lastUnlockBlock[_holder]);
            return _locks[_holder].mul(releaseBlock).div(numberLockBlock);
        }
    }

    function unlock() external {
        require(_locks[msg.sender] > 0, "ERC20: cannot unlock");

        uint256 amount = canUnlockAmount(msg.sender);
        // just for sure
        if (amount > balanceOf(address(this))) {
            amount = balanceOf(address(this));
        }
        _transfer(address(this), msg.sender, amount);
        _locks[msg.sender] = _locks[msg.sender].sub(amount);
        _lastUnlockBlock[msg.sender] = block.number;
        _totalLock = _totalLock.sub(amount);
    }

    // This function is for dev address migrate all balance to a multi sig address
    function transferAll(address _to) external {
        _locks[_to] = _locks[_to].add(_locks[msg.sender]);

        if (_lastUnlockBlock[_to] < lockFromBlock) {
            _lastUnlockBlock[_to] = lockFromBlock;
        }

        if (_lastUnlockBlock[_to] < _lastUnlockBlock[msg.sender]) {
            _lastUnlockBlock[_to] = _lastUnlockBlock[msg.sender];
        }

        _locks[msg.sender] = 0;
        _lastUnlockBlock[msg.sender] = 0;

        _transfer(msg.sender, _to, balanceOf(msg.sender));
    }

    // Copied and modified from YAM code:
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernanceStorage.sol
    // https://github.com/yam-finance/yam-protocol/blob/master/contracts/token/YAMGovernance.sol
    // Which is copied and modified from COMPOUND:
    // https://github.com/compound-finance/compound-protocol/blob/master/contracts/Governance/Comp.sol

    /// @dev A record of each accounts delegate
    mapping(address => address) internal _delegates;

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @notice A record of votes checkpoints for each account, by index
    mapping(address => mapping(uint32 => Checkpoint)) public checkpoints;

    /// @notice The number of checkpoints for each account
    mapping(address => uint32) public numCheckpoints;

    /// @notice The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256(
            "EIP712Domain(string name,uint256 chainId,address verifyingContract)"
        );

    /// @notice The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH =
        keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @notice A record of states for signing / validating signatures
    mapping(address => uint256) public nonces;

    /// @notice An event thats emitted when an account changes its delegate
    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    /// @notice An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator) external view returns (address) {
        return _delegates[delegator];
    }

    /**
     * @notice Delegate votes from `msg.sender` to `delegatee`
     * @param delegatee The address to delegate votes to
     */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @notice Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint256 nonce,
        uint256 expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        bytes32 domainSeparator =
            keccak256(
                abi.encode(
                    DOMAIN_TYPEHASH,
                    keccak256(bytes(name())),
                    getChainId(),
                    address(this)
                )
            );

        bytes32 structHash =
            keccak256(
                abi.encode(DELEGATION_TYPEHASH, delegatee, nonce, expiry)
            );

        bytes32 digest =
            keccak256(
                abi.encodePacked("\x19\x01", domainSeparator, structHash)
            );

        address signatory = ecrecover(digest, v, r, s);
        require(
            signatory != address(0),
            "SatoruFiToken::delegateBySig: invalid signature"
        );
        require(
            nonce == nonces[signatory]++,
            "SatoruFiToken::delegateBySig: invalid nonce"
        );
        require(now <= expiry, "SatoruFiToken::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account) external view returns (uint256) {
        uint32 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint256 blockNumber)
        external
        view
        returns (uint256)
    {
        require(
            blockNumber < block.number,
            "SatoruFiToken::getPriorVotes: not yet determined"
        );

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld =
                    srcRepNum > 0
                        ? checkpoints[srcRep][srcRepNum - 1].votes
                        : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld =
                    dstRepNum > 0
                        ? checkpoints[dstRep][dstRepNum - 1].votes
                        : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        uint32 blockNumber =
            safe32(
                block.number,
                "SatoruFiToken::_writeCheckpoint: block number exceeds 32 bits"
            );

        if (
            nCheckpoints > 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                blockNumber,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    function safe32(uint256 n, string memory errorMessage)
        internal
        pure
        returns (uint32)
    {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint256) {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        return chainId;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Authorizable is Ownable {
    mapping(address => bool) public authorized;

    modifier onlyAuthorized() {
        require(authorized[msg.sender] || owner() == msg.sender);
        _;
    }

    function addAuthorized(address _toAdd) external onlyOwner {
        authorized[_toAdd] = true;
    }

    function removeAuthorized(address _toRemove) external onlyOwner {
        require(_toRemove != msg.sender);
        authorized[_toRemove] = false;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor () internal {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}
