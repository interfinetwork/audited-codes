// SPDX-License-Identifier: MIT

pragma solidity ^0.8.4;

contract MisBlockBase is ERC20, Ownable {
    constructor() ERC20("UNICOIN", "UNICN") {
        _mint(msg.sender, 1000000000000 * 10 ** uint256(decimals()));
    }
}


/// @title Presale Vesting Contract
/// @dev Any address can vest tokens into this contract with amount, releaseTimestamp, revocable.
///      Anyone can claim tokens (if unlocked as per the schedule).
contract DevelopmentFundContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // State variables===================================================================================
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public totalVestedAmount;
    uint256 public totalClaimedAmount;

    struct Timelock {
        uint256 amount;
        uint256 releaseTimestamp;
    }

    mapping(address => Timelock[]) public timelocks;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenVested(address indexed claimerAddress, uint256 amount, uint256 unlockTimestamp, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);
    event VestTransferFromFailed(uint256 amount);

    //================CONSTRUCTOR================================================================
    /// @notice Constructor
    /// @param _token ERC20 token
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require( _maxVestingAmount > 0, "max vesting amount must be positive");
        
        vestingToken = _token;

        maxVestingAmount = _maxVestingAmount;
        totalVestedAmount = 0;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Vest function accessed by anyone
    /// @param _beneficiary beneficiary address
    /// @param _amount vesting amount
    /// @param _unlockTimestamp vesting unlock time
    function vest(address _beneficiary, uint256 _amount, uint256 _unlockTimestamp) external payable whenNotPaused {
        require(_beneficiary != address(0), "Invalid address");
        require(_amount > 0, "amount must be positive");
        require(maxVestingAmount != 0, "maxVestingAmount is not yet set by admin.");

        require(totalVestedAmount.add(_amount) <= maxVestingAmount, 'maxVestingAmount is already vested');
        require(_unlockTimestamp > block.timestamp, "unlock timestamp must be greater than the currrent");

        Timelock memory newVesting = Timelock(_amount, _unlockTimestamp);
        timelocks[_beneficiary].push(newVesting);

        totalVestedAmount = totalVestedAmount.add(_amount);

        // transfer to SC using delegate transfer
        // NOTE: the tokens has to be approved first by the caller to the SC using `approve()` method.
        bool success = vestingToken.transferFrom(msg.sender, address(this), _amount);
        if(success) {
            emit TokenVested(_beneficiary, _amount, _unlockTimestamp, block.timestamp);
        } else {
            emit VestTransferFromFailed(_amount);
            revert("vestingToken.transferFrom function failed");
        }
    }

    /// @notice Calculate claimable amount for a beneficiary
    /// @param _addr beneficiary address
    function claimableAmount(address _addr) public view whenNotPaused returns (uint256) {
        uint256 sum = 0;

        // iterate across all the vestings
        // & check if the releaseTimestamp is elapsed
        // then, add all the amounts as claimable amount
        for (uint256 i = 0; i < timelocks[_addr].length; i++) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                sum = sum.add(timelocks[_addr][i].amount);
            }
        }

        return sum;
    }

    /// @notice Delete claimed timelock
    /// @param _addr beneficiary address
    function deleteClaimedTimelock(address _addr) internal {
        for (uint256 i = 0; i < timelocks[_addr].length; ) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                if (i != timelocks[_addr].length - 1) {
                    timelocks[_addr][i] = timelocks[_addr][timelocks[_addr].length - 1];
                }
                timelocks[_addr].pop();
            } else {
                ++i;
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Claim vesting
    /// @dev Beneficiary can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) external whenNotPaused {
        require(vestingToken == _token, "invalid token address");

        uint256 amount = claimableAmount(msg.sender);
        require(amount > 0, "Claimable amount must be positive");
        require(amount <= totalVestedAmount, "Cannot withdraw more than the total vested amount");
        
        totalClaimedAmount = totalClaimedAmount.add(amount);
        deleteClaimedTimelock(msg.sender);

        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);

        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Pause contract 
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}


/// @title Influencers Contract
contract InfluencerContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, 'Caller should be beneficiary');
        _;
    }

    // State variables===================================================================================
    using SafeMath for uint256;

    address public beneficiary;
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public releaseTime;
    uint256 public totalClaimedAmount;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);

    /// @notice Constructor
    /// @param _token token contract Interface
    /// @param _beneficiary Beneficiary address
    /// @param _releaseTime Unlock time
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _releaseTime,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require(_beneficiary != address(0), 'Invalid address');
        require( _maxVestingAmount > 0, "max vesting amount must be positive");

        beneficiary = _beneficiary;
        vestingToken = _token;
        releaseTime = _releaseTime;

        maxVestingAmount = _maxVestingAmount;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    /// @notice Calculate claimable amount
    function claimableAmount() public view whenNotPaused returns(uint256) {
        if (releaseTime > block.timestamp) return 0;
        return maxVestingAmount;
    }

    /// @notice Claim vesting
    /// @dev Anyone can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) public onlyBeneficiary whenNotPaused {
       require(vestingToken == _token, "invalid token address");

        uint256 amount = claimableAmount();
        require(amount > 0, "Claimable amount must be positive");

        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);
        
        totalClaimedAmount = totalClaimedAmount.add(amount);
        
        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    /// @notice Pause contract  
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}


/// @title Manual Burning Contract
contract ManualBurningContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // State variables===================================================================================
    using SafeMath for uint256;

    IERC20 public vestingToken;
    uint256 public maxVestingAmount;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);

    /// @notice Constructor
    /// @param _token token contract Interface
    constructor(
        IERC20 _token,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require( _maxVestingAmount > 0, "max vesting amount must be positive");
        
        maxVestingAmount = _maxVestingAmount;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    /// @notice Pause contract  
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}


/// @title Marketing Contract
/// @dev Any address can vest tokens into this contract with amount, releaseTimestamp, revocable.
///      Anyone can claim tokens (if unlocked as per the schedule).
contract MarketingContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // State variables===================================================================================
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public totalVestedAmount;
    uint256 public totalClaimedAmount;

    struct Timelock {
        uint256 amount;
        uint256 releaseTimestamp;
    }

    mapping(address => Timelock[]) public timelocks;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenVested(address indexed claimerAddress, uint256 amount, uint256 unlockTimestamp, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);
    event VestTransferFromFailed(uint256 amount);

    //================CONSTRUCTOR================================================================
    /// @notice Constructor
    /// @param _token ERC20 token
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require( _maxVestingAmount > 0, "max vesting amount must be positive");
        
        vestingToken = _token;

        maxVestingAmount = _maxVestingAmount;
        totalVestedAmount = 0;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Vest function accessed by anyone
    /// @param _beneficiary beneficiary address
    /// @param _amount vesting amount
    /// @param _unlockTimestamp vesting unlock time
    function vest(address _beneficiary, uint256 _amount, uint256 _unlockTimestamp) external payable whenNotPaused {
        require(_beneficiary != address(0), "Invalid address");
        require(_amount > 0, "amount must be positive");
        require(maxVestingAmount != 0, "maxVestingAmount is not yet set by admin.");

        require(totalVestedAmount.add(_amount) <= maxVestingAmount, 'maxVestingAmount is already vested');
        require(_unlockTimestamp > block.timestamp, "unlock timestamp must be greater than the currrent");

        Timelock memory newVesting = Timelock(_amount, _unlockTimestamp);
        timelocks[_beneficiary].push(newVesting);

        totalVestedAmount = totalVestedAmount.add(_amount);

        // transfer to SC using delegate transfer
        // NOTE: the tokens has to be approved first by the caller to the SC using `approve()` method.
        bool success = vestingToken.transferFrom(msg.sender, address(this), _amount);
        if(success) {
            emit TokenVested(_beneficiary, _amount, _unlockTimestamp, block.timestamp);
        } else {
            emit VestTransferFromFailed(_amount);
            revert("vestingToken.transferFrom function failed");
        }
    }

    /// @notice Calculate claimable amount for a beneficiary
    /// @param _addr beneficiary address
    function claimableAmount(address _addr) public view whenNotPaused returns (uint256) {
        uint256 sum = 0;

        // iterate across all the vestings
        // & check if the releaseTimestamp is elapsed
        // then, add all the amounts as claimable amount
        for (uint256 i = 0; i < timelocks[_addr].length; i++) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                sum = sum.add(timelocks[_addr][i].amount);
            }
        }

        return sum;
    }

    /// @notice Delete claimed timelock
    /// @param _addr beneficiary address
    function deleteClaimedTimelock(address _addr) internal {
        for (uint256 i = 0; i < timelocks[_addr].length; ) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                if (i != timelocks[_addr].length - 1) {
                    timelocks[_addr][i] = timelocks[_addr][timelocks[_addr].length - 1];
                }
                timelocks[_addr].pop();
            } else {
                ++i;
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Claim vesting
    /// @dev Beneficiary can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) external whenNotPaused {
        require(vestingToken == _token, "invalid token address");

        uint256 amount = claimableAmount(msg.sender);
        require(amount > 0, "Claimable amount must be positive");
        require(amount <= totalVestedAmount, "Cannot withdraw more than the total vested amount");
        
        totalClaimedAmount = totalClaimedAmount.add(amount);
        deleteClaimedTimelock(msg.sender);

        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);

        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Pause contract 
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}


/// @title Presale Vesting Contract
/// @dev Any address can vest tokens into this contract with amount, releaseTimestamp, revocable.
///      Anyone can claim tokens (if unlocked as per the schedule).
contract PresaleContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // State variables===================================================================================
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public totalVestedAmount;
    uint256 public totalClaimedAmount;

    struct Timelock {
        uint256 amount;
        uint256 releaseTimestamp;
    }

    mapping(address => Timelock[]) public timelocks;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenVested(address indexed claimerAddress, uint256 amount, uint256 unlockTimestamp, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);
    event VestTransferFromFailed(uint256 amount);

    //================CONSTRUCTOR================================================================
    /// @notice Constructor
    /// @param _token ERC20 token
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require( _maxVestingAmount > 0, "max vesting amount must be positive");
        
        vestingToken = _token;

        maxVestingAmount = _maxVestingAmount;
        totalVestedAmount = 0;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Vest function accessed by anyone
    /// @param _beneficiary beneficiary address
    /// @param _amount vesting amount
    /// @param _unlockTimestamp vesting unlock time
    function vest(address _beneficiary, uint256 _amount, uint256 _unlockTimestamp) external payable whenNotPaused {
        require(_beneficiary != address(0), "Invalid address");
        require(_amount > 0, "amount must be positive");
        require(maxVestingAmount != 0, "maxVestingAmount is not yet set by admin.");

        require(totalVestedAmount.add(_amount) <= maxVestingAmount, 'maxVestingAmount is already vested');
        require(_unlockTimestamp > block.timestamp, "unlock timestamp must be greater than the currrent");

        Timelock memory newVesting = Timelock(_amount, _unlockTimestamp);
        timelocks[_beneficiary].push(newVesting);

        totalVestedAmount = totalVestedAmount.add(_amount);

        // transfer to SC using delegate transfer
        // NOTE: the tokens has to be approved first by the caller to the SC using `approve()` method.
        bool success = vestingToken.transferFrom(msg.sender, address(this), _amount);
        if(success) {
            emit TokenVested(_beneficiary, _amount, _unlockTimestamp, block.timestamp);
        } else {
            emit VestTransferFromFailed(_amount);
            revert("vestingToken.transferFrom function failed");
        }
    }

    /// @notice Calculate claimable amount for a beneficiary
    /// @param _addr beneficiary address
    function claimableAmount(address _addr) public view whenNotPaused returns (uint256) {
        uint256 sum = 0;

        // iterate across all the vestings
        // & check if the releaseTimestamp is elapsed
        // then, add all the amounts as claimable amount
        for (uint256 i = 0; i < timelocks[_addr].length; i++) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                sum = sum.add(timelocks[_addr][i].amount);
            }
        }

        return sum;
    }

    /// @notice Delete claimed timelock
    /// @param _addr beneficiary address
    function deleteClaimedTimelock(address _addr) internal {
        for (uint256 i = 0; i < timelocks[_addr].length; ) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                if (i != timelocks[_addr].length - 1) {
                    timelocks[_addr][i] = timelocks[_addr][timelocks[_addr].length - 1];
                }
                timelocks[_addr].pop();
            } else {
                ++i;
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Claim vesting
    /// @dev Beneficiary can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) external whenNotPaused {
        require(vestingToken == _token, "invalid token address");

        uint256 amount = claimableAmount(msg.sender);
        require(amount > 0, "Claimable amount must be positive");
        require(amount <= totalVestedAmount, "Cannot withdraw more than the total vested amount");
        
        totalClaimedAmount = totalClaimedAmount.add(amount);
        deleteClaimedTimelock(msg.sender);

        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);

        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Pause contract 
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}


/// @title Staking Contract
contract StakingContract is Ownable, Pausable {
   using SafeMath for uint256;
    using SafeERC20 for IERC20;
    
    modifier onlyBeneficiary() {
        require(msg.sender == beneficiary, 'Caller should be beneficiary');
        _;
    }

    // State variables===================================================================================
    using SafeMath for uint256;

    address public beneficiary;
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public releaseTime;
    uint256 public totalClaimedAmount;

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);
    
    /// @notice Constructor
    /// @param _token token contract Interface
    /// @param _beneficiary Beneficiary address
    /// @param _releaseTime Unlock time
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        address _beneficiary,
        uint256 _releaseTime,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require(_beneficiary != address(0), 'Invalid address');
        require( _maxVestingAmount > 0, "max vesting amount must be positive");

        beneficiary = _beneficiary;
        vestingToken = _token;
        releaseTime = _releaseTime;

        maxVestingAmount = _maxVestingAmount;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    /// @notice Calculate claimable amount
    function claimableAmount() public view whenNotPaused returns(uint256) {
        if (releaseTime > block.timestamp) return 0;
        return maxVestingAmount;
    }

    /// @notice Claim vesting
    /// @dev Anyone can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) public onlyBeneficiary whenNotPaused {
       require(vestingToken == _token, "invalid token address");

        uint256 amount = claimableAmount();
        require(amount > 0, "Claimable amount must be positive");

        totalClaimedAmount = totalClaimedAmount.add(amount);
        
        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);        
        
        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    /// @notice Pause contract  
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}

/// @title Team Vesting Contract
/// @dev Any address can vest tokens into this contract with amount, releaseTimestamp, revocable.
///      Anyone can claim tokens (if unlocked as per the schedule).
contract TeamVestingContract is Ownable, Pausable {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // State variables===================================================================================
    IERC20 public vestingToken;

    uint256 public maxVestingAmount;
    uint256 public totalVestedAmount;
    uint256 public totalClaimedAmount;

    struct Timelock {
        uint256 amount;
        uint256 releaseTimestamp;
    }

    mapping(address => Timelock[]) public timelocks;

    // Now, no need of `revoked` param as:
    // if (revokeTimes[addr] == 0) => the address is not revoked, else it's revoked.
    mapping(address => uint256) public revokeTimes;         // key: beneficiary address, value: revokeTimestamp

    // ===============EVENTS============================================================================================
    event UpdatedMaxVestingAmount(address caller, uint256 amount, uint256 currentTimestamp);
    event TokenVested(address indexed claimerAddress, uint256 amount, uint256 unlockTimestamp, uint256 currentTimestamp);
    event TokenClaimed(address indexed claimerAddress, uint256 amount, uint256 currentTimestamp);
    event Revoke(address indexed account, uint256 currentTimestamp);
    event Unrevoke(address indexed account, uint256 currentTimestamp);
    event VestTransferFromFailed(uint256 amount);

    //================CONSTRUCTOR================================================================
    /// @notice Constructor
    /// @param _token ERC20 token
    /// @param _maxVestingAmount max vesting amount. This is also updatable using `updateMaxVestingAmount` 
    constructor(
        IERC20 _token,
        uint256 _maxVestingAmount
    ) {
        require(address(_token) != address(0), "Invalid address");
        require( _maxVestingAmount > 0, "max vesting amount must be positive");
        
        vestingToken = _token;

        maxVestingAmount = _maxVestingAmount;
        totalVestedAmount = 0;
        totalClaimedAmount = 0;
    }

    //=================FUNCTIONS=================================================================
    /// @notice Update vesting contract maximum amount
    /// @param _maxAmount amount. This can be modified by the owner only 
    ///        so as to increase the max vesting amount
    function updateMaxVestingAmount(uint256 _maxAmount) external onlyOwner whenNotPaused {
        maxVestingAmount = maxVestingAmount.add(_maxAmount);

        emit UpdatedMaxVestingAmount(msg.sender, _maxAmount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Vest function accessed by anyone
    /// @param _beneficiary beneficiary address
    /// @param _amount vesting amount
    /// @param _unlockTimestamp vesting unlock time
    function vest(address _beneficiary, uint256 _amount, uint256 _unlockTimestamp) external payable whenNotPaused {
        require(_beneficiary != address(0), "Invalid address");
        require( _amount > 0, "amount must be positive");
        require(maxVestingAmount != 0, "maxVestingAmount is not yet set by admin.");

        require(totalVestedAmount.add(_amount) <= maxVestingAmount, 'maxVestingAmount is already vested');
        require(_unlockTimestamp > block.timestamp, "unlock timestamp must be greater than the currrent");

        Timelock memory newVesting = Timelock(_amount, _unlockTimestamp);
        timelocks[_beneficiary].push(newVesting);

        totalVestedAmount = totalVestedAmount.add(_amount);

        // transfer to SC using delegate transfer
        // NOTE: the tokens has to be approved first by the caller to the SC using `approve()` method.
        bool success = vestingToken.transferFrom(msg.sender, address(this), _amount);
        if(success) {
            emit TokenVested(_beneficiary, _amount, _unlockTimestamp, block.timestamp);
        } else {
            emit VestTransferFromFailed(_amount);
            revert("vestingToken.transferFrom function failed");
        }
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Revoke vesting
    /// @dev The vesting is revoked by setting the value of `revokeTimes` mapping as `revoke timestamp` 
    /// @param _addr beneficiary address
    function revoke(address _addr) public onlyOwner whenNotPaused {
        require(revokeTimes[_addr] == 0, 'Account must not already be revoked.');

        revokeTimes[_addr] = block.timestamp;
        
        emit Revoke(_addr, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Unrevoke vesting
    /// @dev The vesting is unrevoked by setting the value of `revokeTimes` mapping as zero.
    ///         This indicates that the beneficiary has able to claim. 
    /// @param _addr beneficiary address
    function unrevoke(address _addr) public onlyOwner whenNotPaused {
        require(revokeTimes[_addr] != 0, 'Account must already be revoked.');

        revokeTimes[_addr] = 0;
        
        emit Unrevoke(_addr, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Calculate claimable amount for a beneficiary
    /// @param _addr beneficiary address
    function claimableAmount(address _addr) public view whenNotPaused returns (uint256) {
        uint256 sum = 0;

        // iterate across all the vestings
        // & check if the releaseTimestamp is elapsed
        // then, add all the amounts as claimable amount
        for (uint256 i = 0; i < timelocks[_addr].length; i++) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                sum = sum.add(timelocks[_addr][i].amount);
            }
        }

        return sum;
    }

    /// @notice Delete claimed timelock
    /// @param _addr beneficiary address
    function deleteClaimedTimelock(address _addr) internal {
        for (uint256 i = 0; i < timelocks[_addr].length; ) {
            if ( block.timestamp >= timelocks[_addr][i].releaseTimestamp ) {
                if (i != timelocks[_addr].length - 1) {
                    timelocks[_addr][i] = timelocks[_addr][timelocks[_addr].length - 1];
                }
                timelocks[_addr].pop();
            } else {
                ++i;
            }
        }
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Claim vesting
    /// @dev Beneficiary can claim claimableAmount which was vested
    /// @param _token Vesting token contract
    function claim(IERC20 _token) external whenNotPaused {
        require(vestingToken == _token, "invalid token address");
        require(revokeTimes[msg.sender] == 0, 'Account must not already be revoked');

        uint256 amount = claimableAmount(msg.sender);
        require(amount > 0, "Claimable amount must be positive");
        require(amount <= totalVestedAmount, "Cannot withdraw more than the total vested amount");
        
        totalClaimedAmount = totalClaimedAmount.add(amount);
        deleteClaimedTimelock(msg.sender);

        // transfer from SC
        vestingToken.safeTransfer(msg.sender, amount);
        
        emit TokenClaimed(msg.sender, amount, block.timestamp);
    }

    // ------------------------------------------------------------------------------------------
    /// @notice Pause contract 
    function pause() public onlyOwner whenNotPaused {
        _pause();
    }

    /// @notice Unpause contract
    function unpause() public onlyOwner whenPaused {
        _unpause();
    }
}