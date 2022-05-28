// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { TokenPreTimelock } from "./TokenPreTimelock.sol";
import { TokenPreVesting } from "./TokenPreVesting.sol";

/**
 * @title TokenPreSale Contract
 */

contract TokenPreSale is Ownable {
    using SafeMath for uint256;

    IERC20 public token; // the token being sold

    uint256 public coinsSold;

    event Sold(address buyer, uint256 amount);

    uint256 public exchangePriceUSDT = 120000000000000000;
    uint256 public exchangePriceBUSD = 120000000000000000;
    uint256 public duration = 18 * 30 days;
    uint256 public cliff = 3 * 30 days;
    uint256 public minBuyAmountUSDT = 1000000000000000000;
    uint256 public maxBuyAmountUSDT = 10000000000000000000000;
    uint256 public minBuyAmountBUSD = 1000000000000000000;
    uint256 public maxBuyAmountBUSD = 10000000000000000000000;
    TokenPreVesting public vesting;
    TokenPreTimelock public timelock;

    uint256 public availableAtTGE = 200; // percentage basis points

    enum SaleStatus {
        Pause,
        Start
    }

    SaleStatus public saleStatus;
    address public immutable USDT;
    address public immutable BUSD;

    constructor(
        IERC20 _token,
        address _usdt,
        address _busd
    ) {
        token = _token;
        USDT = _usdt;
        BUSD = _busd;
        vesting = new TokenPreVesting(address(token));
        timelock = new TokenPreTimelock(address(token));
    }

    modifier onSale() {
        require(saleStatus == SaleStatus.Start, "TokenPreSale: Sale not started");
        _;
    }

    function setExchangePriceUSDT(uint256 _usdtPrice) external onlyOwner {
        exchangePriceUSDT = _usdtPrice;
    }

    function setExchangePriceBUSD(uint256 _busdPrice) external onlyOwner {
        exchangePriceBUSD = _busdPrice;
    }

    function setDuration(uint256 _duration) external onlyOwner {
        duration = _duration;
    }

    function setCliff(uint256 _cliff) external onlyOwner {
        cliff = _cliff;
    }

    function setTimeStamp(uint256 _timePeriodInSeconds) external onlyOwner {
        vesting.setTimestamp(_timePeriodInSeconds);
        timelock.setTimestamp(_timePeriodInSeconds);
    }

    function setSaleStatus(SaleStatus _saleStatus) external onlyOwner {
        saleStatus = _saleStatus;
    }

    function setAvailableAtTGE(uint256 _availableAtTGE) external onlyOwner {
        availableAtTGE = _availableAtTGE;
    }

    function transferAccidentallyLockedTokensInTimeLock(IERC20 _token, uint256 _amount) external onlyOwner {
        timelock.transferAccidentallyLockedTokens(_token, _amount);
        _token.transfer(owner(), _amount);
    }

    function setBuyAmountRangeBUSD(uint256 _min, uint256 _max) external onlyOwner {
        minBuyAmountBUSD = _min;
        maxBuyAmountBUSD = _max;
    }

    function setBuyAmountRangeUSDT(uint256 _min, uint256 _max) external onlyOwner {
        minBuyAmountUSDT = _min;
        maxBuyAmountUSDT = _max;
    }

    function buyTokensUsingBUSD(uint256 _busdAmount) external onSale {
        uint256 _balanceBefore = IERC20(BUSD).balanceOf(address(this));
        require(IERC20(BUSD).transferFrom(msg.sender, address(this), _busdAmount), "TokenPreSale: BUSD -> this");
        uint256 _balanceAfter = IERC20(BUSD).balanceOf(address(this));
        uint256 _actualBUSDAmount = _balanceAfter.sub(_balanceBefore);
        require(
            _actualBUSDAmount >= minBuyAmountBUSD && _actualBUSDAmount <= maxBuyAmountBUSD,
            "TokenPreSale: BUSD out of range"
        );
        uint256 _numberOfTokens = computeTokensForBUSD(_actualBUSDAmount);
        require(
            token.allowance(owner(), address(this)) >= _numberOfTokens,
            "TokenPreSale: insufficient token approval"
        );
        emit Sold(msg.sender, _numberOfTokens);
        coinsSold += _numberOfTokens;
        uint256 _nonVestedTokenAmount = _numberOfTokens.mul(availableAtTGE).div(10000);
        uint256 _vestedTokenAmount = _numberOfTokens.sub(_nonVestedTokenAmount);
        // send some pct of tokens to buyer right away
        if (_nonVestedTokenAmount > 0) {
            require(
                token.transferFrom(owner(), address(timelock), _nonVestedTokenAmount),
                "TokenPreSale: token -> tokenpretimelock"
            );
            timelock.depositTokens(msg.sender, _nonVestedTokenAmount);
        } // vest rest of the tokens
        require(
            token.transferFrom(owner(), address(vesting), _vestedTokenAmount),
            "TokenPreSale: token -> tokenprevesting"
        );
        vesting.createVestingSchedule(msg.sender, cliff, duration, 1, false, _vestedTokenAmount, availableAtTGE);
    }

    function buyTokensUsingUSDT(uint256 _usdtAmount) external onSale {
        uint256 _balanceBefore = IERC20(USDT).balanceOf(address(this));
        require(IERC20(USDT).transferFrom(msg.sender, address(this), _usdtAmount), "TokenPreSale: USDT -> this");
        uint256 _balanceAfter = IERC20(USDT).balanceOf(address(this));
        uint256 _actualUSDTAmount = _balanceAfter.sub(_balanceBefore);
        require(
            _actualUSDTAmount >= minBuyAmountUSDT && _actualUSDTAmount <= maxBuyAmountUSDT,
            "TokenPreSale: USDT out of range"
        );
        uint256 _numberOfTokens = computeTokensForUSDT(_actualUSDTAmount);
        require(
            token.allowance(owner(), address(this)) >= _numberOfTokens,
            "TokenPreSale: insufficient token approval"
        );
        emit Sold(msg.sender, _numberOfTokens);
        coinsSold += _numberOfTokens;
        uint256 _nonVestedTokenAmount = _numberOfTokens.mul(availableAtTGE).div(10000);
        uint256 _vestedTokenAmount = _numberOfTokens.sub(_nonVestedTokenAmount);
        // send some pct of tokens to buyer right away
        if (_nonVestedTokenAmount > 0) {
            require(
                token.transferFrom(owner(), address(timelock), _nonVestedTokenAmount),
                "TokenPreSale: token -> tokenpretimelock"
            );
            timelock.depositTokens(msg.sender, _nonVestedTokenAmount);
        } // vest rest of the tokens
        require(
            token.transferFrom(owner(), address(vesting), _vestedTokenAmount),
            "TokenPreSale: token -> tokenprevesting"
        );

        vesting.createVestingSchedule(msg.sender, cliff, duration, 1, false, _vestedTokenAmount, availableAtTGE);
    }

    function computeTokensForBUSD(uint256 _busdAmount) public view returns (uint256) {
        uint256 _tokenDecimals = ERC20(address(token)).decimals();
        return (_busdAmount * 10**_tokenDecimals) / exchangePriceBUSD;
    }

    function computeTokensForUSDT(uint256 _usdtAmount) public view returns (uint256) {
        uint256 _tokenDecimals = ERC20(address(token)).decimals();
        return (_usdtAmount * 10**_tokenDecimals) / exchangePriceUSDT;
    }

    function withdrawBUSD() public onlyOwner {
        uint256 _busdBalance = IERC20(BUSD).balanceOf(address(this));
        if (_busdBalance > 0) {
            IERC20(BUSD).transfer(owner(), _busdBalance);
        }
    }

    function withdrawUSDT() public onlyOwner {
        uint256 _usdtBalance = IERC20(USDT).balanceOf(address(this));
        if (_usdtBalance > 0) {
            IERC20(USDT).transfer(owner(), _usdtBalance);
        }
    }

    function withdrawFromVesting(uint256 _amount) public onlyOwner {
        vesting.withdraw(_amount);
        token.transfer(owner(), _amount);
    }

    function transferAccidentallyLockedTokensFromTimelock(IERC20 _token, uint256 amount) public onlyOwner {
        timelock.transferAccidentallyLockedTokens(_token, amount);
        _token.transfer(owner(), _token.balanceOf(address(this)));
    }

    function revoke(bytes32 vestingScheduleId) external onlyOwner {
        vesting.revoke(vestingScheduleId);
    }

    function endSale() external onlyOwner {
        // Send unsold tokens to owner.
        saleStatus = SaleStatus.Pause;
        uint256 _withdrawableAmount = vesting.getWithdrawableAmount();
        if (_withdrawableAmount > 0) {
            withdrawFromVesting(vesting.getWithdrawableAmount());
        }
        withdrawBUSD();
        withdrawUSDT();
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title Token vesting Contract
 */
contract TokenPreVesting is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    struct VestingSchedule {
        bool initialized;
        // beneficiary of tokens after they are released
        address beneficiary;
        // cliff period in seconds
        uint256 cliff;
        // duration of the vesting period in seconds
        uint256 duration;
        // duration of a slice period for the vesting in seconds
        uint256 slicePeriodSeconds;
        // whether or not the vesting is revocable
        bool revocable;
        // total amount of tokens to be released at the end of the vesting
        uint256 amountTotal;
        // amount of tokens released
        uint256 released;
        // whether or not the vesting has been revoked
        bool revoked;
        // tge tokens in percentage basis points
        uint256 tge;
    }

    // Contract owner access
    bool public allIncomingDepositsFinalised;

    // Timestamp related variables
    bool public timestampSet;
    uint256 public initialTimestamp;
    uint256 public start;

    bytes32[] private vestingSchedulesIds;
    uint256 private vestingSchedulesTotalAmount;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    mapping(address => uint256) private holdersVestingCount;

    IERC20 private immutable _token;

    event Released(uint256 amount);
    event Revoked();
    event VestingScheduleCreated(address beneficiary, bytes32 vestingScheduleId);

    /**
     * @dev Throws if allIncomingDepositsFinalised is true.
     */
    modifier incomingDepositsStillAllowed() {
        require(allIncomingDepositsFinalised == false, "TokenPreVesting: Incoming deposits have been finalised.");
        _;
    }

    /**
     * @dev Reverts if no vesting schedule matches the passed identifier.
     */
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        require(
            vestingSchedules[vestingScheduleId].initialized == true,
            "TokenPreVesting: vesting schedule does not exist for this user"
        );
        _;
    }

    modifier onlyIfLaunchTimestampNotSet() {
        require(timestampSet == false, "TokenPreVesting: launch timestamp is set");
        _;
    }

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(
            vestingSchedules[vestingScheduleId].initialized == true,
            "TokenPreVesting: Vesting schedule does not exists"
        );
        require(vestingSchedules[vestingScheduleId].revoked == false, "TokenPreVesting: Vesting schedule is revoked");
        _;
    }

    /**
     * @dev Creates a vesting contract.
     * @param token_ address of the ERC20 token contract
     */
    constructor(address token_) {
        require(token_ != address(0x0), "TokenPreVesting: token address is zero");
        initialTimestamp = block.timestamp;
        _token = IERC20(token_);
    }

    /**
     * @dev set timestamp and finalize deposits
     * @param _timePeriodInSeconds time period in seconds
     */
    function setTimestamp(uint256 _timePeriodInSeconds) external onlyOwner onlyIfLaunchTimestampNotSet {
        timestampSet = true;
        allIncomingDepositsFinalised = true;
        initialTimestamp = block.timestamp;
        start = initialTimestamp.add(_timePeriodInSeconds);
    }

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return holdersVestingCount[_beneficiary];
    }

    /**
     * @dev Returns the vesting schedule id at the given index.
     * @return the vesting id
     */
    function getVestingIdAtIndex(uint256 index) external view returns (bytes32) {
        require(index < getVestingSchedulesCount(), "TokenPreVesting: index out of bounds");
        return vestingSchedulesIds[index];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(address holder, uint256 index)
        external
        view
        returns (VestingSchedule memory)
    {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return vestingSchedulesTotalAmount;
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiary address of the beneficiary to whom vested tokens are transferred
     * @param _cliff duration in seconds of the cliff in which tokens will begin to vest
     * @param _duration duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocable whether the vesting is revocable or not
     * @param _amount total amount of tokens to be released at the end of the vesting
     * @param _tge tge tokens in percentage basis points
     */
    function createVestingSchedule(
        address _beneficiary,
        uint256 _cliff,
        uint256 _duration,
        uint256 _slicePeriodSeconds,
        bool _revocable,
        uint256 _amount,
        uint256 _tge
    ) public incomingDepositsStillAllowed onlyOwner {
        require(
            this.getWithdrawableAmount() >= _amount,
            "TokenPreVesting: cannot create vesting schedule because not sufficient tokens"
        );
        require(_duration > 0, "TokenPreVesting: duration must be > 0");
        require(_amount > 0, "TokenPreVesting: amount must be > 0");
        require(_slicePeriodSeconds >= 1, "TokenPreVesting: slicePeriodSeconds must be >= 1");
        bytes32 vestingScheduleId = this.computeNextVestingScheduleIdForHolder(_beneficiary);
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            _beneficiary,
            _cliff,
            _duration,
            _slicePeriodSeconds,
            _revocable,
            _amount,
            0,
            false,
            _tge
        );
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.add(_amount);
        vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = holdersVestingCount[_beneficiary];
        holdersVestingCount[_beneficiary] = currentVestingCount.add(1);
        emit VestingScheduleCreated(_beneficiary, vestingScheduleId);
    }

    /**
     * BULK : CREATING VESTING SCHEDULE IN BULK
     * @notice Creates a new vesting schedule for a beneficiary.
     * @param _beneficiaries address of the beneficiary to whom vested tokens are transferred
     * @param _cliffs duration in seconds of the cliff in which tokens will begin to vest
     * @param _durations duration in seconds of the period in which the tokens will vest
     * @param _slicePeriodSeconds duration of a slice period for the vesting in seconds
     * @param _revocables whether the vesting is revocable or not
     * @param _amounts total amount of tokens to be released at the end of the vesting
     * @param _tges list of tges in percentage basis points
     */
    function createVestingSchedule(
        address[] calldata _beneficiaries,
        uint256[] calldata _cliffs,
        uint256[] calldata _durations,
        uint256[] calldata _slicePeriodSeconds,
        bool[] calldata _revocables,
        uint256[] memory _amounts,
        uint256[] memory _tges
    ) external incomingDepositsStillAllowed onlyOwner {
        require(
            _beneficiaries.length == _durations.length &&
                _durations.length == _slicePeriodSeconds.length &&
                _slicePeriodSeconds.length == _revocables.length &&
                _revocables.length == _amounts.length,
            "TokenPreVesting: Length mismatch"
        );

        //looping through beneficiaries
        for (uint256 _i; _i < _beneficiaries.length; _i++) {
            createVestingSchedule(
                _beneficiaries[_i],
                _cliffs[_i],
                _durations[_i],
                _slicePeriodSeconds[_i],
                _revocables[_i],
                _amounts[_i],
                _tges[_i]
            );
        }
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(bytes32 vestingScheduleId) public onlyOwner onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revocable == true, "TokenPreVesting: vesting is not revocable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            release(vestingScheduleId, vestedAmount);
        }
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(unreleased);
        vestingSchedule.revoked = true;
    }

    /**
     * @notice Withdraw the specified amount if possible.
     * @param amount the amount to withdraw
     */
    function withdraw(uint256 amount) public nonReentrant onlyOwner {
        require(this.getWithdrawableAmount() >= amount, "TokenPreVesting: not enough withdrawable funds");
        _token.safeTransfer(owner(), amount);
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     * @param amount the amount to release
     */
    function release(bytes32 vestingScheduleId, uint256 amount)
        public
        nonReentrant
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "TokenPreVesting: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= amount, "TokenPreVesting: cannot release tokens, not enough vested tokens");
        vestingSchedule.released = vestingSchedule.released.add(amount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        vestingSchedulesTotalAmount = vestingSchedulesTotalAmount.sub(amount);
        _token.safeTransfer(beneficiaryPayable, amount);
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() public view returns (uint256) {
        return vestingSchedulesIds.length;
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(bytes32 vestingScheduleId)
        public
        view
        onlyIfVestingScheduleNotRevoked(vestingScheduleId)
        returns (uint256)
    {
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(bytes32 vestingScheduleId) public view returns (VestingSchedule memory) {
        return vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Returns the amount of tokens that can be withdrawn by the owner.
     * @return the amount of tokens
     */
    function getWithdrawableAmount() public view returns (uint256) {
        return _token.balanceOf(address(this)).sub(vestingSchedulesTotalAmount);
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder]);
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(address holder) public view returns (VestingSchedule memory) {
        return vestingSchedules[computeVestingScheduleIdForAddressAndIndex(holder, holdersVestingCount[holder] - 1)];
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        if (!timestampSet) {
            return uint256(0);
        }
        uint256 currentTime = getCurrentTime();
        if ((currentTime < start.add(vestingSchedule.cliff)) || vestingSchedule.revoked == true) {
            return 0;
        } else if (currentTime >= start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = currentTime.sub(start);
            uint256 secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }

    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { SafeMath } from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title TokenPreTimeLock Contract
 */

contract TokenPreTimelock is Ownable {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    // boolean to prevent reentrancy
    bool internal locked;

    // Contract owner access
    bool public allIncomingDepositsFinalised;

    // Timestamp related variables
    bool public timestampSet;
    uint256 public initialTimestamp;
    uint256 public timePeriod;

    // Token amount variables
    mapping(address => uint256) public alreadyWithdrawn;
    mapping(address => uint256) public balances;

    // address of the token
    IERC20 private immutable _token;

    // Events
    event TokensDeposited(address from, uint256 amount);
    event AllocationPerformed(address recipient, uint256 amount);
    event TokensUnlocked(address recipient, uint256 amount);

    constructor(address token_) {
        require(token_ != address(0x0), "TokenPreTimelock: _erc20_contract_address address can not be zero");
        _token = IERC20(token_);
        allIncomingDepositsFinalised = false;
        timestampSet = false;
        locked = false;
    }

    /**
     * @dev Prevents reentrancy
     */
    modifier noReentrant() {
        require(!locked, "TokenPreTimelock: No re-entrancy");
        locked = true;
        _;
        locked = false;
    }

    /**
     * @dev Throws if allIncomingDepositsFinalised is true.
     */
    modifier incomingDepositsStillAllowed() {
        require(allIncomingDepositsFinalised == false, "TokenPreTimelock: Incoming deposits have been finalised.");
        _;
    }

    /**
     * @dev Throws if timestamp already set.
     */
    modifier timestampNotSet() {
        require(timestampSet == false, "TokenPreTimelock: The time stamp has already been set.");
        _;
    }

    /**
     * @dev Throws if timestamp not set.
     */
    modifier timestampIsSet() {
        require(timestampSet == true, "TokenPreTimelock: Please set the time stamp first, then try again.");
        _;
    }

    /**
     * @dev Returns the address of the ERC20 token managed by the vesting contract.
     */
    function getToken() external view returns (address) {
        return address(_token);
    }

    /**
     * @dev Sets the initial timestamp and calculates locking period variables i.e. twelveMonths etc.
     *      setting the time stamp will also finalize deposits
     * @param _timePeriodInSeconds amount of seconds to add to the initial timestamp i.e. we are essemtially creating the lockup period here
     */
    function setTimestamp(uint256 _timePeriodInSeconds) public onlyOwner timestampNotSet {
        timestampSet = true;
        allIncomingDepositsFinalised = true;
        initialTimestamp = block.timestamp;
        timePeriod = initialTimestamp.add(_timePeriodInSeconds);
    }

    /**
     * @dev Allows the contract owner to allocate official ERC20 tokens to each future recipient (only one at a time).
     * @param recipient, address of recipient.
     * @param amount to allocate to recipient.
     */
    function depositTokens(address recipient, uint256 amount) public onlyOwner incomingDepositsStillAllowed {
        require(recipient != address(0), "TokenPreTimelock: ERC20: transfer to the zero address");
        balances[recipient] = balances[recipient].add(amount);
        emit AllocationPerformed(recipient, amount);
    }

    /**
     * @dev Allows the contract owner to allocate official ERC20 tokens to multiple future recipient in bulk.
     * @param recipients, an array of addresses of the many recipient.
     * @param amounts to allocate to each of the many recipient.
     */
    function bulkDepositTokens(address[] calldata recipients, uint256[] calldata amounts)
        external
        onlyOwner
        incomingDepositsStillAllowed
    {
        require(
            recipients.length == amounts.length,
            "TokenPreTimelock: The recipients and amounts arrays must be the same size in length"
        );
        for (uint256 i = 0; i < recipients.length; i++) {
            require(recipients[i] != address(0), "TokenPreTimelock: ERC20: transfer to the zero address");
            balances[recipients[i]] = balances[recipients[i]].add(amounts[i]);
            emit AllocationPerformed(recipients[i], amounts[i]);
        }
    }

    /**
     * @dev Allows recipient to unlock tokens after 24 month period has elapsed
     * @param token - address of the official ERC20 token which is being unlocked here.
     * @param to - the recipient's account address.
     * @param amount - the amount to unlock (in wei)
     */
    function transferTimeLockedTokensAfterTimePeriod(
        IERC20 token,
        address to,
        uint256 amount
    ) public timestampIsSet noReentrant {
        require(to != address(0), "ERC20: transfer to the zero address");
        require(balances[to] >= amount, "Insufficient token balance, try lesser amount");
        require(msg.sender == to, "Only the token recipient can perform the unlock");
        require(
            token == _token,
            "TokenPreTimelock: Token parameter must be the same as the erc20 contract address which was passed into the constructor"
        );
        if (block.timestamp >= timePeriod) {
            alreadyWithdrawn[to] = alreadyWithdrawn[to].add(amount);
            balances[to] = balances[to].sub(amount);
            token.safeTransfer(to, amount);
            emit TokensUnlocked(to, amount);
        } else {
            revert("TokenPreTimelock: Tokens are only available after correct time period has elapsed");
        }
    }

    /**
     * @dev Transfer accidentally locked ERC20 tokens.
     * @param token - ERC20 token address.
     * @param amount of ERC20 tokens to remove.
     */
    function transferAccidentallyLockedTokens(IERC20 token, uint256 amount) public onlyOwner noReentrant {
        require(address(token) != address(0), "TokenPreTimelock: Token address can not be zero");
        // This function can not access the official timelocked tokens; just other random ERC20 tokens that may have been accidently sent here
        require(
            token != _token,
            "TokenPreTimelock: Token address can not be ERC20 address which was passed into the constructor"
        );
        // Transfer the amount of the specified ERC20 tokens, to the owner of this contract
        token.safeTransfer(msg.sender, amount);
    }

    function getCurrentTime() public view virtual returns (uint256) {
        return block.timestamp;
    }
}