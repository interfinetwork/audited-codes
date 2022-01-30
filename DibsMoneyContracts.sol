// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

contract DBond is ERC20Burnable, Operator {
    /**
     * @notice Constructs the DIBS Bond ERC-20 contract.
     */
    constructor() public ERC20("DBOND", "DBOND") {}

    /**
     * @notice Operator mints basis bonds to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of basis bonds to mint to
     * @return whether the process has been done
     */

    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }
}


contract Dibs is ERC20Burnable, Operator {
    using SafeMath8 for uint8;
    using SafeMath for uint256;

    // Initial distribution for the first 12h genesis pools
    uint256 public constant INITIAL_GENESIS_POOL_DISTRIBUTION = 11000 ether;
    // Distribution for DAO wallet
    uint256 public constant INITIAL_DAO_WALLET_DISTRIBUTION = 300 ether;

    // Have the rewards been distributed to the pools
    bool public rewardPoolDistributed = false;

    /* ================= Taxation =============== */
    // Address of the Oracle
    address public dibsOracle;
    // Address of the Tax Office
    address public taxOffice;

    // Current tax rate
    uint256 public taxRate;
    // Price threshold below which taxes will get burned
    uint256 public burnThreshold = 1.10e18;
    // Address of the tax collector wallet
    address public taxCollectorAddress;

    // Should the taxes be calculated using the tax tiers
    bool public autoCalculateTax;

    // Tax Tiers
    uint256[] public taxTiersTwaps = [0, 5e17, 6e17, 7e17, 8e17, 9e17, 9.5e17, 1e18, 1.05e18, 1.10e18, 1.20e18, 1.30e18, 1.40e18, 1.50e18];
    uint256[] public taxTiersRates = [2000, 1900, 1800, 1700, 1600, 1500, 1500, 1500, 1500, 1400, 900, 400, 200, 100];

    // Sender addresses excluded from Tax
    mapping(address => bool) public excludedAddresses;

    event TaxOfficeTransferred(address oldAddress, address newAddress);

    modifier onlyTaxOffice() {
        require(taxOffice == msg.sender, "Caller is not the tax office");
        _;
    }

    modifier onlyOperatorOrTaxOffice() {
        require(isOperator() || taxOffice == msg.sender, "Caller is not the operator or the tax office");
        _;
    }

    /**
     * @notice Constructs the DIBS ERC-20 contract.
     */
    constructor(uint256 _taxRate, address _taxCollectorAddress) public ERC20("dibs.money", "DIBS") {
        // Mints 1 DIBS to contract creator for initial pool setup
        require(_taxRate < 10000, "tax equal or bigger to 100%");
        require(_taxCollectorAddress != address(0), "tax collector address must be non-zero address");

        excludeAddress(address(this));

        _mint(msg.sender, 1 ether);
        taxRate = _taxRate;
        taxCollectorAddress = _taxCollectorAddress;
    }

    /* ============= Taxation ============= */

    function getTaxTiersTwapsCount() public view returns (uint256 count) {
        return taxTiersTwaps.length;
    }

    function getTaxTiersRatesCount() public view returns (uint256 count) {
        return taxTiersRates.length;
    }

    function isAddressExcluded(address _address) public view returns (bool) {
        return excludedAddresses[_address];
    }

    function setTaxTiersTwap(uint8 _index, uint256 _value) public onlyTaxOffice returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < getTaxTiersTwapsCount(), "Index has to lower than count of tax tiers");
        if (_index > 0) {
            require(_value > taxTiersTwaps[_index - 1]);
        }
        if (_index < getTaxTiersTwapsCount().sub(1)) {
            require(_value < taxTiersTwaps[_index + 1]);
        }
        taxTiersTwaps[_index] = _value;
        return true;
    }

    function setTaxTiersRate(uint8 _index, uint256 _value) public onlyTaxOffice returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < getTaxTiersRatesCount(), "Index has to lower than count of tax tiers");
        taxTiersRates[_index] = _value;
        return true;
    }

    function setBurnThreshold(uint256 _burnThreshold) public onlyTaxOffice returns (bool) {
        burnThreshold = _burnThreshold;
    }

    function _getDibsPrice() internal view returns (uint256 _dibsPrice) {
        try IOracle(dibsOracle).consult(address(this), 1e18) returns (uint144 _price) {
            return uint256(_price);
        } catch {
            revert("Dibs: failed to fetch DIBS price from Oracle");
        }
    }

    function _updateTaxRate(uint256 _dibsPrice) internal returns (uint256) {
        if (autoCalculateTax) {
            for (uint8 tierId = uint8(getTaxTiersTwapsCount()).sub(1); tierId >= 0; --tierId) {
                if (_dibsPrice >= taxTiersTwaps[tierId]) {
                    require(taxTiersRates[tierId] < 10000, "tax equal or bigger to 100%");
                    taxRate = taxTiersRates[tierId];
                    return taxTiersRates[tierId];
                }
            }
        }
    }

    function enableAutoCalculateTax() public onlyTaxOffice {
        autoCalculateTax = true;
    }

    function disableAutoCalculateTax() public onlyTaxOffice {
        autoCalculateTax = false;
    }

    function setDibsOracle(address _dibsOracle) public onlyOperatorOrTaxOffice {
        require(_dibsOracle != address(0), "oracle address cannot be 0 address");
        dibsOracle = _dibsOracle;
    }

    function setTaxOffice(address _taxOffice) public onlyOperatorOrTaxOffice {
        require(_taxOffice != address(0), "tax office address cannot be 0 address");
        emit TaxOfficeTransferred(taxOffice, _taxOffice);
        taxOffice = _taxOffice;
    }

    function setTaxCollectorAddress(address _taxCollectorAddress) public onlyTaxOffice {
        require(_taxCollectorAddress != address(0), "tax collector address must be non-zero address");
        taxCollectorAddress = _taxCollectorAddress;
    }

    function setTaxRate(uint256 _taxRate) public onlyTaxOffice {
        require(!autoCalculateTax, "auto calculate tax cannot be enabled");
        require(_taxRate < 10000, "tax equal or bigger to 100%");
        taxRate = _taxRate;
    }

    function excludeAddress(address _address) public onlyOperatorOrTaxOffice returns (bool) {
        require(!excludedAddresses[_address], "address can't be excluded");
        excludedAddresses[_address] = true;
        return true;
    }

    function includeAddress(address _address) public onlyOperatorOrTaxOffice returns (bool) {
        require(excludedAddresses[_address], "address can't be included");
        excludedAddresses[_address] = false;
        return true;
    }

    /**
     * @notice Operator mints DIBS to a recipient
     * @param recipient_ The address of recipient
     * @param amount_ The amount of DIBS to mint to
     * @return whether the process has been done
     */
    function mint(address recipient_, uint256 amount_) public onlyOperator returns (bool) {
        uint256 balanceBefore = balanceOf(recipient_);
        _mint(recipient_, amount_);
        uint256 balanceAfter = balanceOf(recipient_);

        return balanceAfter > balanceBefore;
    }

    function burn(uint256 amount) public override {
        super.burn(amount);
    }

    function burnFrom(address account, uint256 amount) public override onlyOperator {
        super.burnFrom(account, amount);
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public override returns (bool) {
        uint256 currentTaxRate = 0;
        bool burnTax = false;

        if (autoCalculateTax) {
            uint256 currentDibsPrice = _getDibsPrice();
            currentTaxRate = _updateTaxRate(currentDibsPrice);
            if (currentDibsPrice < burnThreshold) {
                burnTax = true;
            }
        }

        if (currentTaxRate == 0 || excludedAddresses[sender]) {
            _transfer(sender, recipient, amount);
        } else {
            _transferWithTax(sender, recipient, amount, burnTax);
        }

        _approve(sender, _msgSender(), allowance(sender, _msgSender()).sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function _transferWithTax(
        address sender,
        address recipient,
        uint256 amount,
        bool burnTax
    ) internal returns (bool) {
        uint256 taxAmount = amount.mul(taxRate).div(10000);
        uint256 amountAfterTax = amount.sub(taxAmount);

        if (burnTax) {
            // Burn tax
            super.burnFrom(sender, taxAmount);
        } else {
            // Transfer tax to tax collector
            _transfer(sender, taxCollectorAddress, taxAmount);
        }

        // Transfer amount after tax to recipient
        _transfer(sender, recipient, amountAfterTax);

        return true;
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(
        address[] memory _genesisPools,
        address _daoWallet
    ) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_genesisPools.length > 0, "_genesisPools.length > 0");
        require(_daoWallet != address(0), "!_daoWallet");
        rewardPoolDistributed = true;

        uint256 genesisPoolStake = INITIAL_GENESIS_POOL_DISTRIBUTION.div(_genesisPools.length);
        for(uint256 i = 0; i < _genesisPools.length; i++) {
            require(_genesisPools[i] != address(0), "!_genesisPool");
            _mint(_genesisPools[i], genesisPoolStake);
        }

        _mint(_daoWallet, INITIAL_DAO_WALLET_DISTRIBUTION);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        _token.transfer(_to, _amount);
    }
}

contract DShare is ERC20Burnable, Operator {
    using SafeMath for uint256;

    /*
        TOTAL MAX SUPPLY = 70,000 dSHAREs
        - 36000 dShares allocated to Dibs-BNB
        - 24000 dShares allocated to dShare-BNB
        - Airdop 500 dShares allocated to DAO wallet
        - Allocate 4500 dShares to DAO wallet for linear vesting
        - Airdrop 360 dShares to Dev wallet
        - Allocate 4640 dShares to Dev wallet for linear vesting
    */
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 60000 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 4500 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 4640 ether;

    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    bool public rewardPoolDistributed = false;

    constructor(uint256 _startTime, address _daoFund, address _devFund) public ERC20("DSHARE", "DSHARE") {
        _mint(msg.sender, 2 ether);         // mint 2 DIBS Share for initial pools deployment and Piggybank initialization
        _mint(_daoFund, 500 ether);         // Airdop 500 Dshares allocated to DAO wallet
        _mint(_devFund, 358 ether);         // Airdop 358 Dshares allocated to DEV wallet + 2 dShare for initialization

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate = COMMUNITY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_daoFund != address(0), "Address cannot be 0");
        communityFund = _daoFund;
    }

    function setTreasuryFund(address _daoFund) external {
        require(msg.sender == devFund, "!dev");
        communityFund = _daoFund;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(communityFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && communityFund != address(0)) {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
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
}

interface IHyperswapRouter01 {
    function factory() external pure returns (address);
    function WFTM() external pure returns (address);

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
    function addLiquidityFTM(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountFTMMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountFTM, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityFTM(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountFTMMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountFTM);
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
    function removeLiquidityFTMWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountFTMMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountFTM);
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
    function swapExactFTMForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactFTM(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForFTM(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapFTMForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

// Part: IUniswapV2Pair

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

// Part: IUniswapV2Router01

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
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
        ) external;
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
      ) external;
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

// Part: OpenZeppelin/openzeppelin-contracts@4.1.0/IERC20

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
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

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


// Part: IVault

interface IVault is IERC20 {
    function deposit(uint256 amount) external;
    function withdraw(uint256 shares) external;
    function want() external pure returns (address);
}

// Part: OpenZeppelin/openzeppelin-contracts@4.1.0/Address

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// Part: OpenZeppelin/openzeppelin-contracts@4.1.0/SafeMath

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

// Part: TransferHelper

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: APPROVE_FAILED');
    }

    function safeTransfer(address token, address to, uint value) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FAILED');
    }

    function safeTransferFrom(address token, address from, address to, uint value) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'TransferHelper: TRANSFER_FROM_FAILED');
    }

    function safeTransferETH(address to, uint value) internal {
        (bool success,) = to.call{value:value}(new bytes(0));
        require(success, 'TransferHelper: ETH_TRANSFER_FAILED');
    }
}

// Part: OpenZeppelin/openzeppelin-contracts@4.1.0/SafeERC20

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// File: Context.sol

pragma solidity ^0.8.0;

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

    function _msgData() internal view virtual returns (bytes calldata) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
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
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
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

// File: IZap.sol

interface IZap {
    function estimateZapInToken(address _from, address _to, address _router, uint _amt) external view returns (uint256, uint256);
    function swapToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external;
    function swapToNative(address _from, uint amount, address routerAddr, address _recipient) external;
    function zapIn(address _to, address routerAddr, address _recipient) external payable;
    function zapInToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external;
    function zapAcross(address _from, uint amount, address _toRouter, address _recipient) external;
    function zapOut(address _from, uint amount, address routerAddr, address _recipient) external;
    function zapOutToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external;
}


// File: Zap.sol

contract Zap is Ownable, IZap {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /* ========== STATE VARIABLES ========== */

    address private WNATIVE;
    mapping(address => mapping(address => address)) private tokenBridgeForRouter;
    mapping(address => bool) public isFeeOnTransfer;

    mapping (address => bool) public useNativeRouter;

    constructor(address _WNATIVE) Ownable() {
       WNATIVE = _WNATIVE;
    }

    /* ========== External Functions ========== */

    receive() external payable {}

    function zapInToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external override {
        _approveTokenIfNeeded(_from, routerAddr);

        if (isFeeOnTransfer[_from]) {
            IERC20(_from).transferFrom(msg.sender, address(this), amount);
            _swapTokenToLP(_from, IERC20(_from).balanceOf(address(this)), _to, _recipient, routerAddr);
            return;
        } else {
            // From an ERC20 to an LP token, through specified router, going through base asset if necessary
            IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
            // we'll need this approval to add liquidity
            _approveTokenIfNeeded(_from, routerAddr);
            _swapTokenToLP(_from, amount, _to, _recipient, routerAddr);
            return;
        }
        if (IERC20(_from).balanceOf(address(this)) != 0) {
            IERC20(_from).transfer(msg.sender, IERC20(_from).balanceOf(address(this)));
        }
        if (IERC20(_to).balanceOf(address(this)) != 0) {
            IERC20(_from).transfer(msg.sender, IERC20(_from).balanceOf(address(this)));
        }
    }

    function estimateZapInToken(address _from, address _to, address _router, uint _amt) public view override returns (uint256, uint256) {
        // get pairs for desired lp
        if (_from == IUniswapV2Pair(_to).token0() || _from == IUniswapV2Pair(_to).token1()) { // check if we already have one of the assets
            // if so, we're going to sell half of _from for the other token we need
            // figure out which token we need, and approve
            address other = _from == IUniswapV2Pair(_to).token0() ? IUniswapV2Pair(_to).token1() : IUniswapV2Pair(_to).token0();
            // calculate amount of _from to sell
            uint sellAmount = _amt.div(2);
            // execute swap
            uint otherAmount = _estimateSwap(_from, sellAmount, other, _router);
            if (_from == IUniswapV2Pair(_to).token0()) {
                return (sellAmount, otherAmount);
            } else {
                return (otherAmount, sellAmount);
            }
        } else {
            // go through native token for highest liquidity
            uint nativeAmount = _from == WNATIVE ? _amt : _estimateSwap(_from, _amt, WNATIVE, _router);
            if (WNATIVE == IUniswapV2Pair(_to).token0()) {
                return (nativeAmount.div(2), _estimateSwap(WNATIVE, nativeAmount.div(2), IUniswapV2Pair(_to).token1(), _router ));
            }
            if (WNATIVE == IUniswapV2Pair(_to).token1()) {
                return (_estimateSwap(WNATIVE, nativeAmount.div(2), IUniswapV2Pair(_to).token0(), _router ), nativeAmount.div(2));
            }
                return (_estimateSwap(WNATIVE, nativeAmount.div(2), IUniswapV2Pair(_to).token0(), _router ), _estimateSwap(WNATIVE, nativeAmount.div(2), IUniswapV2Pair(_to).token1(), _router));
        }
    }

    function zapIn(address _to, address routerAddr, address _recipient) external payable override {
        // from Native to an LP token through the specified router
        _swapNativeToLP(_to, msg.value, _recipient, routerAddr);
        if (address(this).balance != 0) {
            TransferHelper.safeTransferETH(msg.sender, address(this).balance);
        }
    }

    function zapAcross(address _from, uint amount, address _toRouter, address _recipient) external override {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);

        IUniswapV2Pair pair = IUniswapV2Pair(_from);
        _approveTokenIfNeeded(pair.token0(), _toRouter);
        _approveTokenIfNeeded(pair.token1(), _toRouter);

        IERC20(_from).safeTransfer(_from, amount);
        uint amt0;
        uint amt1;
        (amt0, amt1) = pair.burn(address(this));
        IUniswapV2Router01(_toRouter).addLiquidity(pair.token0(), pair.token1(), amt0, amt1, 0, 0, _recipient, block.timestamp);
    }

    function zapOut(address _from, uint amount, address routerAddr, address _recipient) external override {
        // from an LP token to Native through specified router
        // take the LP token
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, routerAddr);

        // get pairs for LP
        address token0 = IUniswapV2Pair(_from).token0();
        address token1 = IUniswapV2Pair(_from).token1();
        _approveTokenIfNeeded(token0, routerAddr);
        _approveTokenIfNeeded(token1, routerAddr);
        // check if either is already native token
        if (token0 == WNATIVE || token1 == WNATIVE) {
            // if so, we only need to swap one, figure out which and how much
            address token = token0 != WNATIVE ? token0 : token1;
            uint amtToken;
            uint amtETH;
            (amtToken, amtETH) = IUniswapV2Router01(routerAddr).removeLiquidityETH(token, amount, 0, 0, address(this), block.timestamp);
            // swap with msg.sender as recipient, so they already get the Native
            _swapTokenForNative(token, amtToken, _recipient, routerAddr);
            // send other half of Native
            TransferHelper.safeTransferETH(_recipient, amtETH);
        } else {
            // convert both for Native with msg.sender as recipient
            uint amt0;
            uint amt1;
            (amt0, amt1) = IUniswapV2Router01(routerAddr).removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);
            _swapTokenForNative(token0, amt0, _recipient, routerAddr);
            _swapTokenForNative(token1, amt1, _recipient, routerAddr);
        }
    }

    function zapOutToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external override {
        // from an LP token to an ERC20 through specified router
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, routerAddr);

        address token0 = IUniswapV2Pair(_from).token0();
        address token1 = IUniswapV2Pair(_from).token1();
        _approveTokenIfNeeded(token0, routerAddr);
        _approveTokenIfNeeded(token1, routerAddr);
        uint amt0;
        uint amt1;
        (amt0, amt1) = IUniswapV2Router01(routerAddr).removeLiquidity(token0, token1, amount, 0, 0, address(this), block.timestamp);
        if (token0 != _to) {
            amt0 = _swap(token0, amt0, _to, address(this), routerAddr);
        }
        if (token1 != _to) {
            amt1 = _swap(token1, amt1, _to, address(this), routerAddr);
        }
        IERC20(_to).safeTransfer(_recipient, amt0.add(amt1));
    }

    function swapToken(address _from, uint amount, address _to, address routerAddr, address _recipient) external override {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, routerAddr);
        _swap(_from, amount, _to, _recipient, routerAddr);
    }

    function swapToNative(address _from, uint amount, address routerAddr, address _recipient) external override {
        IERC20(_from).safeTransferFrom(msg.sender, address(this), amount);
        _approveTokenIfNeeded(_from, routerAddr);
        _swapTokenForNative(_from, amount, _recipient, routerAddr);
    }


    /* ========== Private Functions ========== */

    function _approveTokenIfNeeded(address token, address router) private {
        if (IERC20(token).allowance(address(this), router) == 0) {
            IERC20(token).safeApprove(router, type(uint).max);
        }
    }

    function _swapTokenToLP(address _from, uint amount, address _to, address recipient, address routerAddr) private returns (uint) {
                // get pairs for desired lp
        if (_from == IUniswapV2Pair(_to).token0() || _from == IUniswapV2Pair(_to).token1()) { // check if we already have one of the assets
            // if so, we're going to sell half of _from for the other token we need
            // figure out which token we need, and approve
            address other = _from == IUniswapV2Pair(_to).token0() ? IUniswapV2Pair(_to).token1() : IUniswapV2Pair(_to).token0();
            _approveTokenIfNeeded(other, routerAddr);
            // calculate amount of _from to sell
            uint sellAmount = amount.div(2);
            // execute swap
            uint otherAmount = _swap(_from, sellAmount, other, address(this), routerAddr);
            uint liquidity;
            ( , , liquidity) = IUniswapV2Router01(routerAddr).addLiquidity(_from, other, amount.sub(sellAmount), otherAmount, 0, 0, recipient, block.timestamp);
            return liquidity;
        } else {
            // go through native token for highest liquidity
            uint nativeAmount = _swapTokenForNative(_from, amount, address(this), routerAddr);
            return _swapNativeToLP(_to, nativeAmount, recipient, routerAddr);
        }
    }

    function _swapNativeToLP(address _LP, uint amount, address recipient, address routerAddress) private returns (uint) {
            // LP
            IUniswapV2Pair pair = IUniswapV2Pair(_LP);
            address token0 = pair.token0();
            address token1 = pair.token1();
            uint liquidity;
            if (token0 == WNATIVE || token1 == WNATIVE) {
                address token = token0 == WNATIVE ? token1 : token0;
                ( , , liquidity) = _swapHalfNativeAndProvide(token, amount, routerAddress, recipient);
            } else {
                ( , , liquidity) = _swapNativeToEqualTokensAndProvide(token0, token1, amount, routerAddress, recipient);
            }
            return liquidity;
    }

    function _swapHalfNativeAndProvide(address token, uint amount, address routerAddress, address recipient) private returns (uint, uint, uint) {
            uint swapValue = amount.div(2);
            uint tokenAmount = _swapNativeForToken(token, swapValue, address(this), routerAddress);
            _approveTokenIfNeeded(token, routerAddress);
            if (useNativeRouter[routerAddress]) {
                IHyperswapRouter01 router = IHyperswapRouter01(routerAddress);
                return router.addLiquidityFTM{value : amount.sub(swapValue)}(token, tokenAmount, 0, 0, recipient, block.timestamp);
            }
            else {
                IUniswapV2Router01 router = IUniswapV2Router01(routerAddress);
                return router.addLiquidityETH{value : amount.sub(swapValue)}(token, tokenAmount, 0, 0, recipient, block.timestamp);
            }
    }

    function _swapNativeToEqualTokensAndProvide(address token0, address token1, uint amount, address routerAddress, address recipient) private returns (uint, uint, uint) {
            uint swapValue = amount.div(2);
            uint token0Amount = _swapNativeForToken(token0, swapValue, address(this), routerAddress);
            uint token1Amount = _swapNativeForToken(token1, amount.sub(swapValue), address(this), routerAddress);
            _approveTokenIfNeeded(token0, routerAddress);
            _approveTokenIfNeeded(token1, routerAddress);
            IUniswapV2Router01 router = IUniswapV2Router01(routerAddress);
            return router.addLiquidity(token0, token1, token0Amount, token1Amount, 0, 0, recipient, block.timestamp);
    }

    function _swapNativeForToken(address token, uint value, address recipient, address routerAddr) private returns (uint) {
        address[] memory path;
        IUniswapV2Router01 router = IUniswapV2Router01(routerAddr);

        if (tokenBridgeForRouter[token][routerAddr] != address(0)) {
            path = new address[](3);
            path[0] = WNATIVE;
            path[1] = tokenBridgeForRouter[token][routerAddr];
            path[2] = token;
        } else {
            path = new address[](2);
            path[0] = WNATIVE;
            path[1] = token;
        }

        uint[] memory amounts = router.swapExactETHForTokens{value : value}(0, path, recipient, block.timestamp);
        return amounts[amounts.length - 1];
    }

    function _swapTokenForNative(address token, uint amount, address recipient, address routerAddr) private returns (uint) {
        address[] memory path;
        IUniswapV2Router01 router = IUniswapV2Router01(routerAddr);

        if (tokenBridgeForRouter[token][routerAddr] != address(0)) {
            path = new address[](3);
            path[0] = token;
            path[1] = tokenBridgeForRouter[token][routerAddr];
            path[2] = router.WETH();
        } else {
            path = new address[](2);
            path[0] = token;
            path[1] = router.WETH();
        }

        if (isFeeOnTransfer[token]) {
            router.swapExactTokensForETHSupportingFeeOnTransferTokens(amount, 0, path, recipient, block.timestamp);
            return IERC20(token).balanceOf(address(this));
        } else {
            uint[] memory amounts = router.swapExactTokensForETH(amount, 0, path, recipient, block.timestamp);
            return amounts[amounts.length - 1];
        }
    }

    function _swap(address _from, uint amount, address _to, address recipient, address routerAddr) private returns (uint) {
        IUniswapV2Router01 router = IUniswapV2Router01(routerAddr);

        address fromBridge = tokenBridgeForRouter[_from][routerAddr];
        address toBridge = tokenBridgeForRouter[_to][routerAddr];

        address[] memory path;

        if (fromBridge != address(0) && toBridge != address(0)) { // both have bridge
            if (fromBridge != toBridge) {
                path = new address[](5);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = toBridge;
                path[4] = _to;
            } else {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = _to;
            }
        } else if (fromBridge != address(0)) { // from has bridge
            if (fromBridge == _to) {
                path = new address[](2);
                path[0] = _from;
                path[1] = _to;
            }
            else if (_to == WNATIVE) {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
            } else {
                path = new address[](4);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = _to;
            }
        } else if (toBridge != address(0)) { // only _to ha a bridge, not _from
            if (_from == toBridge) {
                path = new address[](2);
                path[0] = _from;
                path[1] = _to;
            } else if (_from == WNATIVE) {
                path = new address[](3);
                path[0] = WNATIVE;
                path[1] = toBridge;
                path[2] = _to;
            }
            else {
                path = new address[](4);
                path[0] = _from;
                path[1] = WNATIVE;
                path[2] = toBridge;
                path[3] = _to;
            }
        } else if (_from == WNATIVE || _to == WNATIVE) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // Go through WNative
            path = new address[](3);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = _to;
        }

        uint[] memory amounts;

        if (isFeeOnTransfer[_from]) {
            router.swapExactTokensForTokensSupportingFeeOnTransferTokens(amount, 0, path, recipient, block.timestamp);
            return IERC20(_to).balanceOf(address(this));
        } else {
            amounts = router.swapExactTokensForTokens(amount, 0, path, recipient, block.timestamp);
        }

        return amounts[amounts.length - 1];
    }

    function _estimateSwap(address _from, uint amount, address _to, address routerAddr) private view returns (uint) {
        IUniswapV2Router01 router = IUniswapV2Router01(routerAddr);

        address fromBridge = tokenBridgeForRouter[_from][routerAddr];
        address toBridge = tokenBridgeForRouter[_to][routerAddr];

        address[] memory path;

        if (fromBridge != address(0) && toBridge != address(0)) {
            if (fromBridge != toBridge) {
                path = new address[](5);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = toBridge;
                path[4] = _to;
            } else {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = _to;
            }
        } else if (fromBridge != address(0)) {
            if (fromBridge == _to) {
                path = new address[](2);
                path[0] = _from;
                path[1] = _to;
            }
            else if (_to == WNATIVE) {
                path = new address[](3);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
            } else {
                path = new address[](4);
                path[0] = _from;
                path[1] = fromBridge;
                path[2] = WNATIVE;
                path[3] = _to;
            }
        } else if (toBridge != address(0)) {
            if (_from == toBridge) {
                path = new address[](2);
                path[0] = _from;
                path[1] = _to;
            } else if (_from == WNATIVE) {
                path = new address[](3);
                path[0] = WNATIVE;
                path[1] = toBridge;
                path[2] = _to;
            }
            else {
                path = new address[](4);
                path[0] = _from;
                path[1] = WNATIVE;
                path[2] = toBridge;
                path[3] = _to;
            }
        } else if (_from == WNATIVE || _to == WNATIVE) {
            path = new address[](2);
            path[0] = _from;
            path[1] = _to;
        } else {
            // Go through WNative
            path = new address[](3);
            path[0] = _from;
            path[1] = WNATIVE;
            path[2] = _to;
        }

        uint[] memory amounts = router.getAmountsOut(amount, path);
        return amounts[amounts.length - 1];
    }


    /* ========== RESTRICTED FUNCTIONS ========== */

    function setTokenBridgeForRouter(address token, address router, address bridgeToken) external onlyOwner {
       tokenBridgeForRouter[token][router] = bridgeToken;
    }

    function withdraw(address token) external onlyOwner {
        if (token == address(0)) {
            payable(owner()).transfer(address(this).balance);
            return;
        }

        IERC20(token).transfer(owner(), IERC20(token).balanceOf(address(this)));
    }

    function setUseNativeRouter(address router) external onlyOwner {
        useNativeRouter[router] = true;
    }

    function setIsFeeOnTransfer(address token) external onlyOwner {
        isFeeOnTransfer[token] = true;
    }
}

contract Treasury is ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========= CONSTANT VARIABLES ======== */

    uint256 public constant PERIOD = 6 hours;

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    // epoch
    uint256 public startTime;
    uint256 public epoch = 0;
    uint256 public epochSupplyContractionLeft = 0;

    // exclusions from total supply
    address[] public excludedFromTotalSupply = [
        address(0xEDf83B9939B83cDff224cD093F71bB772c76A603), // BnbGenesisPool
        address(0xBB4b88B836180177c50b69B5343FBBAA59b028E9), // CakeGenesisPool
        address(0xe9aBF38253C6BC768e68B0b311515258B0C6D4C2), // BananaGenesisPool
        address(0xA6B536e578a159c78b216135B1b417a634EA3a01)  // NftartGenesisPool
    ];

    // core components
    address public dibs;
    address public dbond;
    address public dshare;

    address public piggybank;
    address public dibsOracle;

    // price
    uint256 public dibsPriceOne;
    uint256 public dibsPriceCeiling;

    uint256 public seigniorageSaved;

    uint256[] public supplyTiers;
    uint256[] public maxExpansionTiers;

    uint256 public maxSupplyExpansionPercent;
    uint256 public bondDepletionFloorPercent;
    uint256 public seigniorageExpansionFloorPercent;
    uint256 public maxSupplyContractionPercent;
    uint256 public maxDebtRatioPercent;

    // 28 first epochs (1 week) with 3% expansion regardless of DIBS price
    uint256 public bootstrapEpochs;
    uint256 public bootstrapSupplyExpansionPercent;

    /* =================== Added variables =================== */
    uint256 public previousEpochDibsPrice;
    uint256 public maxDiscountRate; // when purchasing bond
    uint256 public maxPremiumRate; // when redeeming bond
    uint256 public discountPercent;
    uint256 public premiumThreshold;
    uint256 public premiumPercent;
    uint256 public mintingFactorForPayingDebt; // print extra DIBS during debt phase

    address public daoFund;
    uint256 public daoFundSharedPercent;

    address public devFund;
    uint256 public devFundSharedPercent;

    /* =================== Events =================== */

    event Initialized(address indexed executor, uint256 at);
    event BurnedBonds(address indexed from, uint256 bondAmount);
    event RedeemedBonds(address indexed from, uint256 dibsAmount, uint256 bondAmount);
    event BoughtBonds(address indexed from, uint256 dibsAmount, uint256 bondAmount);
    event TreasuryFunded(uint256 timestamp, uint256 seigniorage);
    event PiggybankFunded(uint256 timestamp, uint256 seigniorage);
    event DaoFundFunded(uint256 timestamp, uint256 seigniorage);
    event DevFundFunded(uint256 timestamp, uint256 seigniorage);

    /* =================== Modifier =================== */

    modifier onlyOperator() {
        require(operator == msg.sender, "Treasury: caller is not the operator");
        _;
    }

    modifier checkCondition() {
        require(now >= startTime, "Treasury: not started yet");

        _;
    }

    modifier checkEpoch() {
        require(now >= nextEpochPoint(), "Treasury: not opened yet");

        _;

        epoch = epoch.add(1);
        epochSupplyContractionLeft = (getDibsPrice() > dibsPriceCeiling) ? 0 : getDibsCirculatingSupply().mul(maxSupplyContractionPercent).div(10000);
    }

    modifier checkOperator() {
        require(
            IBasisAsset(dibs).operator() == address(this) &&
                IBasisAsset(dbond).operator() == address(this) &&
                IBasisAsset(dshare).operator() == address(this) &&
                Operator(piggybank).operator() == address(this),
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
    function getDibsPrice() public view returns (uint256 dibsPrice) {
        try IOracle(dibsOracle).consult(dibs, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DIBS price from the oracle");
        }
    }

    function getDibsUpdatedPrice() public view returns (uint256 _dibsPrice) {
        try IOracle(dibsOracle).twap(dibs, 1e18) returns (uint144 price) {
            return uint256(price);
        } catch {
            revert("Treasury: failed to consult DIBS price from the oracle");
        }
    }

    // budget
    function getReserve() public view returns (uint256) {
        return seigniorageSaved;
    }

    function getBurnableDibsLeft() public view returns (uint256 _burnableDibsLeft) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice <= dibsPriceOne) {
            uint256 _dibsSupply = getDibsCirculatingSupply();
            uint256 _bondMaxSupply = _dibsSupply.mul(maxDebtRatioPercent).div(10000);
            uint256 _bondSupply = IERC20(dbond).totalSupply();
            if (_bondMaxSupply > _bondSupply) {
                uint256 _maxMintableBond = _bondMaxSupply.sub(_bondSupply);
                uint256 _maxBurnableDibs = _maxMintableBond.mul(_dibsPrice).div(1e15);
                _burnableDibsLeft = Math.min(epochSupplyContractionLeft, _maxBurnableDibs);
            }
        }
    }

    function getRedeemableBonds() public view returns (uint256 _redeemableBonds) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice > dibsPriceCeiling) {
            uint256 _totalDibs = IERC20(dibs).balanceOf(address(this));
            uint256 _rate = getBondPremiumRate();
            if (_rate > 0) {
                _redeemableBonds = _totalDibs.mul(1e15).div(_rate);
            }
        }
    }

    function getBondDiscountRate() public view returns (uint256 _rate) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice <= dibsPriceOne) {
            if (discountPercent == 0) {
                // no discount
                _rate = dibsPriceOne;
            } else {
                uint256 _bondAmount = dibsPriceOne.mul(1e18).div(_dibsPrice); // to burn 1 DIBS
                uint256 _discountAmount = _bondAmount.sub(dibsPriceOne).mul(discountPercent).div(10000);
                _rate = dibsPriceOne.add(_discountAmount);
                if (maxDiscountRate > 0 && _rate > maxDiscountRate) {
                    _rate = maxDiscountRate;
                }
            }
        }
    }

    function getBondPremiumRate() public view returns (uint256 _rate) {
        uint256 _dibsPrice = getDibsPrice();
        if (_dibsPrice > dibsPriceCeiling) {
            uint256 _dibsPricePremiumThreshold = dibsPriceOne.mul(premiumThreshold).div(100);
            if (_dibsPrice >= _dibsPricePremiumThreshold) {
                //Price > 1.10
                uint256 _premiumAmount = _dibsPrice.sub(dibsPriceOne).mul(premiumPercent).div(10000);
                _rate = dibsPriceOne.add(_premiumAmount);
                if (maxPremiumRate > 0 && _rate > maxPremiumRate) {
                    _rate = maxPremiumRate;
                }
            } else {
                // no premium bonus
                _rate = dibsPriceOne;
            }
        }
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        address _dibs,
        address _dbond,
        address _dshare,
        address _dibsOracle,
        address _piggybank,
        uint256 _startTime
    ) public notInitialized {
        dibs = _dibs;
        dbond = _dbond;
        dshare = _dshare;
        dibsOracle = _dibsOracle;
        piggybank = _piggybank;
        startTime = _startTime;

        dibsPriceOne = 10**15; // This is to allow a PEG of 1,000 DIBS per BNB
        dibsPriceCeiling = dibsPriceOne.mul(101).div(100);

        // Dynamic max expansion percent
        supplyTiers = [0 ether, 500_000 ether, 2_000_000 ether, 4_000_000 ether, 8_000_000 ether, 20_000_000 ether];
        maxExpansionTiers = [300, 250, 200, 150, 125, 100];

        maxSupplyExpansionPercent = 400; // Upto 4.0% supply for expansion

        bondDepletionFloorPercent = 10000; // 100% of Bond supply for depletion floor
        seigniorageExpansionFloorPercent = 3500; // At least 35% of expansion reserved for piggybank
        maxSupplyContractionPercent = 300; // Upto 3.0% supply for contraction (to burn DIBS and mint tBOND)
        maxDebtRatioPercent = 4500; // Upto 45% supply of tBOND to purchase

        premiumThreshold = 110;
        premiumPercent = 7000;

        // First 28 epochs with 3% expansion
        bootstrapEpochs = 0;
        bootstrapSupplyExpansionPercent = 300;

        // set seigniorageSaved to it's balance
        seigniorageSaved = IERC20(dibs).balanceOf(address(this));

        initialized = true;
        operator = msg.sender;
        emit Initialized(msg.sender, block.number);
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function setPiggybank(address _piggybank) external onlyOperator {
        piggybank = _piggybank;
    }

    function setDibsOracle(address _dibsOracle) external onlyOperator {
        dibsOracle = _dibsOracle;
    }

    function setDibsPriceCeiling(uint256 _dibsPriceCeiling) external onlyOperator {
        require(_dibsPriceCeiling >= dibsPriceOne && _dibsPriceCeiling <= dibsPriceOne.mul(120).div(100), "out of range"); // [$1.0, $1.2]
        dibsPriceCeiling = _dibsPriceCeiling;
    }

    function setMaxSupplyExpansionPercents(uint256 _maxSupplyExpansionPercent) external onlyOperator {
        require(_maxSupplyExpansionPercent >= 10 && _maxSupplyExpansionPercent <= 1000, "_maxSupplyExpansionPercent: out of range"); // [0.1%, 10%]
        maxSupplyExpansionPercent = _maxSupplyExpansionPercent;
    }

    function setSupplyTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < supplyTiers.length, "Index has to be lower than count of tiers");
        if (_index > 0) {
            require(_value > supplyTiers[_index - 1]);
        }
        if (_index < supplyTiers.length - 1) {
            require(_value < supplyTiers[_index + 1]);
        }
        supplyTiers[_index] = _value;
        return true;
    }

    function setMaxExpansionTiersEntry(uint8 _index, uint256 _value) external onlyOperator returns (bool) {
        require(_index >= 0, "Index has to be higher than 0");
        require(_index < maxExpansionTiers.length, "Index has to be lower than count of tiers");
        require(_value >= 10 && _value <= 1000, "_value: out of range"); // [0.1%, 10%]
        maxExpansionTiers[_index] = _value;
        return true;
    }

    function setBondDepletionFloorPercent(uint256 _bondDepletionFloorPercent) external onlyOperator {
        require(_bondDepletionFloorPercent >= 500 && _bondDepletionFloorPercent <= 10000, "out of range"); // [5%, 100%]
        bondDepletionFloorPercent = _bondDepletionFloorPercent;
    }

    function setMaxSupplyContractionPercent(uint256 _maxSupplyContractionPercent) external onlyOperator {
        require(_maxSupplyContractionPercent >= 100 && _maxSupplyContractionPercent <= 1500, "out of range"); // [0.1%, 15%]
        maxSupplyContractionPercent = _maxSupplyContractionPercent;
    }

    function setMaxDebtRatioPercent(uint256 _maxDebtRatioPercent) external onlyOperator {
        require(_maxDebtRatioPercent >= 1000 && _maxDebtRatioPercent <= 10000, "out of range"); // [10%, 100%]
        maxDebtRatioPercent = _maxDebtRatioPercent;
    }

    function setBootstrap(uint256 _bootstrapEpochs, uint256 _bootstrapSupplyExpansionPercent) external onlyOperator {
        require(_bootstrapEpochs <= 120, "_bootstrapEpochs: out of range"); // <= 1 month
        require(_bootstrapSupplyExpansionPercent >= 100 && _bootstrapSupplyExpansionPercent <= 1000, "_bootstrapSupplyExpansionPercent: out of range"); // [1%, 10%]
        bootstrapEpochs = _bootstrapEpochs;
        bootstrapSupplyExpansionPercent = _bootstrapSupplyExpansionPercent;
    }

    function setExtraFunds(
        address _daoFund,
        uint256 _daoFundSharedPercent,
        address _devFund,
        uint256 _devFundSharedPercent
    ) external onlyOperator {
        require(_daoFund != address(0), "zero");
        require(_daoFundSharedPercent <= 3000, "out of range"); // <= 30%
        require(_devFund != address(0), "zero");
        require(_devFundSharedPercent <= 1000, "out of range"); // <= 10%
        daoFund = _daoFund;
        daoFundSharedPercent = _daoFundSharedPercent;
        devFund = _devFund;
        devFundSharedPercent = _devFundSharedPercent;
    }

    function setMaxDiscountRate(uint256 _maxDiscountRate) external onlyOperator {
        maxDiscountRate = _maxDiscountRate;
    }

    function setMaxPremiumRate(uint256 _maxPremiumRate) external onlyOperator {
        maxPremiumRate = _maxPremiumRate;
    }

    function setDiscountPercent(uint256 _discountPercent) external onlyOperator {
        require(_discountPercent <= 20000, "_discountPercent is over 200%");
        discountPercent = _discountPercent;
    }

    function setPremiumThreshold(uint256 _premiumThreshold) external onlyOperator {
        require(_premiumThreshold >= dibsPriceCeiling, "_premiumThreshold exceeds dibsPriceCeiling");
        require(_premiumThreshold <= 150, "_premiumThreshold is higher than 1.5");
        premiumThreshold = _premiumThreshold;
    }

    function setPremiumPercent(uint256 _premiumPercent) external onlyOperator {
        require(_premiumPercent <= 20000, "_premiumPercent is over 200%");
        premiumPercent = _premiumPercent;
    }

    function setMintingFactorForPayingDebt(uint256 _mintingFactorForPayingDebt) external onlyOperator {
        require(_mintingFactorForPayingDebt >= 10000 && _mintingFactorForPayingDebt <= 20000, "_mintingFactorForPayingDebt: out of range"); // [100%, 200%]
        mintingFactorForPayingDebt = _mintingFactorForPayingDebt;
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    function _updateDibsPrice() internal {
        try IOracle(dibsOracle).update() {} catch {}
    }

    function getDibsCirculatingSupply() public view returns (uint256) {
        IERC20 dibsErc20 = IERC20(dibs);
        uint256 totalSupply = dibsErc20.totalSupply();
        uint256 balanceExcluded = 0;
        for (uint8 entryId = 0; entryId < excludedFromTotalSupply.length; ++entryId) {
            balanceExcluded = balanceExcluded.add(dibsErc20.balanceOf(excludedFromTotalSupply[entryId]));
        }
        return totalSupply.sub(balanceExcluded);
    }

    function buyBonds(uint256 _dibsAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_dibsAmount > 0, "Treasury: cannot purchase bonds with zero amount");

        uint256 dibsPrice = getDibsPrice();
        require(dibsPrice == targetPrice, "Treasury: DIBS price moved");
        require(
            dibsPrice < dibsPriceOne, // price < $1
            "Treasury: dibsPrice not eligible for bond purchase"
        );

        require(_dibsAmount <= epochSupplyContractionLeft, "Treasury: not enough bond left to purchase");

        uint256 _rate = getBondDiscountRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _bondAmount = _dibsAmount.mul(_rate).div(1e15);
        uint256 dibsSupply = getDibsCirculatingSupply();
        uint256 newBondSupply = IERC20(dbond).totalSupply().add(_bondAmount);
        require(newBondSupply <= dibsSupply.mul(maxDebtRatioPercent).div(10000), "over max debt ratio");

        IBasisAsset(dibs).burnFrom(msg.sender, _dibsAmount);
        IBasisAsset(dbond).mint(msg.sender, _bondAmount);

        epochSupplyContractionLeft = epochSupplyContractionLeft.sub(_dibsAmount);
        _updateDibsPrice();

        emit BoughtBonds(msg.sender, _dibsAmount, _bondAmount);
    }

    function redeemBonds(uint256 _bondAmount, uint256 targetPrice) external onlyOneBlock checkCondition checkOperator {
        require(_bondAmount > 0, "Treasury: cannot redeem bonds with zero amount");

        uint256 dibsPrice = getDibsPrice();
        require(dibsPrice == targetPrice, "Treasury: DIBS price moved");
        require(
            dibsPrice > dibsPriceCeiling, // price > $1.01
            "Treasury: dibsPrice not eligible for bond purchase"
        );

        uint256 _rate = getBondPremiumRate();
        require(_rate > 0, "Treasury: invalid bond rate");

        uint256 _dibsAmount = _bondAmount.mul(_rate).div(1e15);
        require(IERC20(dibs).balanceOf(address(this)) >= _dibsAmount, "Treasury: treasury has no more budget");

        seigniorageSaved = seigniorageSaved.sub(Math.min(seigniorageSaved, _dibsAmount));

        IBasisAsset(dbond).burnFrom(msg.sender, _bondAmount);
        IERC20(dibs).safeTransfer(msg.sender, _dibsAmount);

        _updateDibsPrice();

        emit RedeemedBonds(msg.sender, _dibsAmount, _bondAmount);
    }

    function _sendToPiggybank(uint256 _amount) internal {
        IBasisAsset(dibs).mint(address(this), _amount);

        uint256 _daoFundSharedAmount = 0;
        if (daoFundSharedPercent > 0) {
            _daoFundSharedAmount = _amount.mul(daoFundSharedPercent).div(10000);
            IERC20(dibs).transfer(daoFund, _daoFundSharedAmount);
            emit DaoFundFunded(now, _daoFundSharedAmount);
        }

        uint256 _devFundSharedAmount = 0;
        if (devFundSharedPercent > 0) {
            _devFundSharedAmount = _amount.mul(devFundSharedPercent).div(10000);
            IERC20(dibs).transfer(devFund, _devFundSharedAmount);
            emit DevFundFunded(now, _devFundSharedAmount);
        }

        _amount = _amount.sub(_daoFundSharedAmount).sub(_devFundSharedAmount);

        IERC20(dibs).safeApprove(piggybank, 0);
        IERC20(dibs).safeApprove(piggybank, _amount);
        IPiggybank(piggybank).allocateSeigniorage(_amount);
        emit PiggybankFunded(now, _amount);
    }

    function _calculateMaxSupplyExpansionPercent(uint256 _dibsSupply) internal returns (uint256) {
        for (uint8 tierId = uint8(supplyTiers.length - 1); tierId >= 0; --tierId) {
            if (_dibsSupply >= supplyTiers[tierId]) {
                maxSupplyExpansionPercent = maxExpansionTiers[tierId];
                break;
            }
        }
        return maxSupplyExpansionPercent;
    }

    function allocateSeigniorage() external onlyOneBlock checkCondition checkEpoch checkOperator {
        _updateDibsPrice();
        previousEpochDibsPrice = getDibsPrice();
        uint256 dibsSupply = getDibsCirculatingSupply().sub(seigniorageSaved);
        if (epoch < bootstrapEpochs) {
            // 28 first epochs with 3% expansion
            _sendToPiggybank(dibsSupply.mul(bootstrapSupplyExpansionPercent).div(10000));
        } else {
            if (previousEpochDibsPrice > dibsPriceCeiling) {
                // Expansion ($DIBS Price > 1 $BNB): there is some seigniorage to be allocated
                uint256 bondSupply = IERC20(dbond).totalSupply();
                uint256 _percentage = previousEpochDibsPrice.sub(dibsPriceOne);
                uint256 _savedForBond;
                uint256 _savedForPiggybank;
                uint256 _mse = _calculateMaxSupplyExpansionPercent(dibsSupply).mul(1e14);
                if (_percentage > _mse) {
                    _percentage = _mse;
                }
                if (seigniorageSaved >= bondSupply.mul(bondDepletionFloorPercent).div(10000)) {
                    // saved enough to pay debt, mint as usual rate
                    _savedForPiggybank = dibsSupply.mul(_percentage).div(1e18);
                } else {
                    // have not saved enough to pay debt, mint more
                    uint256 _seigniorage = dibsSupply.mul(_percentage).div(1e18);
                    _savedForPiggybank = _seigniorage.mul(seigniorageExpansionFloorPercent).div(10000);
                    _savedForBond = _seigniorage.sub(_savedForPiggybank);
                    if (mintingFactorForPayingDebt > 0) {
                        _savedForBond = _savedForBond.mul(mintingFactorForPayingDebt).div(10000);
                    }
                }
                if (_savedForPiggybank > 0) {
                    _sendToPiggybank(_savedForPiggybank);
                }
                if (_savedForBond > 0) {
                    seigniorageSaved = seigniorageSaved.add(_savedForBond);
                    IBasisAsset(dibs).mint(address(this), _savedForBond);
                    emit TreasuryFunded(now, _savedForBond);
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
        require(address(_token) != address(dibs), "dibs");
        require(address(_token) != address(dbond), "bond");
        require(address(_token) != address(dshare), "share");
        _token.safeTransfer(_to, _amount);
    }

    function piggybankSetOperator(address _operator) external onlyOperator {
        IPiggybank(piggybank).setOperator(_operator);
    }

    function piggybankSetLockUp(uint256 _withdrawLockupEpochs, uint256 _rewardLockupEpochs) external onlyOperator {
        IPiggybank(piggybank).setLockUp(_withdrawLockupEpochs, _rewardLockupEpochs);
    }

    function piggybankAllocateSeigniorage(uint256 amount) external onlyOperator {
        IPiggybank(piggybank).allocateSeigniorage(amount);
    }

    function piggybankGovernanceRecoverUnsupported(
        address _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        IPiggybank(piggybank).governanceRecoverUnsupported(_token, _amount, _to);
    }
}

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
        require(memberShare >= amount, "Piggybank: withdraw request greater than staked amount");
        _totalSupply = _totalSupply.sub(amount);
        _balances[msg.sender] = memberShare.sub(amount);
        share.safeTransfer(msg.sender, amount);
    }
}

contract Piggybank is ShareWrapper, ContractGuard {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    /* ========== DATA STRUCTURES ========== */

    struct Memberseat {
        uint256 lastSnapshotIndex;
        uint256 rewardEarned;
        uint256 epochTimerStart;
    }

    struct PiggybankSnapshot {
        uint256 time;
        uint256 rewardReceived;
        uint256 rewardPerShare;
    }

    /* ========== STATE VARIABLES ========== */

    // governance
    address public operator;

    // flags
    bool public initialized = false;

    IERC20 public dibs;
    ITreasury public treasury;

    mapping(address => Memberseat) public members;
    PiggybankSnapshot[] public piggybankHistory;

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
        require(operator == msg.sender, "Piggybank: caller is not the operator");
        _;
    }

    modifier memberExists() {
        require(balanceOf(msg.sender) > 0, "Piggybank: The member does not exist");
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
        require(!initialized, "Piggybank: already initialized");
        _;
    }

    /* ========== GOVERNANCE ========== */

    function initialize(
        IERC20 _dibs,
        IERC20 _share,
        ITreasury _treasury
    ) public notInitialized {
        dibs = _dibs;
        share = _share;
        treasury = _treasury;

        PiggybankSnapshot memory genesisSnapshot = PiggybankSnapshot({time: block.number, rewardReceived: 0, rewardPerShare: 0});
        piggybankHistory.push(genesisSnapshot);

        withdrawLockupEpochs = 6; // Lock for 6 epochs (36h) before release withdraw
        rewardLockupEpochs = 3; // Lock for 3 epochs (18h) before release claimReward

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
        return piggybankHistory.length.sub(1);
    }

    function getLatestSnapshot() internal view returns (PiggybankSnapshot memory) {
        return piggybankHistory[latestSnapshotIndex()];
    }

    function getLastSnapshotIndexOf(address member) public view returns (uint256) {
        return members[member].lastSnapshotIndex;
    }

    function getLastSnapshotOf(address member) internal view returns (PiggybankSnapshot memory) {
        return piggybankHistory[getLastSnapshotIndexOf(member)];
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

    function getDibsPrice() external view returns (uint256) {
        return treasury.getDibsPrice();
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
        require(amount > 0, "Piggybank: Cannot stake 0");
        super.stake(amount);
        members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
        emit Staked(msg.sender, amount);
    }

    function withdraw(uint256 amount) public override onlyOneBlock memberExists updateReward(msg.sender) {
        require(amount > 0, "Piggybank: Cannot withdraw 0");
        require(members[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <= treasury.epoch(), "Piggybank: still in withdraw lockup");
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
            require(members[msg.sender].epochTimerStart.add(rewardLockupEpochs) <= treasury.epoch(), "Piggybank: still in reward lockup");
            members[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
            members[msg.sender].rewardEarned = 0;
            dibs.safeTransfer(msg.sender, reward);
            emit RewardPaid(msg.sender, reward);
        }
    }

    function allocateSeigniorage(uint256 amount) external onlyOneBlock onlyOperator {
        require(amount > 0, "Piggybank: Cannot allocate 0");
        require(totalSupply() > 0, "Piggybank: Cannot allocate when totalSupply is 0");

        // Create & add new snapshot
        uint256 prevRPS = getLatestSnapshot().rewardPerShare;
        uint256 nextRPS = prevRPS.add(amount.mul(1e18).div(totalSupply()));

        PiggybankSnapshot memory newSnapshot = PiggybankSnapshot({time: block.number, rewardReceived: amount, rewardPerShare: nextRPS});
        piggybankHistory.push(newSnapshot);

        dibs.safeTransferFrom(msg.sender, address(this), amount);
        emit RewardAdded(msg.sender, amount);
    }

    function governanceRecoverUnsupported(
        IERC20 _token,
        uint256 _amount,
        address _to
    ) external onlyOperator {
        // do not allow to drain core tokens
        require(address(_token) != address(dibs), "dibs");
        require(address(_token) != address(share), "share");
        _token.safeTransfer(_to, _amount);
    }
}

contract Oracle is Epoch {
    using FixedPoint for *;
    using SafeMath for uint256;

    /* ========== STATE VARIABLES ========== */

    // uniswap
    address public token0;
    address public token1;
    IUniswapV2Pair public pair;

    // oracle
    uint32 public blockTimestampLast;
    uint256 public price0CumulativeLast;
    uint256 public price1CumulativeLast;
    FixedPoint.uq112x112 public price0Average;
    FixedPoint.uq112x112 public price1Average;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        IUniswapV2Pair _pair,
        uint256 _period,
        uint256 _startTime
    ) public Epoch(_period, _startTime, 0) {
        pair = _pair;
        token0 = pair.token0();
        token1 = pair.token1();
        price0CumulativeLast = pair.price0CumulativeLast(); // fetch the current accumulated price value (1 / 0)
        price1CumulativeLast = pair.price1CumulativeLast(); // fetch the current accumulated price value (0 / 1)
        uint112 reserve0;
        uint112 reserve1;
        (reserve0, reserve1, blockTimestampLast) = pair.getReserves();
        require(reserve0 != 0 && reserve1 != 0, "Oracle: NO_RESERVES"); // ensure that there's liquidity in the pair
    }

    /* ========== MUTABLE FUNCTIONS ========== */

    /** @dev Updates 1-day EMA price from Uniswap.  */
    function update() external checkEpoch {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed == 0) {
            // prevent divided by zero
            return;
        }

        // overflow is desired, casting never truncates
        // cumulative price is in (uq112x112 price * seconds) units so we simply wrap it after division by time elapsed
        price0Average = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed));
        price1Average = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed));

        price0CumulativeLast = price0Cumulative;
        price1CumulativeLast = price1Cumulative;
        blockTimestampLast = blockTimestamp;

        emit Updated(price0Cumulative, price1Cumulative);
    }

    // note this will always return 0 before update has been called successfully for the first time.
    function consult(address _token, uint256 _amountIn) external view returns (uint144 amountOut) {
        if (_token == token0) {
            amountOut = price0Average.mul(_amountIn).decode144();
        } else {
            require(_token == token1, "Oracle: INVALID_TOKEN");
            amountOut = price1Average.mul(_amountIn).decode144();
        }
    }

    function twap(address _token, uint256 _amountIn) external view returns (uint144 _amountOut) {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) = UniswapV2OracleLibrary.currentCumulativePrices(address(pair));
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired
        if (_token == token0) {
            _amountOut = FixedPoint.uq112x112(uint224((price0Cumulative - price0CumulativeLast) / timeElapsed)).mul(_amountIn).decode144();
        } else if (_token == token1) {
            _amountOut = FixedPoint.uq112x112(uint224((price1Cumulative - price1CumulativeLast) / timeElapsed)).mul(_amountIn).decode144();
        }
    }

    event Updated(uint256 price0CumulativeLast, uint256 price1CumulativeLast);
}
contract DShare is ERC20Burnable, Operator {
    using SafeMath for uint256;

    /*
        TOTAL MAX SUPPLY = 70,000 dSHAREs
        - 36000 dShares allocated to Dibs-BNB
        - 24000 dShares allocated to dShare-BNB
        - Airdop 500 dShares allocated to DAO wallet
        - Allocate 4500 dShares to DAO wallet for linear vesting
        - Airdrop 360 dShares to Dev wallet
        - Allocate 4640 dShares to Dev wallet for linear vesting
    */
    uint256 public constant FARMING_POOL_REWARD_ALLOCATION = 60000 ether;
    uint256 public constant COMMUNITY_FUND_POOL_ALLOCATION = 4500 ether;
    uint256 public constant DEV_FUND_POOL_ALLOCATION = 4640 ether;

    uint256 public constant VESTING_DURATION = 365 days;
    uint256 public startTime;
    uint256 public endTime;

    uint256 public communityFundRewardRate;
    uint256 public devFundRewardRate;

    address public communityFund;
    address public devFund;

    uint256 public communityFundLastClaimed;
    uint256 public devFundLastClaimed;

    bool public rewardPoolDistributed = false;

    constructor(uint256 _startTime, address _daoFund, address _devFund) public ERC20("DSHARE", "DSHARE") {
        _mint(msg.sender, 2 ether);         // mint 2 DIBS Share for initial pools deployment and Piggybank initialization
        _mint(_daoFund, 500 ether);         // Airdop 500 Dshares allocated to DAO wallet
        _mint(_devFund, 358 ether);         // Airdop 358 Dshares allocated to DEV wallet + 2 dShare for initialization

        startTime = _startTime;
        endTime = startTime + VESTING_DURATION;

        communityFundLastClaimed = startTime;
        devFundLastClaimed = startTime;

        communityFundRewardRate = COMMUNITY_FUND_POOL_ALLOCATION.div(VESTING_DURATION);
        devFundRewardRate = DEV_FUND_POOL_ALLOCATION.div(VESTING_DURATION);

        require(_devFund != address(0), "Address cannot be 0");
        devFund = _devFund;

        require(_daoFund != address(0), "Address cannot be 0");
        communityFund = _daoFund;
    }

    function setTreasuryFund(address _daoFund) external {
        require(msg.sender == devFund, "!dev");
        communityFund = _daoFund;
    }

    function setDevFund(address _devFund) external {
        require(msg.sender == devFund, "!dev");
        require(_devFund != address(0), "zero");
        devFund = _devFund;
    }

    function unclaimedTreasuryFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (communityFundLastClaimed >= _now) return 0;
        _pending = _now.sub(communityFundLastClaimed).mul(communityFundRewardRate);
    }

    function unclaimedDevFund() public view returns (uint256 _pending) {
        uint256 _now = block.timestamp;
        if (_now > endTime) _now = endTime;
        if (devFundLastClaimed >= _now) return 0;
        _pending = _now.sub(devFundLastClaimed).mul(devFundRewardRate);
    }

    /**
     * @dev Claim pending rewards to community and dev fund
     */
    function claimRewards() external {
        uint256 _pending = unclaimedTreasuryFund();
        if (_pending > 0 && communityFund != address(0)) {
            _mint(communityFund, _pending);
            communityFundLastClaimed = block.timestamp;
        }
        _pending = unclaimedDevFund();
        if (_pending > 0 && devFund != address(0)) {
            _mint(devFund, _pending);
            devFundLastClaimed = block.timestamp;
        }
    }

    /**
     * @notice distribute to reward pool (only once)
     */
    function distributeReward(address _farmingIncentiveFund) external onlyOperator {
        require(!rewardPoolDistributed, "only can distribute once");
        require(_farmingIncentiveFund != address(0), "!_farmingIncentiveFund");
        rewardPoolDistributed = true;
        _mint(_farmingIncentiveFund, FARMING_POOL_REWARD_ALLOCATION);
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
}
pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";

// Note that this pool has no minter key of dSHARE (rewards).
// Instead, the governance will call dSHARE distributeReward method and send reward to this pool at the beginning.
contract DShareRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. dSHAREs to distribute per block.
        uint256 lastRewardTime; // Last time that dSHAREs distribution occurs.
        uint256 accDSharePerShare; // Accumulated dSHAREs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    IERC20 public dshare;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when dSHARE mining starts.
    uint256 public poolStartTime;

    // The time when dSHARE mining ends.
    uint256 public poolEndTime;

    uint256 public dSharePerSecond; // 60000 dshare / 365 days
    uint256 public runningTime = 365 days; // 365 days
    uint256 public constant TOTAL_REWARDS = 60000 ether;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(
        address _dshare,
        uint256 _poolStartTime
    ) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_dshare != address(0)) dshare = IERC20(_dshare);
        dSharePerSecond = TOTAL_REWARDS.div(runningTime);
        poolStartTime = _poolStartTime;
        poolEndTime = poolStartTime + runningTime;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "DShareRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "DShareRewardPool: existing pool?");
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
            accDSharePerShare : 0,
            isStarted : _isStarted
            }));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's dSHARE allocation point. Can only be called by the owner.
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
            if (_fromTime <= poolStartTime) return poolEndTime.sub(poolStartTime).mul(dSharePerSecond);
            return poolEndTime.sub(_fromTime).mul(dSharePerSecond);
        } else {
            if (_toTime <= poolStartTime) return 0;
            if (_fromTime <= poolStartTime) return _toTime.sub(poolStartTime).mul(dSharePerSecond);
            return _toTime.sub(_fromTime).mul(dSharePerSecond);
        }
    }

    // View function to see pending dSHAREs on frontend.
    function pendingShare(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDSharePerShare = pool.accDSharePerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _dshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accDSharePerShare = accDSharePerShare.add(_dshareReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accDSharePerShare).div(1e18).sub(user.rewardDebt);
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
            uint256 _dshareReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accDSharePerShare = pool.accDSharePerShare.add(_dshareReward.mul(1e18).div(tokenSupply));
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
            uint256 _pending = user.amount.mul(pool.accDSharePerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeDShareTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDSharePerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accDSharePerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeDShareTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDSharePerShare).div(1e18);
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

    // Safe dshare transfer function, just in case if rounding error causes pool to not have enough dSHAREs.
    function safeDShareTransfer(address _to, uint256 _amount) internal {
        uint256 _dshareBal = dshare.balanceOf(address(this));
        if (_dshareBal > 0) {
            if (_amount > _dshareBal) {
                dshare.safeTransfer(_to, _dshareBal);
            } else {
                dshare.safeTransfer(_to, _amount);
            }
        }
    }

    function setOperator(address _operator) external onlyOperator {
        operator = _operator;
    }

    function governanceRecoverUnsupported(IERC20 _token, uint256 amount, address to) external onlyOperator {
        if (block.timestamp < poolEndTime + 30 days) {
            // do not allow to drain core token (dSHARE or lps) if less than 30 days after pool ends
            require(_token != dshare, "dshare");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}
contract DibsRewardPool {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // governance
    address public operator;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
    }

    // Info of each pool.
    struct PoolInfo {
        IERC20 token; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. DIBSs to distribute in the pool.
        uint256 lastRewardTime; // Last time that DIBSs distribution occurred.
        uint256 accDibsPerShare; // Accumulated DIBSs per share, times 1e18. See below.
        bool isStarted; // if lastRewardTime has passed
    }

    IERC20 public dibs;

    // Info of each pool.
    PoolInfo[] public poolInfo;

    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;

    // The time when DIBS mining starts.
    uint256 public poolStartTime;

    uint256[] public epochTotalRewards = [80000 ether, 60000 ether];

    // Time when each epoch ends.
    uint256[3] public epochEndTimes;

    // Reward per second for each of 2 epochs (last item is equal to 0 - for sanity).
    uint256[3] public epochDibsPerSecond;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event RewardPaid(address indexed user, uint256 amount);

    constructor(address _dibs, uint256 _poolStartTime) public {
        require(block.timestamp < _poolStartTime, "late");
        if (_dibs != address(0)) dibs = IERC20(_dibs);

        poolStartTime = _poolStartTime;

        epochEndTimes[0] = poolStartTime + 4 days; // Day 2-5
        epochEndTimes[1] = epochEndTimes[0] + 5 days; // Day 6-10

        epochDibsPerSecond[0] = epochTotalRewards[0].div(4 days);
        epochDibsPerSecond[1] = epochTotalRewards[1].div(5 days);

        epochDibsPerSecond[2] = 0;
        operator = msg.sender;
    }

    modifier onlyOperator() {
        require(operator == msg.sender, "DibsRewardPool: caller is not the operator");
        _;
    }

    function checkPoolDuplicate(IERC20 _token) internal view {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            require(poolInfo[pid].token != _token, "DibsRewardPool: existing pool?");
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
        poolInfo.push(PoolInfo({token: _token, allocPoint: _allocPoint, lastRewardTime: _lastRewardTime, accDibsPerShare: 0, isStarted: _isStarted}));
        if (_isStarted) {
            totalAllocPoint = totalAllocPoint.add(_allocPoint);
        }
    }

    // Update the given pool's DIBS allocation point. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint) public onlyOperator {
        massUpdatePools();
        PoolInfo storage pool = poolInfo[_pid];
        if (pool.isStarted) {
            totalAllocPoint = totalAllocPoint.sub(pool.allocPoint).add(_allocPoint);
        }
        pool.allocPoint = _allocPoint;
    }

    // Return accumulate rewards over the given _fromTime to _toTime.
    function getGeneratedReward(uint256 _fromTime, uint256 _toTime) public view returns (uint256) {
        for (uint8 epochId = 2; epochId >= 1; --epochId) {
            if (_toTime >= epochEndTimes[epochId - 1]) {
                if (_fromTime >= epochEndTimes[epochId - 1]) {
                    return _toTime.sub(_fromTime).mul(epochDibsPerSecond[epochId]);
                }

                uint256 _generatedReward = _toTime.sub(epochEndTimes[epochId - 1]).mul(epochDibsPerSecond[epochId]);
                if (epochId == 1) {
                    return _generatedReward.add(epochEndTimes[0].sub(_fromTime).mul(epochDibsPerSecond[0]));
                }
                for (epochId = epochId - 1; epochId >= 1; --epochId) {
                    if (_fromTime >= epochEndTimes[epochId - 1]) {
                        return _generatedReward.add(epochEndTimes[epochId].sub(_fromTime).mul(epochDibsPerSecond[epochId]));
                    }
                    _generatedReward = _generatedReward.add(epochEndTimes[epochId].sub(epochEndTimes[epochId - 1]).mul(epochDibsPerSecond[epochId]));
                }
                return _generatedReward.add(epochEndTimes[0].sub(_fromTime).mul(epochDibsPerSecond[0]));
            }
        }
        return _toTime.sub(_fromTime).mul(epochDibsPerSecond[0]);
    }

    // View function to see pending DIBSs on frontend.
    function pendingDIBS(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accDibsPerShare = pool.accDibsPerShare;
        uint256 tokenSupply = pool.token.balanceOf(address(this));
        if (block.timestamp > pool.lastRewardTime && tokenSupply != 0) {
            uint256 _generatedReward = getGeneratedReward(pool.lastRewardTime, block.timestamp);
            uint256 _dibsReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            accDibsPerShare = accDibsPerShare.add(_dibsReward.mul(1e18).div(tokenSupply));
        }
        return user.amount.mul(accDibsPerShare).div(1e18).sub(user.rewardDebt);
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
            uint256 _dibsReward = _generatedReward.mul(pool.allocPoint).div(totalAllocPoint);
            pool.accDibsPerShare = pool.accDibsPerShare.add(_dibsReward.mul(1e18).div(tokenSupply));
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
            uint256 _pending = user.amount.mul(pool.accDibsPerShare).div(1e18).sub(user.rewardDebt);
            if (_pending > 0) {
                safeDibsTransfer(_sender, _pending);
                emit RewardPaid(_sender, _pending);
            }
        }
        if (_amount > 0) {
            pool.token.safeTransferFrom(_sender, address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDibsPerShare).div(1e18);
        emit Deposit(_sender, _pid, _amount);
    }

    // Withdraw LP tokens.
    function withdraw(uint256 _pid, uint256 _amount) public {
        address _sender = msg.sender;
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 _pending = user.amount.mul(pool.accDibsPerShare).div(1e18).sub(user.rewardDebt);
        if (_pending > 0) {
            safeDibsTransfer(_sender, _pending);
            emit RewardPaid(_sender, _pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.token.safeTransfer(_sender, _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accDibsPerShare).div(1e18);
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

    // Safe dibs transfer function, just in case if rounding error causes pool to not have enough DIBSs.
    function safeDibsTransfer(address _to, uint256 _amount) internal {
        uint256 _dibsBal = dibs.balanceOf(address(this));
        if (_dibsBal > 0) {
            if (_amount > _dibsBal) {
                dibs.safeTransfer(_to, _dibsBal);
            } else {
                dibs.safeTransfer(_to, _amount);
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
        if (block.timestamp < epochEndTimes[1] + 30 days) {
            // do not allow to drain token if less than 30 days after farming
            require(_token != dibs, "!dibs");
            uint256 length = poolInfo.length;
            for (uint256 pid = 0; pid < length; ++pid) {
                PoolInfo storage pool = poolInfo[pid];
                require(_token != pool.token, "!pool.token");
            }
        }
        _token.safeTransfer(to, amount);
    }
}