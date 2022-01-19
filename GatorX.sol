// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IGatorXToken.sol";
import "./interfaces/IUniswapV2Router.sol";
import "./interfaces/IUniswapV2Factory.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IGameOfLuck.sol";
import "./pancake-swap/libraries/TransferHelper.sol";

/**
 * @dev Implementation of the GATORX Token.
 *
 * After the first stage of the sale, 15% of the tokens must be burned
 * Then every month 2% of tokens should be burned during the year
 *
 * Each transaction must be charged 10% of the tokens of the amount, where
 *
 * - 1% goes to the game address, from where once a month these tokens are sent to the random holder
 * - 1% of the transaction amount - burned
 * - 3% go to the marketing address
 * - 3% on the liquidity pool
 * - 2% to be distributed to holders proportionally
 *
 * BSC net
 */
contract GatorXToken is IGatorXToken, IERC20, Ownable {
    uint256 public constant SEED_ROUND = 22;
    uint256 public constant PRIVATE_SALE = 28;
    uint256 public constant MARKETING = 180;
    uint256 public constant TEAM = 120;
    uint256 public constant RESERVES = 50;
    uint256 public constant DEVELOPMENT = 150;
    uint256 public constant PUBLIC_SALE = 350;
    uint256 public constant LIQ = 100;

    uint256 public constant GAME_TAX = 10;
    uint256 public constant BURN_TAX = 10;
    uint256 public constant MARKETING_TAX = 30;
    uint256 public constant LIQ_TAX = 30;
    uint256 public constant TO_HOLDERS_TAX = 20;
    uint256 public constant MULTIPLIER = 10**20;

    IUniswapV2Router public immutable router;
    address public immutable uniswapV2Pair;

    address public gameContract;
    address public marketingContract;
    address public crowdsaleContract;
    uint256 public totalDistributed;
    uint256 public deferredLiquidity;

    uint256 private constant PERCENT_BASE = 1000;
    address private constant DEAD_ADDRESS =
        address(0x000000000000000000000000000000000000dEaD);

    string private _name;
    string private _symbol;
    uint256 private _totalSupply = 11 * (10**13) * (10**8);
    uint256 private globalCoefficient;
    bool private inTransfer;

    address[] private holders;

    mapping(address => bool) public isExcludedFromFee;
    mapping(address => bool) public burnFrom;
    mapping(address => uint256) private _balances;
    mapping(address => Holders) private holder;
    mapping(address => mapping(address => uint256)) private _allowances;

    struct Taxes {
        uint256 toGameTax;
        uint256 toMarketingTax;
        uint256 toBurnTax;
        uint256 toLIQTax;
        uint256 toHoldersTax;
    }

    struct Holders {
        uint256 index;
        uint256 rewardGot;
    }

    event TaxesDistribution(
        address from,
        uint256 toGameTax,
        uint256 toMarketingTax,
        uint256 toBurnTax,
        uint256 toLIQTax,
        uint256 toHoldersTax
    );

    event WithdrawReward(address user, uint256 reward);
    event BurnByOwner(uint256 amount, address wallet, uint256 time);

    modifier transferToken() {
        if (!inTransfer) {
            inTransfer = true;
            _;
            inTransfer = false;
        }
    }

    modifier nonZeroAmount(uint256 amount) {
        require(amount > 0, "GatorX: amnt 0");
        _;
    }

    constructor(
        address _marketingContract,
        address _router,
        address _owner,
        address _team,
        address _reserve,
        address _development,
        address _seed_round,
        address _private_sale
    ) {
        require(
            _marketingContract != address(0) &&
                _router != address(0) &&
                _owner != address(0) &&
                _team != address(0) &&
                _private_sale != address(0) &&
                _seed_round != address(0) &&
                _reserve != address(0) &&
                _development != address(0),
            "GatorX: 0X0.."
        );
        _name = "GatorX";
        _symbol = "GTRX";
        router = IUniswapV2Router(_router);
        uniswapV2Pair = IUniswapV2Factory(router.factory()).createPair(
            address(this),
            router.WETH()
        );
        marketingContract = _marketingContract;
        isExcludedFromFee[_router] = true;
        isExcludedFromFee[uniswapV2Pair] = true;
        isExcludedFromFee[_marketingContract] = true;
        isExcludedFromFee[DEAD_ADDRESS] = true;
        isExcludedFromFee[address(0)] = true;
        isExcludedFromFee[address(this)] = true;
        isExcludedFromFee[_owner] = true;
        isExcludedFromFee[_reserve] = true;
        isExcludedFromFee[_development] = true;
        isExcludedFromFee[_seed_round] = true;
        isExcludedFromFee[_private_sale] = true;
        isExcludedFromFee[_team] = true;
        isExcludedFromFee[_msgSender()] = true;
        burnFrom[_marketingContract] = true;
        burnFrom[_owner] = true;
        burnFrom[_reserve] = true;
        burnFrom[_development] = true;
        burnFrom[_seed_round] = true;
        burnFrom[_private_sale] = true;
        burnFrom[_team] = true;
        _balances[_marketingContract] +=
            (_totalSupply * MARKETING) /
            PERCENT_BASE;
        _balances[_team] += (_totalSupply * TEAM) / PERCENT_BASE;
        _balances[_reserve] += (_totalSupply * RESERVES) / PERCENT_BASE;
        _balances[_development] += (_totalSupply * DEVELOPMENT) / PERCENT_BASE;
        _balances[_seed_round] += (_totalSupply * SEED_ROUND) / PERCENT_BASE;
        _balances[_private_sale] += (_totalSupply * PRIVATE_SALE) / PERCENT_BASE;
        _balances[_owner] += (_totalSupply *  LIQ) / PERCENT_BASE;
        _balances[_msgSender()] += (_totalSupply * PUBLIC_SALE) / PERCENT_BASE;
    }

    receive() external payable {}

    /**
     * @dev to burn TO_BURN_AFTER_STAGE percents and then burn TO_BURN_EACH_MONTH percents each months.
     * @param wallet address for burning
     * @param amount for burning
     */
    function burnOnDifRounds(address wallet, uint256 amount)
        external
        nonZeroAmount(amount)
        onlyOwner
    {
        require(burnFrom[wallet], "GatorX: 'not burning' wallet ");
        _burn(wallet, amount);
        emit BurnByOwner(amount, wallet, block.timestamp);
    }

    /**
     * @dev change parametr for user
     */
    function changeExcludedFromeFee(address user) external onlyOwner {
        if (isExcludedFromFee[user]) {
            if(_balances[user] > 0) {
                holder[user].rewardGot =
                    (globalCoefficient * _balances[user]) /
                    MULTIPLIER;
                holder[user].index = holders.length;
                holders.push(user);
                totalDistributed += _balances[user];
            }
            isExcludedFromFee[user] = false;
        } else {
            withdraw(user);
            if(_balances[user] > 0) {
                Holders memory investor = holder[user];
                uint256 index = holders.length - 1;
                address lastUser = holders[index];
                holder[lastUser].index = investor.index;
                holders[investor.index] = lastUser;
                holders.pop();
                totalDistributed -= _balances[user];
                delete (holder[user]);
            }
            isExcludedFromFee[user] = true;
        }
    }

    function setNewMarketingContract(address newMarketing) external onlyOwner {
        marketingContract = newMarketing;
    }

    /**
     * @dev set the address of crowdsale.
     * @param _crowdsaleContract address of contract
     */
    function setCrowdsale(address _crowdsaleContract, address _gameContract) external onlyOwner {
        require(
            gameContract == address(0) && crowdsaleContract == address(0),
            "GatroX: 0X0.."
        );
        isExcludedFromFee[_gameContract] = true;
        gameContract = _gameContract;
        isExcludedFromFee[_crowdsaleContract] = true;
        crowdsaleContract = _crowdsaleContract;
        _transfer(owner(), _crowdsaleContract , _totalSupply * PUBLIC_SALE / PERCENT_BASE);
    }

    /**
     * @dev send LIQ tokens from transction from pair BNB-GatorX
     */
    function sendDeferredLIQ() external transferToken onlyOwner {
        require(deferredLiquidity > 0, "GatroX: deferredLiquidity = 0");
        address owner = owner();
        swapETHAndLiquify(deferredLiquidity, owner, owner);
        deferredLiquidity = 0;
    }

    function sendResidue(
        address _token,
        uint256 amount,
        address to
    ) external nonZeroAmount(amount) transferToken onlyOwner {
        if (_token != address(0)) {
            require(
                IERC20(_token).balanceOf(address(this)) >= amount,
                "GatorX: balance < amount"
            );
            TransferHelper.safeTransfer(_token, to, amount);
        } else {
            require(
                address(this).balance >= amount,
                "GatorX: balance < amount"
            );
            (bool success, ) = payable(to).call{value: amount}("");
            require(success, "GatorX: tokens didn`t transfer");
        }
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) external returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount)
        external
        nonZeroAmount(amount)
        returns (bool)
    {
        address investor = _msgSender();

        if (!inTransfer) amount = calculateTaxes(amount, investor, recipient);

        _transfer(investor, recipient, amount);

        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the 'sender must have a balance of at least `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external nonZeroAmount(amount) returns (bool) {
        if (!inTransfer) amount = calculateTaxes(amount, sender, recipient);

        _transfer(sender, recipient, amount);
        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    /**
     * @dev Returns the address of the pair BNB-GatorX.
     */
    function getUV2Pair() external view returns (address) {
        return uniswapV2Pair;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        returns (bool)
    {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(
            currentAllowance >= subtractedValue,
            "ERC20: decreased allowance below zero"
        );
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue)
        public
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender] + addedValue
        );
        return true;
    }

    /**
     * @dev send rewards to the address.
     * @param account for withdraw
     */
    function withdraw(address account) public {
        require(
            _balances[account] > 0 && !isExcludedFromFee[account],
            "GatorX: not holder"
        );
        uint256 amount = getReward(account);
        if( amount > 0 ) {
            holder[account].rewardGot =
                (globalCoefficient * (_balances[account] + amount)) /
                MULTIPLIER;
            totalDistributed = totalDistributed + amount;
            _transfer(address(this), account, amount);
        }
        emit WithdrawReward(account, amount);
    }

    /**
     * @dev Returns massive of holders.
     */
    function getHolders() public view returns (address[] memory) {
        return holders;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view returns (uint256) {
        if (!isExcludedFromFee[account]) return _balances[account] + getReward(account);
        else return _balances[account];
    }

    /**
     * @dev get amount reward for user.
     * @param account is address for user
     */
    function getReward(address account) public view returns (uint256 amount) {
        amount = ((globalCoefficient * _balances[account]) /
            MULTIPLIER -
            holder[account].rewardGot);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public pure returns (uint8) {
        return 8;
    }

    function calculateTaxes(
        uint256 _amount,
        address from,
        address to
    ) internal transferToken returns (uint256 amount) {
        Taxes memory taxes;
        updateStake(from, to, _amount);
        address inv = _msgSender();

        if (inv != gameContract && inv != crowdsaleContract) {
            taxes.toMarketingTax = (_amount * MARKETING_TAX) / PERCENT_BASE;
            _transfer(from, marketingContract, taxes.toMarketingTax);

            taxes.toBurnTax = (_amount * BURN_TAX) / PERCENT_BASE;
            _burn(from, taxes.toBurnTax);

            address[] memory path = new address[](2);
            path[0] = address(this);
            path[1] = router.WETH();
            if (_pairExisting(path)) {
                taxes.toLIQTax = (_amount * LIQ_TAX) / PERCENT_BASE;
                _transfer(from, address(this), taxes.toLIQTax);
                if (inv != uniswapV2Pair) {
                    uint256 liq_tax = taxes.toLIQTax;
                    if (deferredLiquidity > 0) {
                        liq_tax = liq_tax + deferredLiquidity;
                        deferredLiquidity = 0;
                    }
                    swapETHAndLiquify(liq_tax, from, to);
                } else {
                    deferredLiquidity += taxes.toLIQTax;
                }
            }

            if (gameContract != address(0)) {
                taxes.toGameTax = (_amount * GAME_TAX) / PERCENT_BASE;
                _approve(from, gameContract, taxes.toGameTax);
                IGameOfLuck(gameContract).getTokens(from, taxes.toGameTax);
            }

            if (holders.length > 0) {
                taxes.toHoldersTax = (_amount * TO_HOLDERS_TAX) / PERCENT_BASE;
                _transfer(from, address(this), taxes.toHoldersTax);
            }
        }

        uint256 lost = (taxes.toGameTax +
            taxes.toMarketingTax +
            taxes.toBurnTax +
            taxes.toLIQTax +
            taxes.toHoldersTax);

        amount = _amount - lost;

        if (!isExcludedFromFee[from])
            holder[from].rewardGot =
                (globalCoefficient * (_balances[from] - amount)) /
                MULTIPLIER;
        if (!isExcludedFromFee[to])
            holder[to].rewardGot =
                (globalCoefficient * (_balances[to] + amount)) /
                MULTIPLIER;

        if (isExcludedFromFee[from]) {
            if (!isExcludedFromFee[to]) totalDistributed += amount;
        } else {
            if (isExcludedFromFee[to]) totalDistributed -= _amount;
            else totalDistributed -= lost;
        }

        if (taxes.toHoldersTax > 0)
            globalCoefficient +=
                (taxes.toHoldersTax * MULTIPLIER) /
                totalDistributed;

        emit TaxesDistribution(
            from,
            taxes.toGameTax,
            taxes.toMarketingTax,
            taxes.toBurnTax,
            taxes.toLIQTax,
            taxes.toHoldersTax
        );
    }

    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        uint256 senderBalance = _balances[sender];
        require(
            senderBalance >= amount,
            "ERC20: transfer amount exceeds balance"
        );

        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);
    }

    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);
    }

    function _pairExisting(address[] memory path) internal view returns (bool) {
        uint8 len = uint8(path.length);

        IUniswapV2Factory factory = IUniswapV2Factory(router.factory());
        address pair;
        uint256 reserve0;
        uint256 reserve1;

        for (uint8 i; i < len - 1; i++) {
            pair = factory.getPair(path[i], path[i + 1]);
            if (pair != address(0)) {
                (reserve0, reserve1, ) = IUniswapV2Pair(pair).getReserves();
                if ((reserve0 == 0 || reserve1 == 0)) return false;
            } else {
                return false;
            }
        }

        return true;
    }

    function swapETHAndLiquify(
        uint256 amount,
        address from,
        address to
    ) private {
        _approve(address(this), address(router), amount);

        IUniswapV2Pair pair = IUniswapV2Pair(uniswapV2Pair);

        
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 half = getOptimalAmountToSell(
            int256(address(this) == pair.token0() ? reserve0 : reserve1),
            int256(amount)
        );

        uint256 anotherHalf = amount - half;
        uint256 amountETH = address(this).balance;

        swapTokensForEth(half);

        amountETH = address(this).balance - amountETH;
        (uint256 tokenAmount, , ) = router.addLiquidityETH{value: amountETH}(
            address(this),
            anotherHalf,
            0,
            0,
            from,
            block.timestamp
        );

        if (tokenAmount < anotherHalf) {
            _transfer(address(this), to, anotherHalf - tokenAmount);
            if (!isExcludedFromFee[to])
                totalDistributed =
                    totalDistributed +
                    (anotherHalf - tokenAmount);
        }
    }

    function swapTokensForEth(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();

        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0,
            path,
            address(this),
            block.timestamp
        );
    }

    function getOptimalAmountToSell(int256 X, int256 dX)
        private
        pure
        returns (uint256)
    {
        int256 feeDenom = 1000000;
        int256 f = 998000; // 1 - fee
        unchecked {
            int256 T1 = X * (X * (feeDenom + f)**2 + 4 * feeDenom * dX * f);

            // square root
            int256 z = (T1 + 1) / 2;
            int256 sqrtT1 = T1;
            while (z < sqrtT1) {
                sqrtT1 = z;
                z = (T1 / z + z) / 2;
            }

            return
                uint256(
                    (2 * feeDenom * dX * X) / (sqrtT1 + X * (feeDenom + f))
                );
        }
    }

    function updateStake(
        address from,
        address to,
        uint256 amount
    ) private {
        if (!isExcludedFromFee[to]) {
            if (_pairCheck(to)) isExcludedFromFee[to] = true;
            else if (balanceOf(to) == 0) {
                holder[to].index = holders.length;
                holders.push(to);
            } else withdraw(to);
        }

        if (!isExcludedFromFee[from]) {
            withdraw(from);
            if (balanceOf(from) - amount == 0) {
                Holders memory investor = holder[from];
                uint256 index = holders.length - 1;
                address lastUser = holders[index];
                holder[lastUser].index = investor.index;
                holders[investor.index] = lastUser;
                holders.pop();
                delete (holder[from]);
            }
        }
    }

    function _pairCheck(address _token) internal view returns (bool) {
        address token0;
        address token1;

        if (isContract(_token)) {
            try IUniswapV2Pair(_token).token0() returns (address _token0) {
                token0 = _token0;
            } catch {
                return false;
            }

            try IUniswapV2Pair(_token).token1() returns (address _token1) {
                token1 = _token1;
            } catch {
                return false;
            }

            address goodPair = IUniswapV2Factory(
                IUniswapV2Router(router).factory()
            ).getPair(token0, token1);
            if (goodPair != _token) {
                return false;
            }

            if (token0 == address(this) || token1 == address(this)) return true;
            else return false;
        } else return false;
    }

    function isContract(address addr) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(addr)
        }
        return size > 0;
    }

}// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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
}// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";

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
    constructor() {
        _setOwner(_msgSender());
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
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IGatorXToken {

    function getHolders() external view returns (address[] memory);
    
}// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IUniswapV2Router {
    function WETH() external view returns (address);

    function factory() external pure returns (address);

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IUniswapV2Factory {

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    function feeTo() external view returns (address);
    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB) external view returns (address pair);
    function allPairs(uint) external view returns (address pair);
    function allPairsLength() external view returns (uint);

    function createPair(address tokenA, address tokenB) external returns (address pair);

    function setFeeTo(address) external;
    function setFeeToSetter(address) external;

}// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IUniswapV2Pair {
    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );
}// SPDX-License-Identifier: MIT
pragma solidity 0.8.9;

interface IGameOfLuck {

    function getTokens(address investor, uint256 amount) external ;
    
}// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeApprove: approve failed"
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::safeTransfer: transfer failed"
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) =
            token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper::transferFrom: transferFrom failed"
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(
            success,
            "TransferHelper::safeTransferETH: ETH transfer failed"
        );
    }
}// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
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
        return msg.data;
    }
}