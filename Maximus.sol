// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/ERC20.sol)

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
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
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address to, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _transfer(owner, to, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * NOTE: If `amount` is the maximum `uint256`, the allowance is not updated on
     * `transferFrom`. This is semantically equivalent to an infinite approval.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * NOTE: Does not update the allowance if the current allowance
     * is the maximum `uint256`.
     *
     * Requirements:
     *
     * - `from` and `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     * - the caller must have allowance for ``from``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) public virtual override returns (bool) {
        address spender = _msgSender();
        _spendAllowance(from, spender, amount);
        _transfer(from, to, amount);
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
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        address owner = _msgSender();
        _approve(owner, spender, allowance(owner, spender) + addedValue);
        return true;
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
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        address owner = _msgSender();
        uint256 currentAllowance = allowance(owner, spender);
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(owner, spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `from` must have a balance of at least `amount`.
     */
    function _transfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(from, to, amount);

        uint256 fromBalance = _balances[from];
        require(fromBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[from] = fromBalance - amount;
        }
        _balances[to] += amount;

        emit Transfer(from, to, amount);

        _afterTokenTransfer(from, to, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Updates `owner` s allowance for `spender` based on spent `amount`.
     *
     * Does not update the allowance amount in case of infinite allowance.
     * Revert if not enough allowance is available.
     *
     * Might emit an {Approval} event.
     */
    function _spendAllowance(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        uint256 currentAllowance = allowance(owner, spender);
        if (currentAllowance != type(uint256).max) {
            require(currentAllowance >= amount, "ERC20: insufficient allowance");
            unchecked {
                _approve(owner, spender, currentAllowance - amount);
            }
        }
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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

    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `to`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address to, uint256 amount) external returns (bool);

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
     * @dev Moves `amount` tokens from `from` to `to` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (token/ERC20/utils/SafeERC20.sol)

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

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

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
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
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/extensions/ERC20Burnable.sol)

pragma solidity ^0.8.0;

import "../ERC20.sol";
import "../../../utils/Context.sol";

/**
 * @dev Extension of {ERC20} that allows token holders to destroy both their own
 * tokens and those that they have an allowance for, in a way that can be
 * recognized off-chain (via event analysis).
 */
abstract contract ERC20Burnable is Context, ERC20 {
    /**
     * @dev Destroys `amount` tokens from the caller.
     *
     * See {ERC20-_burn}.
     */
    function burn(uint256 amount) public virtual {
        _burn(_msgSender(), amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, deducting from the caller's
     * allowance.
     *
     * See {ERC20-_burn} and {ERC20-allowance}.
     *
     * Requirements:
     *
     * - the caller must have allowance for ``accounts``'s tokens of at least
     * `amount`.
     */
    function burnFrom(address account, uint256 amount) public virtual {
        _spendAllowance(account, _msgSender(), amount);
        _burn(account, amount);
    }
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/math/SafeMath.sol)

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is generally not needed starting with Solidity 0.8, since the compiler
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
     * @dev Returns the subtraction of two unsigned integers, with an overflow flag.
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}
//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.2;
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

contract HedronToken {
  function approve(address spender, uint256 amount) external returns (bool) {}
  function transfer(address recipient, uint256 amount) external returns (bool) {}
  function mintNative(uint256 stakeIndex, uint40 stakeId) external returns (uint256) {}
  function claimNative(uint256 stakeIndex, uint40 stakeId) external returns (uint256) {}
  function currentDay() external view returns (uint256) {}
}

contract HEXToken {
  function currentDay() external view returns (uint256){}
  function stakeStart(uint256 newStakedHearts, uint256 newStakedDays) external {}
  function approve(address spender, uint256 amount) external returns (bool) {}
  function transfer(address recipient, uint256 amount) public returns (bool) {}
  function stakeEnd(uint256 stakeIndex, uint40 stakeIdParam) public {}
  function stakeCount(address stakerAddr) external view returns (uint256) {}
}
// Maximus is a contract for trustlessly pooling a single max length hex stake.
// Anyone may choose to mint 1 MAXI per HEX deposited into the Maximus Contract Address during the minting phase.
// Anyone may choose to pay for the gas to start and end the stake on behalf of the Maximus Contract.
// Anyone may choose to pay for the gas to mint Hedron the stake earns on behalf of the Maximus Contract.
// MAXI is a standard ERC20 token only minted upon HEX deposit and burnt open HEX redemption with no pre-mine or contract fee.
// MAXI holders may choose to burn MAXI to redeem HEX principal and yield (Including HEDRON) pro-rata from the Maximus Contract Address during the redemption phase.
//
// |--- Minting Phase---|---------- 5555 Day Stake Phase ------------...-----|------ Redemption Phase ---------->


contract Maximus is ERC20, ERC20Burnable {
    // all days are measured in terms of the HEX contract day number
    uint256 MINTING_PHASE_START;
    uint256 MINTING_PHASE_END;
    uint256 STAKE_START_DAY;
    uint256 STAKE_END_DAY;
    uint256 STAKE_LENGTH;
    uint256 HEX_REDEMPTION_RATE; // Number of HEX units redeemable per MAXI
    uint256 HEDRON_REDEMPTION_RATE; // Number of HEDRON units redeemable per MAXI
    bool HAS_STAKE_STARTED;
    bool HAS_STAKE_ENDED;
    bool HAS_HEDRON_MINTED;
    address END_STAKER; 
    
    constructor(uint256 mint_duration, uint256 stake_duration) ERC20("Maximus", "MAXI") {
        uint256 start_day=hex_token.currentDay();
        MINTING_PHASE_START = start_day;
        MINTING_PHASE_END = start_day+mint_duration;
        STAKE_LENGTH=stake_duration; 
        HAS_STAKE_STARTED=false;
        HAS_STAKE_ENDED = false;
        HAS_HEDRON_MINTED=false;
        HEX_REDEMPTION_RATE=100000000; // HEX and MAXI are 1:1 convertible up until the stake is initiated
        HEDRON_REDEMPTION_RATE=0; //no hedron is redeemable until minting has occurred
        
    }
    
    /**
    * @dev View number of decimal places the MAXI token is divisible to. Manually overwritten from default 18 to 8 to match that of HEX. 1 MAXI = 10^8 mini
    */
    
    function decimals() public view virtual override returns (uint8) {
        return 8;
	}
    address MAXI_ADDRESS =address(this);
    address constant HEX_ADDRESS = 0x2b591e99afE9f32eAA6214f7B7629768c40Eeb39; // "2b, 5 9 1e? that is the question..."
    address constant HEDRON_ADDRESS=0x3819f64f282bf135d62168C1e513280dAF905e06; // PULSECHAIN TESTNET HEDRON ADDRESS

    IERC20 hex_contract = IERC20(HEX_ADDRESS);
    IERC20 hedron_contract=IERC20(HEDRON_ADDRESS);
    HEXToken hex_token = HEXToken(HEX_ADDRESS);
    HedronToken hedron_token = HedronToken(HEDRON_ADDRESS);
    // public function
    /**
    * @dev Returns the HEX Day that the Minting Phase started.
    * @return HEX Day that the Minting Phase started.
    */
    function getMintingPhaseStartDay() external view returns (uint256) {return MINTING_PHASE_START;}
    /**
    * @dev Returns the HEX Day that the Minting Phase ends.
    * @return HEX Day that the Minting Phase ends.
    */
    function getMintingPhaseEndDay() external view returns (uint256) {return MINTING_PHASE_END;}
    /**
    * @dev Returns the HEX Day that the Maximus HEX Stake started.
    * @return HEX Day that the Maximus HEX Stake started.
    */
    function getStakeStartDay() external view returns (uint256) {return STAKE_START_DAY;}
    /**
    * @dev Returns the HEX Day that the Maximus HEX Stake ends.
    * @return HEX Day that the Maximus HEX Stake ends.
    */
    function getStakeEndDay() external view returns (uint256) {return STAKE_END_DAY;}
    /**
    * @dev Returns the rate at which MAXI may be redeemed for HEX. "Number of HEX hearts per 1 MAXI redeemed."
    * @return Rate at which MAXI may be redeemed for HEX. "Number of HEX hearts per 1 MAXI redeemed."
    */
    function getHEXRedemptionRate() external view returns (uint256) {return HEX_REDEMPTION_RATE;}
    /**
    * @dev Returns the rate at which MAXI may be redeemed for HEDRON.
    * @return Rate at which MAXI may be redeemed for HDRN.
    */
    function getHedronRedemptionRate() external view returns (uint256) {return HEDRON_REDEMPTION_RATE;}

    /**
    * @dev Returns the current HEX day."
    * @return Current HEX Day
    */
    function getHexDay() external view returns (uint256){
        uint256 day = hex_token.currentDay();
        return day;
    }
     /**
    * @dev Returns the current HEDRON day."
    * @return day Current HEDRON Day
    */
    function getHedronDay() external view returns (uint day) {return hedron_token.currentDay();}

     /**
    * @dev Returns the address of the person who ends stake. May be used by external gas pooling contracts. If stake has not been ended yet will return 0x000...000"
    * @return end_staker_address This person should be honored and celebrated as a hero.
    */
    function getEndStaker() external view returns (address end_staker_address) {return END_STAKER;}

    // MAXI Issuance and Redemption Functions
    /**
     * @dev Mints MAXI.
     * @param amount of MAXI to mint, measured in minis
     */
    function mint(uint256 amount) private {
        _mint(msg.sender, amount);
    }
     /**
     * @dev Ensures that MAXI Minting Phase is ongoing and that the user has allowed the Maximus Contract address to spend the amount of HEX the user intends to pledge to Maximus DAO. Then sends the designated HEX from the user to the Maximus Contract address and mints 1 MAXI per HEX pledged.
     * @param amount of HEX user chose to pledge, measured in hearts
     */
    function pledgeHEX(uint256 amount) external {
        require(hex_token.currentDay()<=MINTING_PHASE_END, "Minting Phase is Done");
        require(hex_contract.allowance(msg.sender, MAXI_ADDRESS)>=amount, "Please approve contract address as allowed spender in the hex contract.");
        address from = msg.sender;
        hex_contract.transferFrom(from, MAXI_ADDRESS, amount);
        mint(amount);
    }
     /**
     * @dev Ensures that it is currently a redemption period (before stake starts or after stake ends) and that the user has at least the number of maxi they entered. Then it calculates how much hex may be redeemed, burns the MAXI, and transfers them the hex.
     * @param amount_MAXI number of MAXI that the user is redeeming, measured in mini
     */
    function redeemHEX(uint256 amount_MAXI) external {
        require(HAS_STAKE_STARTED==false || HAS_STAKE_ENDED==true , "Redemption can only happen before stake starts or after stake ends.");
        uint256 yourMAXI = balanceOf(msg.sender);
        require(yourMAXI>=amount_MAXI, "You do not have that much MAXI.");
        uint256 raw_redeemable_amount = amount_MAXI*HEX_REDEMPTION_RATE;
        uint256 redeemable_amount = raw_redeemable_amount/100000000; //scaled back down to handle integer rounding
        burn(amount_MAXI);
        hex_token.transfer(msg.sender, redeemable_amount);
        if (HAS_HEDRON_MINTED==true) {
            uint256 raw_redeemable_hedron = amount_MAXI*HEDRON_REDEMPTION_RATE;
            uint256 redeemable_hedron = raw_redeemable_hedron/100000000; //scaled back down to handle integer rounding
            hedron_token.transfer(msg.sender, redeemable_hedron);
        }
    }
    //Staking Functions
    // Anyone may run these functions during the allowed time, so long as they pay the gas.
    // While nothing is forcing you to, gracious Maximus members will tip the sender some ETH for paying gas to end your stake.

    /**
     * @dev Ensures that the stake has not started yet and that the minting phase is over. Then it stakes all the hex in the contract and schedules the STAKE_END_DAY.
     * @notice This will trigger the start of the HEX stake. If you run this, you will pay the gas on behalf of the contract and you should not expect reimbursement.
     
     */
    function stakeHEX() external {
        require(HAS_STAKE_STARTED==false, "Stake has already been started.");
        uint256 current_day = hex_token.currentDay();
        require(current_day>MINTING_PHASE_END, "Minting Phase is still ongoing - see MINTING_PHASE_END day.");
        uint256 amount = hex_contract.balanceOf(address(this)); 
        _stakeHEX(amount);
        HAS_STAKE_STARTED=true;
        STAKE_START_DAY=current_day;
        STAKE_END_DAY=current_day+STAKE_LENGTH;
    }
    function _stakeHEX(uint256 amount) private  {
        hex_token.stakeStart(amount,STAKE_LENGTH);
        }
    
    function _endStakeHEX(uint256 stakeIndex,uint40 stakeIdParam ) private  {
        hex_token.stakeEnd(stakeIndex, stakeIdParam);
        }
    /**
     * @dev Ensures that the stake is fully complete and that it has not already been ended. Then it ends the hex stake and updates the redemption rate.
     * @notice This will trigger the ending of the HEX stake and calculate the new redemption rate. This may be very expensive. If you run this, you will pay the gas on behalf of the contract and you should not expect reimbursement.
     * @param stakeIndex index of stake found in stakeLists[contract_address] in hex contract.
     * @param stakeIdParam stake identifier found in stakeLists[contract_address] in hex contract.
     */
    function endStakeHEX(uint256 stakeIndex,uint40 stakeIdParam ) external {
        require(hex_token.currentDay()>STAKE_END_DAY, "Stake is not complete yet.");
        require(HAS_STAKE_STARTED==true && HAS_STAKE_ENDED==false, "Stake has already been started.");
        _endStakeHEX(stakeIndex, stakeIdParam);
        HAS_STAKE_ENDED=true;
        uint256 hex_balance = hex_contract.balanceOf(address(this));
        uint256 total_maxi_supply = IERC20(address(this)).totalSupply();
        HEX_REDEMPTION_RATE  = calculate_redemption_rate(hex_balance, total_maxi_supply);
        END_STAKER=msg.sender;
    }
    /**
     * @dev Calculates the pro-rata redemption rate of any coin per maxi. Scales value by 10^8 to handle integer rounding.
     * @param treasury_balance The balance of coins in the maximus contract address (either HEX or HEDRON)
     * @param maxi_supply total maxi supply
     * @return redemption_rate Number of units redeemable per 10^8 decimal units of MAXI. Is scaled back down by 10^8 on redemption transaction.
     */
    function calculate_redemption_rate(uint treasury_balance, uint maxi_supply) private view returns (uint redemption_rate) {
        uint256 scalar = 10**8;
        uint256 scaled = (treasury_balance * scalar) / maxi_supply; // scale value to calculate redemption amount per maxi and then divide by same scalar after multiplication
        return scaled;
    }
    
    /**
     * @dev Public function which calls the private function which is used for minting available HDRN accumulated by the contract stake. 
     * @notice This will trigger the minting of the mintable Hedron earned by the stake. If you run this, you will pay the gas on behalf of the contract and you should not expect reimbursement. If check to make sure this has not been run yet already or the transaction will fail.
     * @param stakeIndex index of stake found in stakeLists[contract_address] in hex contract.
     * @param stakeId stake identifier found in stakeLists[contract_address] in hex contract.
     */
  function mintHedron(uint256 stakeIndex,uint40 stakeId ) external  {
      _mintHedron(stakeIndex, stakeId);
        }
   /**
     * @dev Private function used for minting available HDRN accumulated by the contract stake and updating the HDRON redemption rate.
     * @param stakeIndex index of stake found in stakeLists[contract_address] in hex contract.
     * @param stakeId stake identifier found in stakeLists[contract_address] in hex contract.
     */
  function _mintHedron(uint256 stakeIndex,uint40 stakeId ) private  {
        hedron_token.mintNative(stakeIndex, stakeId);
        uint256 total_hedron= hedron_contract.balanceOf(address(this));
        uint256 total_maxi = IERC20(address(this)).totalSupply();
        
        HEDRON_REDEMPTION_RATE = calculate_redemption_rate(total_hedron, total_maxi);
        HAS_HEDRON_MINTED = true;
        }

}