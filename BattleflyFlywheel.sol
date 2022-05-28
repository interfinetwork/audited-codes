// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/IERC1155Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeCastUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/structs/EnumerableSetUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


contract BattleflyFounderVault is
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ============================================ STATE ==============================================
    struct FounderStake {
        uint256 amount;
        uint256 stakeTimestamp;
        address owner;
        uint256[] founderNFTIDs;
        uint256 lastClaimedDay;
    }
    struct DailyFounderEmission {
        uint256 totalEmission;
        uint256 totalFounders;
    }
    // ============= Global Immutable State ==============

    /// @notice MAGIC token
    /// @dev functionally immutable
    IERC20Upgradeable public magic;
    ISpecialNFT public founderNFT;
    uint256 public founderTypeID;
    IBattleflyAtlasStaker public BattleflyStaker;
    uint256 public startTimestamp;
    // ============= Global mutable State ==============
    uint256 totalEmission;
    uint256 claimedEmission;
    uint256 pendingFounderEmission;

    mapping(address => EnumerableSetUpgradeable.UintSet)
        private FounderStakeOfOwner;
    uint256 lastStakeTimestamp;
    mapping(uint256 => FounderStake) public FounderStakes;
    uint256 lastStakeId;
    mapping(address => bool) private adminAccess;
    uint256 public DaysSinceStart;
    mapping(uint256 => DailyFounderEmission) public DailyFounderEmissions;

    uint256 withdrawnOldFounder;
    uint256 unupdatedStakeIdFrom;

    uint256 public stakeBackPercent;
    uint256 public treasuryPercent;
    uint256 public v2VaultPercent;

    IBattleflyFounderVault battleflyFounderVaultV2;
    IBattleflyFlywheelVault battleflyFlywheelVault;
    // ============= Constant ==============
    address public constant TREASURY_WALLET = 0xF5411006eEfD66c213d2fd2033a1d340458B7226;
    uint256 public constant PERCENT_DENOMINATOR = 10000;
    IAtlasMine.Lock public constant DEFAULT_STAKE_BACK_LOCK = IAtlasMine.Lock.twoWeeks;
    // ============================================ EVENTS ==============================================
    event ClaimDailyEmission(uint256 dayTotalEmission, uint256 totalFounderEmission, uint256 totalFounders, uint256 stakeBackAmount, uint256 treasuryAmount, uint256 v2VaultAmount);
    event Claim(address user, uint256 stakeId, uint256 amount, uint256[] founderNFTIDs);
    event Withdraw(address user, uint256 stakeId, uint256[] founderNFTIDs);
    event Stake(address user, uint256 stakeId, uint256[] founderNFTIDs);
    event TopupMagicToStaker(address user, uint256 amount, IAtlasMine.Lock lock);
    event TopupTodayEmission(address user, uint256 amount);
    
    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _magicAddress,
        address _BattleflyStakerAddress,
        uint256 _founderTypeID,
        address _founderNFTAddress,
        uint256 _startTimestamp,
        address _battleflyFounderVaultV2Address,
        uint256 _stakeBackPercent,
        uint256 _treasuryPercent,
        uint256 _v2VaultPercent
    ) external initializer {
        __ERC1155Holder_init();
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        founderNFT = (ISpecialNFT(_founderNFTAddress));
        founderTypeID = _founderTypeID;
        lastStakeTimestamp = block.timestamp;
        lastStakeId = 0;
        startTimestamp = _startTimestamp;
        DaysSinceStart = 0;
        stakeBackPercent = _stakeBackPercent;
        treasuryPercent = _treasuryPercent;
        v2VaultPercent = _v2VaultPercent;
        if(_battleflyFounderVaultV2Address ==address(0))
            battleflyFounderVaultV2 = IBattleflyFounderVault(address(this));
        else
            battleflyFounderVaultV2 = IBattleflyFounderVault(_battleflyFounderVaultV2Address);

        require(stakeBackPercent + treasuryPercent + v2VaultPercent < PERCENT_DENOMINATOR);
 
        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }

    // ============================================ USER OPERATIONS ==============================================
    function stakesOf(address owner) view external returns (FounderStake[] memory) {
        FounderStake[] memory stakes = new FounderStake[](FounderStakeOfOwner[owner].length());
        for(uint256 i = 0; i < FounderStakeOfOwner[owner].length(); i++) {
            stakes[i] = FounderStakes[FounderStakeOfOwner[owner].at(i)];
        }
        return stakes;
    }
    function stakeFounderNFT(uint256[] memory ids) external {
        require(ids.length != 0, "Must provide at least one founder NFT ID");
        for (uint256 i = 0; i < ids.length; i++) {
            require(
                founderNFT.getSpecialNFTType(ids[i]) == founderTypeID,
                "Not valid founder NFT"
            );
            founderNFT.safeTransferFrom(msg.sender, address(this), ids[i]);
        }
        uint256 currentDay = (block.timestamp - startTimestamp) / 24 hours;
        lastStakeId++;
        FounderStakes[lastStakeId] = (
            FounderStake({
                amount: ids.length,
                stakeTimestamp: block.timestamp,
                owner: msg.sender,
                founderNFTIDs: ids,
                lastClaimedDay: currentDay
            })
        );
        FounderStakeOfOwner[msg.sender].add(lastStakeId);
        emit Stake(msg.sender, lastStakeId, ids);
    }
    function claimAll() external nonReentrant {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[msg.sender].length(); i++) {
            totalReward +=   _claim(FounderStakeOfOwner[msg.sender].at(i));
        }
        require(totalReward > 0, "No reward to claim");
    }
    function withdrawAll() external nonReentrant {
        require(FounderStakeOfOwner[msg.sender].length() > 0, "No STAKE to withdraw");
        uint256 totalWithdraw = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[msg.sender].length(); i++) {
            totalWithdraw += _withdraw(FounderStakeOfOwner[msg.sender].at(i));
        }
        (uint256 stakeableAmount, uint256 stakingAmount) = battleflyFlywheelVault.getStakeAmount(msg.sender);
        uint256 stakeableAmountPerFounder = battleflyFlywheelVault.stakeableAmountPerFounder(address(this));
        require(stakingAmount <= stakeableAmount - stakeableAmountPerFounder * totalWithdraw, "Pls withdraw FlywheelVault first");
    }
    function withdraw(uint256[] memory stakeIds) external nonReentrant {
        require(stakeIds.length > 0, "No STAKE to withdraw");
        uint256 totalWithdraw = 0;
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(FounderStakes[stakeIds[i]].owner == msg.sender, "Not your stake");
            totalWithdraw +=  _withdraw(stakeIds[i]);
        }
        (uint256 stakeableAmount, uint256 stakingAmount) = battleflyFlywheelVault.getStakeAmount(msg.sender);
        uint256 stakeableAmountPerFounder = battleflyFlywheelVault.stakeableAmountPerFounder(address(this));
        require(stakingAmount <= stakeableAmount - stakeableAmountPerFounder * totalWithdraw, "Pls withdraw FlywheelVault first");
    }
    function claim(uint256[] memory stakeIds) external nonReentrant {
        require(stakeIds.length > 0, "No STAKE to claim");
        for (uint256 i = 0; i < stakeIds.length; i++) {
            require(FounderStakes[stakeIds[i]].owner == msg.sender, "Not your stake");
            _claim(stakeIds[i]);
        }
    }
    function _claim(uint256 stakeId) internal returns (uint256) {
        FounderStake storage stake = FounderStakes[stakeId];
        uint256 totalReward = _getClaimableEmissionOf(stakeId);
        claimedEmission += totalReward;
        stake.lastClaimedDay = DaysSinceStart;
        magic.safeTransfer(stake.owner, totalReward);
        emit Claim(stake.owner, stakeId, totalReward, stake.founderNFTIDs);
        return totalReward;
    }
    function getClaimableEmissionOf(address user) public view returns (uint256) {
        uint256 totalReward = 0;
        for (uint256 i = 0; i < FounderStakeOfOwner[user].length(); i++) {
            totalReward += _getClaimableEmissionOf(FounderStakeOfOwner[user].at(i));
        }
        return totalReward;
    }
    function _getClaimableEmissionOf(uint256 stakeId) internal view returns(uint256) {
        uint256 totalReward = 0;
        FounderStake memory stake = FounderStakes[stakeId];
        if(stake.lastClaimedDay == DaysSinceStart) return 0;
        for (uint256 j = stake.lastClaimedDay + 1; j <= DaysSinceStart; j++) {
            totalReward +=
                (DailyFounderEmissions[j].totalEmission /
                    DailyFounderEmissions[j].totalFounders) *
                stake.amount;
        }
        return totalReward;
    }
    function _withdraw(uint256 stakeId) internal returns (uint256)  {
        FounderStake storage stake = FounderStakes[stakeId];
        uint256 withdrawAmount = stake.amount;
        _claim(stakeId);
        for (uint256 i = 0; i < stake.amount; i++) {
            founderNFT.safeTransferFrom(
                address(this),
                stake.owner,
                stake.founderNFTIDs[i]
            );
        }
        FounderStakeOfOwner[stake.owner].remove(stakeId);
        if(stake.stakeTimestamp < (startTimestamp + (DaysSinceStart) * 24 hours - 24 hours)) {
            withdrawnOldFounder += stake.amount;
        }
        emit Withdraw(stake.owner, stakeId, stake.founderNFTIDs);
        delete FounderStakes[stakeId];
        return withdrawAmount;
    }
    // ============================================ ADMIN OPERATIONS ==============================================
    function topupMagicToStaker(uint256 amount, IAtlasMine.Lock lock) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _depositToStaker(amount, lock);
        emit TopupMagicToStaker(msg.sender, amount, lock);
    }
    function topupTodayEmission(uint256 amount) external onlyAdminAccess {
        require(amount > 0);
        magic.safeTransferFrom(msg.sender, address(this), amount);
        pendingFounderEmission += amount;
        emit TopupTodayEmission(msg.sender, amount);
    }
    function depositToStaker(uint256 amount, IAtlasMine.Lock lock)
        external
        onlyAdminAccess
    {
        require(magic.balanceOf(address(this)) >= amount);
        require(amount > 0);
        _depositToStaker(amount, lock);
    }
    function _depositToStaker(uint256 amount, IAtlasMine.Lock lock) internal {
        BattleflyStaker.deposit(amount, lock);
    }
    function claimDailyEmission() public onlyAdminAccess nonReentrant {
        uint256 currentDay = (block.timestamp - startTimestamp) / 24 hours;
        require(currentDay > DaysSinceStart, "Cant claim again for today");
        uint256 todayTotalEmission = BattleflyStaker.claimAll();
        uint256 todayTotalFounderNFTs =  _updateTotalStakingFounders(currentDay);

        uint256 stakeBackAmount;
        uint256 v2VaultAmount;
        uint256 treasuryAmount;
        uint256 founderEmission;
        if(todayTotalEmission != 0) {

            stakeBackAmount = todayTotalEmission * stakeBackPercent / PERCENT_DENOMINATOR;
            if(stakeBackAmount != 0) _depositToStaker(stakeBackAmount, DEFAULT_STAKE_BACK_LOCK);

            v2VaultAmount = todayTotalEmission * v2VaultPercent / PERCENT_DENOMINATOR;
            if(v2VaultAmount != 0) battleflyFounderVaultV2.topupMagicToStaker(v2VaultAmount, DEFAULT_STAKE_BACK_LOCK);

            treasuryAmount = todayTotalEmission * treasuryPercent / PERCENT_DENOMINATOR;
            if(treasuryAmount != 0) magic.safeTransfer(TREASURY_WALLET, treasuryAmount);

            founderEmission += todayTotalEmission - stakeBackAmount - v2VaultAmount - treasuryAmount;
            

        }
        if(pendingFounderEmission > 0) {
                founderEmission += pendingFounderEmission;
                pendingFounderEmission = 0;
        }
        totalEmission += founderEmission;
        DaysSinceStart = currentDay;
        DailyFounderEmissions[DaysSinceStart] = DailyFounderEmission({
                totalEmission: founderEmission,
                totalFounders: todayTotalFounderNFTs
        });
        emit  ClaimDailyEmission(todayTotalEmission, founderEmission, todayTotalFounderNFTs, stakeBackAmount, treasuryAmount, v2VaultAmount);
    }
    function withdrawAllFromStaker() external onlyAdminAccess {
        claimDailyEmission();
        BattleflyStaker.withdrawAll();
    }
    function withdrawFromVault(address receiver, uint256 amount) external onlyAdminAccess {
        magic.safeTransfer(receiver, amount);
    }
    function _updateTotalStakingFounders(uint256 currentDay)
        private
        returns (uint256)
    {
        uint256 result = DailyFounderEmissions[DaysSinceStart].totalFounders - withdrawnOldFounder;
        withdrawnOldFounder = 0;
        uint256 to = startTimestamp + currentDay * 24 hours;
        uint256 i = unupdatedStakeIdFrom;
        for (; i <= lastStakeId; i++) {
            if (FounderStakes[i].stakeTimestamp == 0 ) {
                continue;
            }
            if (
            FounderStakes[i].stakeTimestamp > to
            ){
                break;
            }
            result += FounderStakes[i].amount;
        }
        unupdatedStakeIdFrom = i;
        return result;
    }
    //Must be called right after init
    function setFlywheelVault(address vault) external onlyOwner {
        require(vault != address(0));
        battleflyFlywheelVault = IBattleflyFlywheelVault(vault);
    }
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
    }
    modifier onlyAdminAccess() {
        require(
            adminAccess[_msgSender()] || _msgSender() == owner(),
            "Require admin access"
        );
        _;
    }
}
contract BattleflyAtlasStaker is
    IBattleflyAtlasStaker,
    Initializable,
    OwnableUpgradeable,
    ERC1155HolderUpgradeable,
    ERC721HolderUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;


    // ============================================ STATE ==============================================

    // ============= Global Immutable State ==============

    /// @notice MAGIC token
    /// @dev functionally immutable
    IERC20Upgradeable public magic;
    /// @notice The IAtlasMine
    /// @dev functionally immutable
    IAtlasMine public mine;



    // ============= Global Staking State ==============
    uint256 public constant ONE = 1e30;

    /// @notice Whether new stakes will get staked on the contract as scheduled. For emergencies
    bool public schedulePaused;
    /// @notice The total amount of staked token
    uint256 public totalStaked;
    /// @notice The total amount of share
    uint256 public totalShare;
    /// @notice All stakes currently active
    Stake[] public stakes;
    /// @notice Deposit ID of last stake. Also tracked in atlas mine
    uint256 public lastDepositId;
    /// @notice Rewards accumulated per share
    uint256 public accRewardsPerShare;

    // ============= Vault Staking State ==============
    mapping(address => bool) public battleflyVaults;

    /// @notice Each vault stake, keyed by vault contract address => deposit ID
    mapping(address => mapping(uint256 => VaultStake)) public vaultStake;
    /// @notice All deposit IDs fro a vault, enumerated
    mapping(address => EnumerableSetUpgradeable.UintSet) private allVaultDepositIds;
    /// @notice The current ID of the vault's last deposited stake
    mapping(address => uint256) public currentId;

    // ============= NFT Boosting State ==============

    /// @notice Holder of treasures and legions
    mapping(uint256 => bool) public legionsStaked;
    mapping(uint256 => uint256) public treasuresStaked;

    // ============= Operator State ==============

    IAtlasMine.Lock[] public allowedLocks;
    /// @notice Fee to contract operator. Only assessed on rewards.
    uint256 public fee;
    /// @notice Amount of fees reserved for withdrawal by the operator.
    uint256 public feeReserve;
    /// @notice Max fee the owner can ever take - 10%
    uint256 public constant MAX_FEE = 1000;
    uint256 public constant FEE_DENOMINATOR = 10000;

    mapping(address => mapping(uint256 =>  int256)) refundedFeeDebts;
    uint256 accRefundedFeePerShare;
    uint256 totalWhitelistedFeeShare;
    EnumerableSetUpgradeable.AddressSet whitelistedFeeVaults;
    mapping(address => bool) public superAdmins;

    /// @notice deposited but unstaked
    uint256 public unstakedDeposits;
    mapping(IAtlasMine.Lock => uint256) public unstakedDepositsByLock;
    address public constant TREASURY_WALLET = 0xF5411006eEfD66c213d2fd2033a1d340458B7226;
    /// @notice Intra-tx buffer for pending payouts
    uint256 public tokenBuffer;
    // ===========================================
    // ============== Post Upgrade ===============
    // ===========================================



    // ========================================== INITIALIZER ===========================================

    /**
     * @param _magic                The MAGIC token address.
     * @param _mine                 The IAtlasMine contract.
     *                              Maps to a timelock for IAtlasMine deposits.
     */
    function initialize(
        IERC20Upgradeable _magic,
        IAtlasMine _mine,
        IAtlasMine.Lock[] memory _allowedLocks
    ) external initializer {
        __ERC1155Holder_init();
        __ERC721Holder_init();
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = _magic;
        mine = _mine;
        allowedLocks = _allowedLocks;
        fee = 1000;
        // Approve the mine
        magic.safeApprove(address(mine), 2**256 - 1);
        approveNFTs();
    }

    // ======================================== VAULT OPERATIONS ========================================

    /**
     * @notice Make a new deposit into the Staker. The Staker will collect
     *         the tokens, to be later staked in atlas mine by the owner,
     *         according to the stake/unlock schedule.
     * @dev    Specified amount of token must be approved by the caller.
     *
     * @param _amount               The amount of tokens to deposit.
     */
    function deposit(uint256 _amount, IAtlasMine.Lock lock ) public virtual override onlyBattleflyVault nonReentrant returns (uint256) {
        require(!schedulePaused, "new staking paused");
        _updateRewards();
        // Collect tokens
        uint256 newDepositId = _deposit(_amount, msg.sender, lock);
        magic.safeTransferFrom(msg.sender, address(this), _amount);
        return (newDepositId);
    }
    function _deposit(uint256 _amount, address _vault, IAtlasMine.Lock lock) internal returns (uint256) {
        require(_amount > 0, "Deposit amount 0");
        bool validLock = false;
        for(uint256 i = 0; i < allowedLocks.length; i++) {
            if(allowedLocks[i] == lock) {
                validLock = true;
                break;
            }
        }
        require(validLock, "Lock time not allowed");
        // Add vault stake
        uint256 newDepositId = ++currentId[_vault];
        allVaultDepositIds[_vault].add(newDepositId);
        VaultStake storage s = vaultStake[_vault][newDepositId];

        s.amount = _amount;
        (uint256 boost,uint256 lockTime) =  getLockBoost(lock);
        uint256 share = _amount * (100e16 + boost)/100e16;
    

        uint256 vestingTime = mine.getVestingTime(lock);
        s.unlockAt = block.timestamp + lockTime + vestingTime + 1 days;
        s.rewardDebt = ((share * accRewardsPerShare) / ONE).toInt256();
        s.lock = lock;

        // Update global accounting
        totalStaked += _amount;
        totalShare += share;
        if(whitelistedFeeVaults.contains(_vault)) {
            totalWhitelistedFeeShare += share;
            refundedFeeDebts[_vault][newDepositId] = ((share * accRefundedFeePerShare) / ONE).toInt256();
        }
        // MAGIC tokens sit in contract. Added to pending stakes
        unstakedDeposits += _amount;
        unstakedDepositsByLock[lock] += _amount;
        emit VaultDeposit(_vault, newDepositId, _amount, s.unlockAt, s.lock);
        return newDepositId;
    }
    /**
     * @notice Withdraw a deposit from the Staker contract. Calculates
     *         pro rata share of accumulated MAGIC and distributes any
     *         earned rewards in addition to original deposit.
     *         There must be enough unlocked tokens to withdraw.
     *
     * @param depositId             The ID of the deposit to withdraw from.
     *
     */
    function withdraw(uint256 depositId) public virtual override onlyBattleflyVault nonReentrant {
        // Distribute tokens
        _updateRewards();
        VaultStake storage s = vaultStake[msg.sender][depositId];
        require(s.amount > 0, "No deposit");
        require(block.timestamp >= s.unlockAt, "Deposit locked");

        uint256 payout = _withdraw(s, depositId);
        magic.safeTransfer(msg.sender, payout);
    }

    /**
     * @notice Withdraw all eligible deposits from the staker contract.
     *         Will skip any deposits not yet unlocked. Will also
     *         distribute rewards for all stakes via 'withdraw'.
     *
     */
    function withdrawAll() public virtual override onlyBattleflyVault nonReentrant {
        // Distribute tokens
        _updateRewards();
        uint256[] memory depositIds = allVaultDepositIds[msg.sender].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            VaultStake storage s = vaultStake[msg.sender][depositIds[i]];

            if (s.amount > 0 && s.unlockAt > 0 && s.unlockAt <= block.timestamp) {
                tokenBuffer += _withdraw(s, depositIds[i]);
            }
        }
        magic.safeTransfer(msg.sender, tokenBuffer);
        tokenBuffer = 0;
    }

    /**
     * @dev Logic for withdrawing a deposit. Calculates pro rata share of
     *      accumulated MAGIC and dsitributed any earned rewards in addition
     *      to original deposit.
     *
     * @dev An _amount argument larger than the total deposit amount will
     *      withdraw the entire deposit.
     *
     * @param s                     The VaultStake struct to withdraw from.
     * @param depositId             The ID of the deposit to withdraw from (for event).
     */
    function _withdraw(
        VaultStake storage s,
        uint256 depositId
    ) internal returns (uint256 payout) {
        uint256 _amount = s.amount;


        // Unstake if we need to to ensure we can withdraw
        (uint256 boost,) =  getLockBoost(s.lock);
        uint256 share = _amount * (100e16 + boost)/100e16;
        int256 accumulatedRewards = ((share * accRewardsPerShare) / ONE).toInt256();
        if(whitelistedFeeVaults.contains(msg.sender)) {
            accumulatedRewards += ((share * accRefundedFeePerShare) / ONE).toInt256();
            accumulatedRewards -= refundedFeeDebts[msg.sender][depositId];
            totalWhitelistedFeeShare -= share;
            refundedFeeDebts[msg.sender][depositId] = 0;
        }
        uint256 reward = (accumulatedRewards - s.rewardDebt).toUint256();
        payout = _amount + reward;

        // // Update vault accounting
        // s.amount -= _amount;
        // s.rewardDebt = 0;
        ///comment Archethect: Consider deleting the VaultStake object for gas optimization. s.unlockAt and s.lock can be zeroed as well.
        delete vaultStake[msg.sender][depositId];

        // Update global accounting
        totalStaked -= _amount;

        totalShare -= share;

        // If we need to unstake, unstake until we have enough
        if (payout > _totalUsableMagic()) {
            _unstakeToTarget(payout - _totalUsableMagic());
        }
        emit VaultWithdraw(msg.sender, depositId, _amount, reward);
    }

    /**
     * @notice Claim rewards without unstaking. Will fail if there
     *         are not enough tokens in the contract to claim rewards.
     *         Does not attempt to unstake.
     *
     * @param depositId             The ID of the deposit to claim rewards from.
     *
     */
    function claim(uint256 depositId) public virtual override onlyBattleflyVault nonReentrant returns (uint256) {
         _updateRewards();
        VaultStake storage s = vaultStake[msg.sender][depositId];
        require(s.amount > 0, "No deposit");
        uint256 reward = _claim(s, depositId);
        magic.safeTransfer(msg.sender, reward);
        return reward;
    }

    /**
     * @notice Claim all possible rewards from the staker contract.
     *         Will apply to both locked and unlocked deposits.
     *
     */
    function claimAll() public virtual override onlyBattleflyVault nonReentrant returns (uint256) {
         _updateRewards();
        uint256[] memory depositIds = allVaultDepositIds[msg.sender].values();
        uint256 totalReward = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            VaultStake storage s = vaultStake[msg.sender][depositIds[i]];
            uint256 reward = _claim(s, depositIds[i]);
            tokenBuffer += reward;
        }
        magic.safeTransfer(msg.sender, tokenBuffer);
        tokenBuffer = 0;
        return totalReward;
    }
    /**
     * @notice Claim all possible rewards from the staker contract then restake.
     *         Will apply to both locked and unlocked deposits.
     *
     */
    function claimAllAndRestake(IAtlasMine.Lock lock) public  onlyBattleflyVault nonReentrant returns (uint256) {
         _updateRewards();
        uint256[] memory depositIds = allVaultDepositIds[msg.sender].values();
        uint256 totalReward = 0;
        for (uint256 i = 0; i < depositIds.length; i++) {
            VaultStake storage s = vaultStake[msg.sender][depositIds[i]];
            uint256 reward = _claim(s, depositIds[i]);
            tokenBuffer += reward;
        }
        _deposit(tokenBuffer, msg.sender, lock);
        tokenBuffer = 0;
        return totalReward;
    }
    /**
     * @dev Logic for claiming rewards on a deposit. Calculates pro rata share of
     *      accumulated MAGIC and dsitributed any earned rewards in addition
     *      to original deposit.
     *
     * @param s                     The VaultStake struct to claim from.
     * @param depositId             The ID of the deposit to claim from (for event).
     */
    function _claim(VaultStake storage s, uint256 depositId) internal returns (uint256) {
        // Update accounting
        (uint256 boost,) =  getLockBoost(s.lock);
        uint256 share = s.amount * (100e16 + boost)/100e16;

        int256 accumulatedRewards = ((share * accRewardsPerShare) / ONE).toInt256();

        uint256 reward = (accumulatedRewards - s.rewardDebt).toUint256();
        if(whitelistedFeeVaults.contains(msg.sender)) {
            int256 accumulatedRefundedFee = ((share * accRefundedFeePerShare) / ONE).toInt256();
            reward += accumulatedRefundedFee.toUint256();
            reward -= refundedFeeDebts[msg.sender][depositId].toUint256();
            refundedFeeDebts[msg.sender][depositId] = accumulatedRefundedFee;
        }
        s.rewardDebt = accumulatedRewards;

        // Unstake if we need to to ensure we can withdraw
        if (reward > _totalUsableMagic()) {
            _unstakeToTarget(reward - _totalUsableMagic());
        }

        require(reward <= _totalUsableMagic(), "Not enough rewards to claim");
        emit VaultClaim(msg.sender, depositId, reward);
        return reward;
    }


    // ======================================= SUPER ADMIN OPERATIONS ========================================

    /**
     * @notice Stake a Treasure owned by the superAdmin into the Atlas Mine.
     *         Staked treasures will boost all vault deposits.
     * @dev    Any treasure must be approved for withdrawal by the caller.
     *
     * @param _tokenId              The tokenId of the specified treasure.
     * @param _amount               The amount of treasures to stake.
     */
    function stakeTreasure(uint256 _tokenId, uint256 _amount) external onlySuperAdmin {
        address treasureAddr = mine.treasure();
        require(IERC1155Upgradeable(treasureAddr).balanceOf(msg.sender, _tokenId) >= _amount, "Not enough treasures");
        treasuresStaked[_tokenId] += _amount;
        // First withdraw and approve
        IERC1155Upgradeable(treasureAddr).safeTransferFrom(msg.sender, address(this), _tokenId, _amount, bytes(""));
        mine.stakeTreasure(_tokenId, _amount);
        uint256 boost = mine.boosts(address(this));

        emit StakeNFT(msg.sender, treasureAddr, _tokenId, _amount, boost);
    }

    /**
     * @notice Unstake a Treasure from the Atlas Mine adn transfer to receiver.
     *
     * @param _receiver              The receiver .
     * @param _tokenId              The tokenId of the specified treasure.
     * @param _amount               The amount of treasures to stake.
     */
    function unstakeTreasure(address _receiver, uint256 _tokenId, uint256 _amount) external onlySuperAdmin {
        require(treasuresStaked[_tokenId] >= _amount, "Not enough treasures");
        treasuresStaked[_tokenId] -= _amount;
        address treasureAddr = mine.treasure();
        mine.unstakeTreasure(_tokenId, _amount);
        IERC1155Upgradeable(treasureAddr).safeTransferFrom(address(this), _receiver, _tokenId, _amount, bytes(""));
        uint256 boost = mine.boosts(address(this));
        emit UnstakeNFT(_receiver, treasureAddr, _tokenId, _amount, boost);
    }

    /**
     * @notice Stake a Legion owned by the superAdmin into the Atlas Mine.
     *         Staked legions will boost all vault deposits.
     * @dev    Any legion be approved for withdrawal by the caller.
     *
     * @param _tokenId              The tokenId of the specified legion.
     */
    function stakeLegion(uint256 _tokenId) external onlySuperAdmin {
        address legionAddr = mine.legion();
        require(IERC721Upgradeable(legionAddr).ownerOf(_tokenId) == msg.sender, "Not owner of legion");
        legionsStaked[_tokenId] = true;
        IERC721Upgradeable(legionAddr).safeTransferFrom(msg.sender, address(this), _tokenId);

        mine.stakeLegion(_tokenId);

        uint256 boost = mine.boosts(address(this));

        emit StakeNFT(msg.sender, legionAddr, _tokenId, 1, boost);
    }

    /**
     * @notice Unstake a Legion from the Atlas Mine and return it to the superAdmin.
     *
     * @param _tokenId              The tokenId of the specified legion.
     */
    function unstakeLegion(address _receiver, uint256 _tokenId) external onlySuperAdmin {
        require(legionsStaked[_tokenId] , "No legion");
        address legionAddr = mine.legion();
        delete legionsStaked[_tokenId];
        mine.unstakeLegion(_tokenId);

        // Distribute to superAdmin
        IERC721Upgradeable(legionAddr).safeTransferFrom(address(this), _receiver, _tokenId);
        uint256 boost = mine.boosts(address(this));

        emit UnstakeNFT(_receiver, legionAddr, _tokenId, 1, boost);
    }

    /**
     * @notice Stake any pending stakes before the current day. Callable
     *         by anybody. Any pending stakes will unlock according
     *         to the time this method is called, and the contract's defined
     *         lock time.
     */
    function stakeScheduled() external onlySuperAdmin virtual override {
        for(uint256 i = 0; i < allowedLocks.length; i++) {
            IAtlasMine.Lock lock = allowedLocks[i];
            _stakeInMine(unstakedDepositsByLock[lock], lock);
            unstakedDepositsByLock[lock] = 0;
        }
        unstakedDeposits = 0;
    }
      /**
     * @notice Unstake everything eligible for unstaking from Atlas Mine.
     *         Callable by owner. Should only be used in case of emergency
     *         or migration to a new contract, or if there is a need to service
     *         an unexpectedly large amount of withdrawals.
     *
     *         If unlockAll is set to true in the Atlas Mine, this can withdraw
     *         all stake.
     */
    function unstakeAllFromMine() external override onlySuperAdmin {
        // Unstake everything eligible
        _updateRewards();

        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory s = stakes[i];

            if (s.unlockAt > block.timestamp) {
                continue;
            }

            // Withdraw position - auto-harvest
            mine.withdrawPosition(s.depositId, s.amount);
        }

        // Only check for removal after, so we don't mutate while looping
        _removeZeroStakes();
    }

    /**
     * @notice Let owner unstake a specified amount as needed to make sure the contract is funded.
     *         Can be used to facilitate expected future withdrawals.
     *
     * @param target                The amount of tokens to reclaim from the mine.
     */
    function unstakeToTarget(uint256 target) external override onlySuperAdmin {
        _updateRewards();
        _unstakeToTarget(target);
    }
        /**
     * @notice Withdraw any accumulated reward fees to the treasury
     */
    function withdrawFeesToTreasury() external virtual onlySuperAdmin {
        uint256 amount = feeReserve;
        feeReserve = 0;
        magic.safeTransfer(TREASURY_WALLET, amount);
        emit WithdrawFeesToTreasury(amount);
    }
    function stakeBackFeeTreasury(IAtlasMine.Lock lock) external virtual onlySuperAdmin {
        uint256 amount = feeReserve;
        feeReserve = 0;
        emit WithdrawFeesToTreasury(amount);
        // magic.safeTransfer(TREASURY_WALLET, amount);
        _deposit(amount, TREASURY_WALLET, lock);
    }
    /**
     * @notice Whitelist vault from fees.
     *
     * @param _vault                Vault address.
     * @param isSet                 Whether to enable or disable the vault whitelist.
     */
    function setFeeWhitelistVault(address _vault, bool isSet) external onlyOwner {
        require(_vault != address(0), "Invalid Vault");
        if(isSet) {
            whitelistedFeeVaults.add(_vault);
            totalWhitelistedFeeShare += totalShareOf(_vault);
        } else {
            whitelistedFeeVaults.remove(_vault);
            totalWhitelistedFeeShare -= totalShareOf(_vault);
        }
        emit SetFeeWhitelistVault(_vault, isSet);
    }
    // ======================================= OWNER OPERATIONS =======================================

  


    function setBattleflyVault(address _vaultAddress, bool isSet) external  onlyOwner {
        require(_vaultAddress != address(0), "Invalid vault");
        if(isSet)
        {
                    require(battleflyVaults[_vaultAddress] == false, "Vault already set");
                    battleflyVaults[_vaultAddress] = isSet;
        }
        else
        {
            require(allVaultDepositIds[_vaultAddress].length() == 0, "Vault is still active");
            delete battleflyVaults[_vaultAddress];
        }
        emit SetBattleflyVault(_vaultAddress, isSet);
    }
    /**
     * @notice Change the designated superAdmin, the address where treasures and
     *         legions are held. Staked NFTs can only be
     *         withdrawn to the current superAdmin address, regardless of which
     *         address the superAdmin was set to when it was staked.
     *
     * @param _superAdmin                The new superAdmin address.
     * @param isSet                 Whether to enable or disable the superAdmin address.
     */
    function setBoostAdmin(address _superAdmin, bool isSet) external override onlyOwner {
        require(_superAdmin != address(0), "Invalid superAdmin");

        superAdmins[_superAdmin] = isSet;
    }

    /**
     * @notice Change the designated super admin, who manage the fee reverse
     *
     * @param _superAdmin                The new superAdmin address.
     * @param isSet                 Whether to enable or disable the super admin address.
     */
    function setSuperAdmin(address _superAdmin, bool isSet) external onlyOwner {
        require(_superAdmin != address(0), "Invalid address");
        superAdmins[_superAdmin] = isSet;
    }


    /**
     * @notice Approve treasures and legions for withdrawal from the atlas mine.
     *         Called on startup, and should be called again in case contract
     *         addresses for treasures and legions ever change.
     *
     */
    function approveNFTs() public override onlyOwner {
        address treasureAddr = mine.treasure();
        IERC1155Upgradeable(treasureAddr).setApprovalForAll(address(mine), true);

        address legionAddr = mine.legion();
        IERC1155Upgradeable(legionAddr).setApprovalForAll(address(mine), true);
    }


    /**
     * @notice EMERGENCY ONLY - toggle pausing new scheduled stakes.
     *         If on, vaults can deposit, but stakes won't go to Atlas Mine.
     *         Can be used in case of Atlas Mine issues or forced migration
     *         to new contract.
     */
    function toggleSchedulePause(bool paused) external virtual override onlyOwner {
        schedulePaused = paused;

        emit StakingPauseToggle(paused);
    }

    
    // ======================================== VIEW FUNCTIONS =========================================
    function getLockBoost(IAtlasMine.Lock _lock) public pure virtual returns (uint256 boost, uint256 timelock) {
        if (_lock == IAtlasMine.Lock.twoWeeks) {
            // 10%
            return (10e16, 14 days);
        } else if (_lock == IAtlasMine.Lock.oneMonth) {
            // 25%
            return (25e16, 30 days);
        } else if (_lock == IAtlasMine.Lock.threeMonths) {
            // 80%
            return (80e16, 3 * 30 days);
        } else if (_lock == IAtlasMine.Lock.sixMonths) {
            // 180%
            return (180e16, 6 * 30 days);
        } else if (_lock == IAtlasMine.Lock.twelveMonths) {
            // 400%
            return (400e16, 365 days);
        } else {
            revert("Invalid lock value");
        }
    }
    /**
     * @notice Returns all magic either unstaked, staked, or pending rewards in Atlas Mine.
     *         Best proxy for TVL.
     *
     * @return total               The total amount of MAGIC in the staker.
     */
    function totalMagic() external view override returns (uint256) {
        return _totalControlledMagic() + mine.pendingRewardsAll(address(this));
    }

    /**
     * @notice Returns all magic that has been deposited, but not staked, and is eligible
     *         to be staked (deposit time < current day).
     *
     * @return total               The total amount of MAGIC available to stake.
     */
    // removed, will read the unstakedDeposits directly
    // function totalPendingStake() external view override returns (uint256) {
    //     return unstakedDeposits;
    // }

    /**
     * @notice Returns all magic that has been deposited, but not staked, and is eligible
     *         to be staked (deposit time < current day).
     *
     * @return total               The total amount of MAGIC that can be withdrawn.
     */
    function totalWithdrawableMagic() external view override returns (uint256) {
        uint256 totalPendingRewards;

        // IAtlasMine attempts to divide by 0 if there are no deposits
        try mine.pendingRewardsAll(address(this)) returns (uint256 _pending) {
            totalPendingRewards = _pending;
        } catch Panic(uint256) {
            totalPendingRewards = 0;
        }

        // uint256 vestedPrincipal;
        // for (uint256 i = 0; i < stakes.length; i++) {
        //     vestedPrincipal += mine.calcualteVestedPrincipal(address(this), stakes[i].depositId);
        // }

        return _totalUsableMagic() + totalPendingRewards ;

    }

    /**
     * @notice Returns the details of a vault stake.
     *
     * @return vaultStake           The details of a vault stake.
     */
    function getVaultStake(address vault, uint256 depositId) external view override returns (VaultStake memory) {
        return vaultStake[vault][depositId];
    }

    /**
     * @notice Returns the total amount staked by a vault.
     *
     * @return totalStake           The total amount of MAGIC staked by a vault.
     */
    // we will read it from the subgraph
    // function vaultTotalStake(address vault) external view override returns (uint256 totalStake) {
    //     uint256[] memory depositIds = allVaultDepositIds[vault].values();
    //     for (uint256 i = 0; i < depositIds.length; i++) {
    //         VaultStake storage s = vaultStake[vault][depositIds[i]];
    //         totalStake += s.amount;
    //     }
    // }

    /**
     * @notice Returns the pending, claimable rewards for a deposit.
     * @dev    This does not update rewards, so out of date if rewards not recently updated.
     *         Needed to maintain 'view' function type.
     *
     * @param vault              The vault to check rewards for.
     * @param depositId         The specific deposit to check rewards for.
     *
     * @return reward           The total amount of MAGIC reward pending.
     */
    function pendingRewards(address vault, uint256 depositId) public view override returns (uint256 reward) {
        if(totalShare == 0) {
            return 0;
        }
        VaultStake storage s = vaultStake[vault][depositId];
        (uint256 boost,) =  getLockBoost(s.lock);
        uint256 share = s.amount * (100e16 + boost)/100e16;

        uint256 unupdatedReward =  mine.pendingRewardsAll(address(this));
        (uint256 founderReward, , uint256 feeRefund ) = _calculateHarvestRewardFee(unupdatedReward);
        uint256 realAccRewardsPerShare = accRewardsPerShare + (founderReward * ONE) / totalShare;
        uint256 accumulatedRewards = (share * realAccRewardsPerShare ) / ONE;
        if(whitelistedFeeVaults.contains(vault) && totalWhitelistedFeeShare > 0) {
            uint256 realAccRefundedFeePerShare = accRefundedFeePerShare + (feeRefund * ONE) / totalWhitelistedFeeShare;
            uint256 accumulatedRefundedFee = (share * realAccRefundedFeePerShare) / ONE;
            accumulatedRewards = accumulatedRewards + accumulatedRefundedFee  ;
            accumulatedRewards -= refundedFeeDebts[vault][depositId].toUint256();
        }
        reward = accumulatedRewards - s.rewardDebt.toUint256();
    }

    /**
     * @notice Returns the pending, claimable rewards for all of a vault's deposits.
     * @dev    This does not update rewards, so out of date if rewards not recently updated.
     *         Needed to maintain 'view' function type.
     *
     * @param vault              The vault to check rewards for.
     *
     * @return reward           The total amount of MAGIC reward pending.
     */
    function pendingRewardsAll(address vault) external view override returns (uint256 reward) {
        uint256[] memory depositIds = allVaultDepositIds[vault].values();

        for (uint256 i = 0; i < depositIds.length; i++) {
            reward += pendingRewards(vault, depositIds[i]);
        }
    }

    /**
     * @notice Returns the total Share of a vault.
     *
     * @param vault              The vault to check rewards for.
     *
     * @return _totalShare           The total share of a vault.
     */
    function totalShareOf(address vault) public view returns (uint256 _totalShare) {
        uint256[] memory depositIds = allVaultDepositIds[vault].values();
        for (uint256 i = 0; i < depositIds.length; i++) {
            (uint256 boost ,) =  getLockBoost(vaultStake[vault][depositIds[i]].lock);
            uint256 share = vaultStake[vault][depositIds[i]].amount * (100e16 + boost)/100e16;
            _totalShare += share;
        }
    }
    // ============================================ HELPERS ============================================

    /**
     * @dev Stake tokens held by staker in the Atlas Mine, according to
     *      the predefined lock value. Schedules for staking will be managed by a queue.
     *
     * @param _amount               Number of tokens to stake
     */
    function _stakeInMine(uint256 _amount, IAtlasMine.Lock lock) internal {
        require(_amount <= _totalUsableMagic(), "Not enough funds");

        uint256 depositId = ++lastDepositId;
        (,uint256 lockTime) = getLockBoost(lock);
        uint256 vestingPeriod = mine.getVestingTime(lock);
        uint256 unlockAt = block.timestamp + lockTime + vestingPeriod;

        stakes.push(Stake({ amount: _amount, unlockAt: unlockAt, depositId: depositId }));

        mine.deposit(_amount, lock);
    }

    /**
     * @dev Unstakes until we have enough unstaked tokens to meet a specific target.
     *      Used to make sure we can service withdrawals.
     *
     * @param target                The amount of tokens we want to have unstaked.
     */
    function _unstakeToTarget(uint256 target) internal {
        uint256 unstaked = 0;

        for (uint256 i = 0; i < stakes.length; i++) {
            Stake memory s = stakes[i];

            if (s.unlockAt > block.timestamp && !mine.unlockAll()) {
                // This stake is not unlocked - stop looking
                continue;
            }

            // Withdraw position - auto-harvest
            uint256 preclaimBalance = _totalUsableMagic();
            uint256 targetLeft = target - unstaked;
            uint256 amount = targetLeft > s.amount ? s.amount : targetLeft;

            // Do not harvest rewards - if this is running, we've already
            // harvested in the same fn call
            mine.withdrawPosition(s.depositId, amount);
            uint256 postclaimBalance = _totalUsableMagic();

            // Increment amount unstaked
            unstaked += postclaimBalance - preclaimBalance;

            if (unstaked >= target) {
                // We unstaked enough
                break;
            }
        }

        require(unstaked >= target, "Cannot unstake enough");
        require(_totalUsableMagic() >= target, "Not enough in contract after unstaking");

        // Only check for removal after, so we don't mutate while looping
        _removeZeroStakes();
    }

    /**
     * @dev Harvest rewards from the IAtlasMine and send them back to
     *      this contract.
     *
     * @return earned               The amount of rewards earned for depositors, minus the fee.
     * @return feeEearned           The amount of fees earned for the contract operator.
     */
    function _harvestMine() internal returns (uint256, uint256) {
        uint256 preclaimBalance = magic.balanceOf(address(this));

        try mine.harvestAll() {
            uint256 postclaimBalance = magic.balanceOf(address(this));

            uint256 earned = postclaimBalance - preclaimBalance;
            // Reserve the 'fee' amount of what is earned
            (, uint256 feeEarned, uint256 feeRefunded) = _calculateHarvestRewardFee(earned);
            feeReserve += feeEarned - feeRefunded;
            emit MineHarvest(earned - feeEarned, feeEarned - feeRefunded, feeRefunded);
            return (earned - feeEarned, feeRefunded);
        } catch {
            // Failed because of reward debt calculation - should be 0
            return (0, 0);
        }
    }

    function _calculateHarvestRewardFee(uint256 earned) internal view returns (uint256, uint256, uint256) {
            uint256 feeEarned = (earned * fee) / FEE_DENOMINATOR;
            uint256 accFeePerShare = (feeEarned * ONE)/totalShare; 
            uint256 feeRefunded = accFeePerShare * totalWhitelistedFeeShare/ONE; 
            return (earned - feeEarned, feeEarned, feeRefunded);
    }
    /**
     * @dev Harvest rewards from the mine so that stakers can claim.
     *      Recalculate how many rewards are distributed to each share.
     */
    function _updateRewards() internal {
        if (totalStaked == 0 || totalShare == 0) return;
        (uint256 newRewards, uint256 feeRefunded) = _harvestMine();
        accRewardsPerShare += (newRewards * ONE) / totalShare;
        if(totalWhitelistedFeeShare > 0 ) accRefundedFeePerShare += (feeRefunded * ONE) / totalWhitelistedFeeShare;
    }

    /**
     * @dev After mutating a stake (by withdrawing fully or partially),
     *      get updated data from the staking contract, and update the stake amounts
     *
     * @param stakeIndex           The index of the stake in the Stakes storage array.
     *
     * @return amount              The current, updated amount of the stake.
     */
    function _updateStakeDepositAmount(uint256 stakeIndex) internal returns (uint256) {
        Stake storage s = stakes[stakeIndex];

        (, uint256 depositAmount, , , , , ) = mine.userInfo(address(this), s.depositId);
        s.amount = depositAmount;

        return s.amount;
    }

    /**
     * @dev Find stakes with zero deposit amount and remove them from tracking.
     *      Uses recursion to stop from mutating an array we are currently looping over.
     *      If a zero stake is found, it is removed, and the function is restarted,
     *      such that it is always working from a 'clean' array.
     *
     */
    function _removeZeroStakes() internal {
        bool shouldRecurse = stakes.length > 0;

        for (uint256 i = 0; i < stakes.length; i++) {
            _updateStakeDepositAmount(i);

            Stake storage s = stakes[i];

            if (s.amount == 0) {
                _removeStake(i);
                // Stop looping and start again - we will skip
                // out of the look and recurse
                break;
            }

            if (i == stakes.length - 1) {
                // We didn't remove anything, so stop recursing
                shouldRecurse = false;
            }
        }

        if (shouldRecurse) {
            _removeZeroStakes();
        }
    }

    /**
     * @dev Calculate total amount of MAGIC usable by the contract.
     *      'Usable' means available for either withdrawal or re-staking.
     *      Counts unstaked magic less fee reserve.
     *
     * @return amount               The amount of usable MAGIC.
     */
    function _totalUsableMagic() internal view returns (uint256) {
        // Current magic held in contract
        uint256 unstaked = magic.balanceOf(address(this));

        return unstaked - tokenBuffer - feeReserve;
    }

    /**
     * @dev Calculate total amount of MAGIC under control of the contract.
     *      Counts staked and unstaked MAGIC. Does _not_ count accumulated
     *      but unclaimed rewards.
     *
     * @return amount               The total amount of MAGIC under control of the contract.
     */
    function _totalControlledMagic() internal view returns (uint256) {
        // Current magic staked in mine
        uint256 staked = 0;

        for (uint256 i = 0; i < stakes.length; i++) {
            staked += stakes[i].amount;
        }

        return staked + _totalUsableMagic();
    }

    /**
     * @dev Remove a tracked stake from any position in the stakes array.
     *      Used when a stake is no longer relevant i.e. fully withdrawn.
     *      Mutates the Stakes array in storage.
     *
     * @param index                 The index of the stake to remove.
     */
    function _removeStake(uint256 index) internal {
        if (index >= stakes.length) return;

        for (uint256 i = index; i < stakes.length - 1; i++) {
            stakes[i] = stakes[i + 1];
        }

        delete stakes[stakes.length - 1];

        stakes.pop();
    }

    modifier onlySuperAdmin() {
        require(msg.sender == owner() ||superAdmins[msg.sender], "Not Super Admin");
        _;
    }
    modifier onlyBattleflyVault() {
        require(msg.sender == owner() || battleflyVaults[msg.sender], "Not BattleflyVault");
        _;
    }
}
contract BattleflyFlywheelVault is
    IBattleflyVault,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ============================================ STATE ==============================================
    struct UserStake {
        uint256 amount;
        uint256 unlockAt;
        uint256 withdrawAt;
        IAtlasMine.Lock lock;
        uint256 battleflyStakerDepositId;
        address owner;
    }
    // ============= Global Immutable State ==============
    IERC20Upgradeable public magic;
    IBattleflyAtlasStaker public BattleflyStaker;
    // ============= Global Staking State ==============
    IAtlasMine.Lock[] public allowedLocks;
    mapping(uint256 => UserStake) public userStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakesOfOwner;
    uint256 nextStakeId;
    uint256 public totalStaked;
    uint256 public totalFee;
    uint256 public totalFeeWithdrawn;
    uint256 public FEE;
    uint256 public FEE_DENOMINATOR;
    // ============= Global Admin ==============
    mapping(address => bool) private adminAccess;

    address public constant TREASURY_WALLET = 0xF5411006eEfD66c213d2fd2033a1d340458B7226;
    IBattleflyFounderVault public founderVaultV1;
    IBattleflyFounderVault public founderVaultV2;
    uint256 public stakeableAmountPerV1;
    uint256 public stakeableAmountPerV2;
    // ============================================ EVENT ==============================================
    event Claim(address indexed user, uint256 stakeId, uint256 amount, uint256 fee);
    event Stake(address indexed user, uint256 stakeId, uint256 amount, IAtlasMine.Lock lock);
    event Withdraw(address indexed user, uint256 stakeId, uint256 amount);
    event SetFee(uint256 oldFee, uint256 newFee, uint256 denominator);
    event WithdrawFee(address receiver, uint256 amount);
    
    event SetAdminAccess(address indexed user, bool access);
    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _magicAddress,
        address _BattleflyStakerAddress,
        uint256 _fee,
        uint256 _feeDominator,
        IAtlasMine.Lock[] memory _allowedLocks,
        address _founderVaultV1Address,
        address _founderVaultV2Address,
        uint256 _stakeableAmountPerV1,
        uint256 _stakeableAmountPerV2
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        nextStakeId = 0;
        FEE = _fee;
        FEE_DENOMINATOR = _feeDominator;
        allowedLocks = _allowedLocks;
        founderVaultV1 = IBattleflyFounderVault(_founderVaultV1Address);
        founderVaultV2 = IBattleflyFounderVault(_founderVaultV2Address);
        stakeableAmountPerV1 = _stakeableAmountPerV1;
        stakeableAmountPerV2 = _stakeableAmountPerV2;
        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }
    // ============================================ USER FUNCTIONS ==============================================
    function stake(uint256 amount, IAtlasMine.Lock lock) external {
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _stake(amount, lock);
    }
    function _stake(uint256 amount, IAtlasMine.Lock lock) internal returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        bool validLock = false;
        for(uint256 i = 0; i < allowedLocks.length; i++) {
            if(allowedLocks[i] == lock) validLock = true;
        }
        require(validLock, "Lock time not allowed");
        uint256 battleflyStakerDepositId = BattleflyStaker.deposit(amount, lock);
        IBattleflyAtlasStaker.VaultStake memory vaultStake = BattleflyStaker.getVaultStake(address(this), battleflyStakerDepositId);
        UserStake storage s = userStakes[nextStakeId];
        s.amount = amount;
        s.unlockAt = vaultStake.unlockAt;
        s.lock = lock;
        s.battleflyStakerDepositId = battleflyStakerDepositId;
        s.owner = msg.sender;
        stakesOfOwner[msg.sender].add(nextStakeId);
        emit Stake(msg.sender, nextStakeId, amount, lock);
        nextStakeId++;
        totalStaked+= amount;
        return nextStakeId - 1;
    }
    function getStakeAmount(address user) public view returns(uint256, uint256) {
        uint256 totalStakingV1;
        uint256 totalStakingV2;
        IBattleflyFounderVault.FounderStake[] memory v1Stakes =  founderVaultV1.stakesOf(user);
        IBattleflyFounderVault.FounderStake[] memory v2Stakes =  founderVaultV2.stakesOf(user);
        for(uint256 i = 0; i < v1Stakes.length; i++) {
            totalStakingV1 += v1Stakes[i].amount;
        }
        for(uint256 i = 0; i < v2Stakes.length; i++) {
            totalStakingV2 += v2Stakes[i].amount;
        }
        uint256 totalUserStaking = 0;
        for(uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            totalUserStaking += userStakes[stakeId].amount;
        }
        uint256 stakedAmount = totalStakingV1 * stakeableAmountPerV1 + totalStakingV2 * stakeableAmountPerV2;
        return (stakedAmount, totalUserStaking);
    }
    function claimAll() public nonReentrant {
      uint256 totalReward = 0;
      for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
          uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if(_getStakeClaimableAmount(stakeId) > 0) {
               totalReward += _claim(stakeId);
            }
      }
      require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }
    function claimAllAndRestake(IAtlasMine.Lock lock) external {
        uint256 totalReward = 0;
        for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
                if(_getStakeClaimableAmount(stakeId) > 0) {
                totalReward += _claim(stakeId);
                }
        }
        require(totalReward > 0, "No rewards to claim");
        _stake(totalReward, lock);
    }
    function claim(uint256[] memory stakeIds) external nonReentrant {
        uint256 totalReward = 0;
        for(uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can claim");
            if(_getStakeClaimableAmount(stakeIds[i]) > 0) {
               totalReward += _claim(stakeIds[i]);
            }
        }
        require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }
    function _claim(uint256 stakeId) internal returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimedAmount = BattleflyStaker.claim(s.battleflyStakerDepositId);
        uint256 fee = claimedAmount * FEE / FEE_DENOMINATOR;
        uint256 userClaimAmount = claimedAmount - fee;
        totalFee+= fee;
        emit Claim(s.owner, stakeId, userClaimAmount, fee);
        return userClaimAmount;
    }
    function _getStakeClaimableAmount(uint256 stakeId) internal view returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimAmount = BattleflyStaker.pendingRewards(address(this), s.battleflyStakerDepositId);
        uint256 fee = claimAmount * FEE / FEE_DENOMINATOR;
        uint256 userClaimAmount = claimAmount - fee;
        return userClaimAmount;
    }
    function getUserClaimableAmount(address user) external view returns (uint256) {
        uint256 total = 0;
        for(uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            total += _getStakeClaimableAmount(stakeId);
        }
        return total;
    }
    function getUserStakes(address user) external view returns (UserStake[] memory) {
        UserStake[] memory stakes = new UserStake[](stakesOfOwner[user].length());
        for(uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            stakes[i] = userStakes[stakeId];
        }
        return stakes;
    }
    function withdrawAll() external nonReentrant {
        require(stakesOfOwner[msg.sender].length() > 0, "No stakes to withdraw");
        uint256 receiveAmount;
        for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if(userStakes[stakeId].unlockAt < block.timestamp) {
                receiveAmount += _withdraw(stakeId);
            }
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }
    function withdraw(uint256[] memory stakeIds) external nonReentrant {
        uint256 receiveAmount;
        for(uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can withdraw");
            receiveAmount += _withdraw(stakeIds[i]);
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }
    function _withdraw(uint256 stakeId) internal returns (uint256){
        UserStake storage s = userStakes[stakeId];
        uint256 rewardAmount;
        require(s.unlockAt < block.timestamp, "Cannot withdraw before the lock time");
        uint256 claimableAmount = _getStakeClaimableAmount(stakeId);
        if(claimableAmount > 0) {
            rewardAmount = _claim(stakeId);
        }
        BattleflyStaker.withdraw(s.battleflyStakerDepositId);
        totalStaked-= s.amount;
        stakesOfOwner[msg.sender].remove(stakeId);
        s.withdrawAt = block.timestamp;
        emit Withdraw(msg.sender, stakeId, s.amount);
        return s.amount + rewardAmount;
    }
    function stakeableAmountPerFounder(address vault) external view returns (uint256) {
        if(vault == address(founderVaultV1)) {
            return stakeableAmountPerV1;
        }
        if(vault == address(founderVaultV2)) {
            return stakeableAmountPerV2;
        }
        return 0;
    }
    // ============================================ ADMIN FUNCTIONS ==============================================
    function setFee(uint256 _fee) external onlyAdminAccess {
        require(_fee < FEE_DENOMINATOR, "Fee must be less than the fee dominator");
        emit SetFee(FEE, _fee, FEE_DENOMINATOR);
        FEE = _fee;
    }
    function setAllowedLock(IAtlasMine.Lock[] memory _allowedLocks) external onlyAdminAccess {
        allowedLocks = _allowedLocks;
    }
    function withdrawFeeToTreausy() external onlyAdminAccess {
        uint256 amount = totalFee - totalFeeWithdrawn;
        require(amount > 0, "No fee to withdraw");
        totalFeeWithdrawn += amount;
        magic.safeTransfer(TREASURY_WALLET, amount);
        emit WithdrawFee(TREASURY_WALLET, amount);
    }
    // ============================================ OWNER FUNCTIONS ==============================================
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }
    // ============================================ MODIFIER ==============================================
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}
contract BattleflyVault is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    // ============================================ STATE ==============================================
    struct UserStake {
        uint256 amount;
        uint256 unlockAt;
        uint256 withdrawAt;
        IAtlasMine.Lock lock;
        uint256 battleflyStakerDepositId;
        address owner;
    }
    // ============= Global Immutable State ==============
    IERC20Upgradeable public magic;
    IBattleflyAtlasStaker public BattleflyStaker;
    // ============= Global Staking State ==============
    IAtlasMine.Lock[] public allowedLocks;
    mapping(uint256 => UserStake) public userStakes;
    mapping(address => EnumerableSetUpgradeable.UintSet) private stakesOfOwner;
    uint256 nextStakeId;
    uint256 public totalStaked;

    // ============= Global Admin ==============
    mapping(address => bool) private adminAccess;
    // ============================================ EVENT ==============================================
    event Claim(address indexed user, uint256 stakeId, uint256 amount);
    event Stake(address indexed user, uint256 stakeId, uint256 amount, IAtlasMine.Lock lock);
    event Withdraw(address indexed user, uint256 stakeId, uint256 amount);
    event SetFee(uint256 oldFee, uint256 newFee, uint256 denominator);
    event WithdrawFee(address receiver, uint256 amount);
    
    event SetAdminAccess(address indexed user, bool access);
    // ============================================ INITIALIZE ==============================================
    function initialize(
        address _magicAddress,
        address _BattleflyStakerAddress,
        IAtlasMine.Lock[] memory _allowedLocks
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        magic = IERC20Upgradeable(_magicAddress);
        BattleflyStaker = IBattleflyAtlasStaker(_BattleflyStakerAddress);
        nextStakeId = 0;
        allowedLocks = _allowedLocks;
        // Approve the AtlasStaker contract to spend the magic
        magic.safeApprove(address(BattleflyStaker), 2**256 - 1);
    }
    // ============================================ USER FUNCTIONS ==============================================
    function stake(uint256 amount, IAtlasMine.Lock lock) external {
        magic.safeTransferFrom(msg.sender, address(this), amount);
        _stake(amount, lock);
    }
    function _stake(uint256 amount, IAtlasMine.Lock lock) internal returns (uint256) {
        require(amount > 0, "Amount must be greater than 0");
        bool validLock = false;
        for(uint256 i = 0; i < allowedLocks.length; i++) {
            if(allowedLocks[i] == lock) validLock = true;
        }
        require(validLock, "Lock time not allowed");
        uint256 battleflyStakerDepositId = BattleflyStaker.deposit(amount, lock);
        IBattleflyAtlasStaker.VaultStake memory vaultStake = BattleflyStaker.getVaultStake(address(this), battleflyStakerDepositId);
        UserStake storage s = userStakes[nextStakeId];
        s.amount = amount;
        s.unlockAt = vaultStake.unlockAt;
        s.lock = lock;
        s.battleflyStakerDepositId = battleflyStakerDepositId;
        s.owner = msg.sender;
        stakesOfOwner[msg.sender].add(nextStakeId);
        emit Stake(msg.sender, nextStakeId, amount, lock);
        nextStakeId++;
        totalStaked+= amount;
        return nextStakeId - 1;
    }
    function claimAll() public nonReentrant {
      uint256 totalReward = 0;
      for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
          uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if(_getStakeClaimableAmount(stakeId) > 0) {
               totalReward += _claim(stakeId);
            }
      }
      require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }
    function claimAllAndRestake(IAtlasMine.Lock lock) external {
        uint256 totalReward = 0;
        for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
                if(_getStakeClaimableAmount(stakeId) > 0) {
                totalReward += _claim(stakeId);
                }
        }
        require(totalReward > 0, "No rewards to claim");
        _stake(totalReward, lock);
    }
    function claim(uint256[] memory stakeIds) external nonReentrant {
        uint256 totalReward = 0;
        for(uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can claim");
            if(_getStakeClaimableAmount(stakeIds[i]) > 0) {
               totalReward += _claim(stakeIds[i]);
            }
        }
        require(totalReward > 0, "No rewards to claim");
        magic.safeTransfer(msg.sender, totalReward);
    }
    function _claim(uint256 stakeId) internal returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimedAmount = BattleflyStaker.claim(s.battleflyStakerDepositId);
        emit Claim(s.owner, stakeId, claimedAmount);
        return claimedAmount;
    }
    function _getStakeClaimableAmount(uint256 stakeId) internal view returns (uint256) {
        UserStake memory s = userStakes[stakeId];
        uint256 claimAmount = BattleflyStaker.pendingRewards(address(this), s.battleflyStakerDepositId);
        return claimAmount;
    }
    function getUserClaimableAmount(address user) external view returns (uint256) {
        uint256 total = 0;
        for(uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            total += _getStakeClaimableAmount(stakeId);
        }
        return total;
    }
    function getUserStakes(address user) external view returns (UserStake[] memory) {
        UserStake[] memory stakes = new UserStake[](stakesOfOwner[user].length());
        for(uint256 i = 0; i < stakesOfOwner[user].length(); i++) {
            uint256 stakeId = stakesOfOwner[user].at(i);
            stakes[i] = userStakes[stakeId];
        }
        return stakes;
    }
    function withdrawAll() external nonReentrant {
        require(stakesOfOwner[msg.sender].length() > 0, "No stakes to withdraw");
        uint256 receiveAmount;
        for(uint256 i = 0; i < stakesOfOwner[msg.sender].length(); i++) {
            uint256 stakeId = stakesOfOwner[msg.sender].at(i);
            if(userStakes[stakeId].unlockAt < block.timestamp) {
                receiveAmount += _withdraw(stakeId);
            }
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }
    function withdraw(uint256[] memory stakeIds) external nonReentrant {
        uint256 receiveAmount;
        for(uint256 i = 0; i < stakeIds.length; i++) {
            UserStake storage s = userStakes[stakeIds[i]];
            require(s.owner == msg.sender, "Only the owner can withdraw");
            receiveAmount += _withdraw(stakeIds[i]);
        }
        require(receiveAmount > 0, "No stakes to withdraw");
        magic.safeTransfer(msg.sender, receiveAmount);
    }
    function _withdraw(uint256 stakeId) internal returns (uint256){
        UserStake storage s = userStakes[stakeId];
        uint256 rewardAmount;
        require(s.unlockAt < block.timestamp, "Cannot withdraw before the lock time");
        uint256 claimableAmount = _getStakeClaimableAmount(stakeId);
        if(claimableAmount > 0) {
            rewardAmount = _claim(stakeId);
        }
        BattleflyStaker.withdraw(s.battleflyStakerDepositId);
        totalStaked-= s.amount;
        stakesOfOwner[msg.sender].remove(stakeId);
        s.withdrawAt = block.timestamp;
        emit Withdraw(msg.sender, stakeId, s.amount);
        return s.amount + rewardAmount;
    }
    // ============================================ ADMIN FUNCTIONS ==============================================

    function setAllowedLock(IAtlasMine.Lock[] memory _allowedLocks) external onlyAdminAccess {
        allowedLocks = _allowedLocks;
    }

    // ============================================ OWNER FUNCTIONS ==============================================
    function setAdminAccess(address user, bool access) external onlyOwner {
        adminAccess[user] = access;
        emit SetAdminAccess(user, access);
    }
    // ============================================ MODIFIER ==============================================
    modifier onlyAdminAccess() {
        require(adminAccess[_msgSender()] == true || _msgSender() == owner(), "Require admin access");
        _;
    }
}