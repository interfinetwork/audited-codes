pragma solidity 0.8.7;
import { IBEP20 } from './interfaces/IBEP20.sol';
import { SafeBEP20 } from './libs/SafeBEP20.sol';
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import { ValonToken } from './ValonToken.sol';

contract ValonStaking is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct PoolInfo {
        IBEP20 lpToken;             // Contract of the LPT            
        uint256 totalPoolStakes;
        uint256 totalPoolRewards;
        uint256 bonusMultiplier;
        bool active;
        uint256 stakeHolderCount;
    }
    
    ValonToken public valon;
    mapping(address => PoolInfo) pools;                                     // LPT token address -> PoolInfo

    // LPT address -> [user address -> value]
    mapping(address => mapping(address => uint256)) private stakes;          // Amount of staked LPT
    mapping(address => mapping(address => uint256)) private blockHeights;    // Latest blockheight when user started staking
    mapping(address => mapping(address => uint256)) private rewards;         // Accumulated rewards

    uint256 private _startBlockHeight;
    uint256 private _totalRewards;
    uint256 private _totalStakes;
    uint256 private _difficulty;
    uint256 private _rewardsPerBlock;
    uint256 private _rewardCap;
    bool private _timelockActive;
    uint256 private _timelockHeight;
    uint256 private _activePoolsCount;
    bool private _sharePoolRewards;
    uint256 private _precision;

    constructor(
        ValonToken valonToken,
        uint256 rewardCapEth,       // default 250000000 eth
        uint256 difficulty,         // default 100
        uint256 rewardsPerBlock     // default 4822530864197531000
    ) {
        valon = valonToken;
        _startBlockHeight = block.number;
        _totalRewards = 0;
        _totalStakes = 0;
        _difficulty = difficulty;
        _rewardsPerBlock = rewardsPerBlock.div(difficulty); // mul difficulty 100
        _rewardCap = _to18Digits(rewardCapEth, 0);
        _timelockHeight = 0;
        _activePoolsCount = 0;
        _sharePoolRewards = false;
        _precision = 1000000000000000000;
    }

    function createPool(address lptAddress) public onlyOwner {
        IBEP20 lptContract = IBEP20(lptAddress);
        require(pools[lptAddress].lpToken != lptContract, "BEP20: pool already created");

        pools[lptAddress] = PoolInfo({
            lpToken: lptContract,           
            totalPoolStakes: 0,
            totalPoolRewards: 0,
            bonusMultiplier: 0,
            active: true,
            stakeHolderCount: 0
        });

        _activePoolsCount = _activePoolsCount.add(1);
    }

    function getPoolInfo(address lptAddress) public view returns(PoolInfo memory) {
        return pools[lptAddress];
    }

    function getBlockHeight() public view returns(uint256) {
        return block.number;
    }

    function getStartBlockHeight() public view returns(uint256) {
        return _startBlockHeight;
    }

    function _updateRewards(address poolAddress, address stakeHolder) private {
        if (stakes[poolAddress][stakeHolder] > 0 && pools[poolAddress].active) {
            uint256 unrealizedRewards = this.getUnrealizedRewards(poolAddress, stakeHolder);

            if (unrealizedRewards > 0) {
                rewards[poolAddress][stakeHolder] = rewards[poolAddress][stakeHolder].add(unrealizedRewards);
                pools[poolAddress].totalPoolRewards = pools[poolAddress].totalPoolRewards.add(unrealizedRewards);
                _totalRewards = _totalRewards.add(unrealizedRewards);
            }
        }
    }

    function _addBonusToRewards(uint256 rewardAmount, uint256 bonusMultiplier) private view returns(uint256) {
        uint256 rewardBonus = rewardAmount.mul(bonusMultiplier).div(_precision);
        uint256 totalRewards = rewardAmount.add(rewardBonus);
        return totalRewards;
    }

    function _applyPoolShare(uint256 rewardAmount) private view returns(uint256) {
        return rewardAmount.div(_activePoolsCount);
    }

    function _updateStakeHolderCount(address poolAddress, address stakeHolder, bool addingStake) private {
        if (addingStake) {
            if (getStake(poolAddress, stakeHolder) == 0) {
                pools[poolAddress].stakeHolderCount = pools[poolAddress].stakeHolderCount.add(1);
            }
        } else {
            if (getStake(poolAddress, stakeHolder) == 0) {
                pools[poolAddress].stakeHolderCount = pools[poolAddress].stakeHolderCount.sub(1);
            }
        }
    }

    function addStake(address poolAddress, uint256 lptAmount) public {
        require(lptAmount > 0, "BEP20: stake needs to be more than 0");
        require(address(pools[poolAddress].lpToken) != address(0), "BEP20: pool not created");
        require(getLptBalance(poolAddress, msg.sender) >= lptAmount, "BEP20: not enough balance");
        require(pools[poolAddress].active == true, "BEP20: pool is not active");

        //update rewards
        _updateStakeHolderCount(poolAddress, msg.sender, true);
        _updateRewards(poolAddress, msg.sender);
        pools[poolAddress].lpToken.safeTransferFrom(msg.sender, address(this), lptAmount);
        stakes[poolAddress][msg.sender] = stakes[poolAddress][msg.sender].add(lptAmount);
        pools[poolAddress].totalPoolStakes = pools[poolAddress].totalPoolStakes.add(lptAmount);
        _totalStakes = _totalStakes.add(lptAmount);
        blockHeights[poolAddress][msg.sender] = block.number;
    }

    function removeStake(address poolAddress, uint256 lptAmount) public {
        require(lptAmount > 0, "BEP20: amount needs to be more than 0");
        require(lptAmount <= this.getStake(poolAddress, msg.sender), "BEP20: amount more than staking balance");
        if (_timelockActive) {
            uint256 blocks = block.number.sub(blockHeights[poolAddress][msg.sender]);
            require(blocks >= _timelockHeight, "BEP20: Timelock still active");
        }

        // update rewards
        _updateRewards(poolAddress, msg.sender);
        stakes[poolAddress][msg.sender] = stakes[poolAddress][msg.sender].sub(lptAmount);
        pools[poolAddress].totalPoolStakes = pools[poolAddress].totalPoolStakes.sub(lptAmount);
        _totalStakes = _totalStakes.sub(lptAmount);
        blockHeights[poolAddress][msg.sender] = block.number;
        _updateStakeHolderCount(poolAddress, msg.sender, false);
        pools[poolAddress].lpToken.safeTransfer(msg.sender, lptAmount);
    }

    function claimRewards(address poolAddress) public {
        uint256 actualRewards = this.getActualRewards(poolAddress, msg.sender);
        require(actualRewards > 0, "BEP20: no rewards available");

        _updateRewards(poolAddress, msg.sender);
        uint256 reward = rewards[poolAddress][msg.sender];
        rewards[poolAddress][msg.sender] = 0;
        blockHeights[poolAddress][msg.sender] = block.number;
        valon.mintTo(msg.sender, reward);
    }

    function _to18Digits(uint256 num, uint decimalz) pure private returns (uint256) {
        return num * (10**(18 - decimalz));
    }

    function getStake(address poolAddress, address userAddress) public view returns(uint256) {
        return stakes[poolAddress][userAddress];
    }

    function getLptBalance(address poolAddress, address userAddress) public view returns(uint256) {
        if (address(pools[poolAddress].lpToken) == address(0)) { return 0; }
        return pools[poolAddress].lpToken.balanceOf(userAddress);
    }

    function getStakeBlockheight(address poolAddress, address stakeHolder) public view returns(uint256) {
        return blockHeights[poolAddress][stakeHolder];
    }

    function getTotalStakes() public view returns(uint256) {
        return _totalStakes;
    }

    function getTotalRewards() public view returns(uint256) {
        return _totalRewards;
    }

    function getRealizedRewards(address poolAddress, address rewardHolder) public view returns(uint256) {
        return rewards[poolAddress][rewardHolder];
    }

    function getMaxDifficulty() public view returns(uint256) {
        return _difficulty;
    }

    function getDifficulty() public view returns(uint256) {
        uint256 totalRewards = _totalRewards;
        if (totalRewards >= _rewardCap) { totalRewards = _rewardCap; }

        uint256 ratio = totalRewards.mul(_precision).div(_rewardCap);
        uint256 difficulty = ratio.mul(_difficulty).div(_precision);
        uint256 result = _difficulty.sub(difficulty);
        if (result <= 1) { result = 1; }
        return result;
    }

    function getPoolStakingPower(address poolAddress) public view returns(uint256) {
        PoolInfo memory poolInfo = getPoolInfo(poolAddress);
        if (poolInfo.totalPoolStakes <= 0) { return 0; }
        return poolInfo.totalPoolStakes.mul(_precision).div(_totalStakes);
    }

    function getRewardsPerBlock() public view returns(uint256) {
        uint256 divider = _difficulty.div(100);
        return _rewardsPerBlock.mul(this.getDifficulty()).div(divider);
    }

    function getStakingPower(address poolAddress, address stakeholder) public view returns(uint256) {
        PoolInfo memory poolInfo = getPoolInfo(poolAddress);
        if (stakes[poolAddress][stakeholder] <= 0 || poolInfo.totalPoolStakes <= 0) { return 0; }
        return stakes[poolAddress][stakeholder].mul(_precision).div(poolInfo.totalPoolStakes);
    }

    function getUnrealizedRewards(address poolAddress, address rewardHolder) public view returns(uint256) {
        uint256 userBlockheight = getStakeBlockheight(poolAddress, rewardHolder);
        if (userBlockheight <= 0 || userBlockheight >= block.number) { return 0; }

        uint256 blockHeight = block.number;
        uint256 blocks = blockHeight.sub(userBlockheight);
        uint256 stakePower = getStakingPower(poolAddress, rewardHolder);
        if (stakePower <= 0) { return 0; }

        uint256 blockReward = blocks.mul(this.getRewardsPerBlock());
        uint256 totalReward = stakePower.mul(blockReward).div(_precision);
        if (pools[poolAddress].bonusMultiplier > 0) {
            totalReward = _addBonusToRewards(totalReward, pools[poolAddress].bonusMultiplier);
        }

        if (_sharePoolRewards) {
            totalReward = _applyPoolShare(totalReward);
        }

        return totalReward;
    }

    function getActualRewards(address poolAddress, address rewardHolder) public view returns(uint256) {
        uint256 realizedRewards = this.getRealizedRewards(poolAddress, rewardHolder);
        uint256 unrealizedRewards = this.getUnrealizedRewards(poolAddress, rewardHolder);
        if (unrealizedRewards <= 0) { return realizedRewards; }
        return realizedRewards.add(unrealizedRewards);
    }

    function setTimelock(bool active) public onlyOwner {
        _timelockActive = active;
    }

    function setTimelockHeight(uint256 blocks) public onlyOwner {
        _timelockHeight = blocks;
    }

    function setPoolActive(address poolAddress, bool active) public onlyOwner {
        require(pools[poolAddress].active != active, "BEP20: setting active to same value");

        pools[poolAddress].active = active;
        if (active) {
            _activePoolsCount = _activePoolsCount.add(1);
        } else {
            _activePoolsCount = _activePoolsCount.sub(1);
        }
    }

    function setPoolBonus(address poolAddress, uint256 bonus) public onlyOwner {
        pools[poolAddress].bonusMultiplier = bonus;
    }

    function setRewardCap(uint256 amountEth) public onlyOwner {
        _rewardCap = amountEth;
    }

    function getActivePoolsCount() public view returns(uint256) {
        return _activePoolsCount;
    }

    function setSharePoolRewards(bool active) public onlyOwner {
        _sharePoolRewards = active;
    }

    /**
     * DEBUG
     * * * * * * */
    function setTotalRewards(uint256 totalRewards) public onlyOwner {
        _totalRewards = totalRewards;
    }

    function setDifficulty(uint256 difficulty) public onlyOwner {
        _difficulty = difficulty;
    }
}