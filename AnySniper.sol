/**
 *Submitted for verification at Etherscan.io on 2022-02-17
*/

// Sources flattened with hardhat v2.6.8 https://hardhat.org

// File hardhat/console.sol@v2.6.8


pragma solidity >= 0.4.22 <0.9.0;

library console {
	address constant CONSOLE_ADDRESS = address(0x000000000000000000636F6e736F6c652e6c6f67);

	function _sendLogPayload(bytes memory payload) private view {
		uint256 payloadLength = payload.length;
		address consoleAddress = CONSOLE_ADDRESS;
		assembly {
			let payloadStart := add(payload, 32)
			let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
		}
	}

	function log() internal view {
		_sendLogPayload(abi.encodeWithSignature("log()"));
	}

	function logInt(int p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(int)", p0));
	}

	function logUint(uint p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
	}

	function logString(string memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(string)", p0));
	}

	function logBool(bool p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
	}

	function logAddress(address p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(address)", p0));
	}

	function logBytes(bytes memory p0) internal view {
		_sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
	}


// File @openzeppelin/contracts/utils/Context.sol@v4.4.0-rc.0


// OpenZeppelin Contracts v4.4.0-rc.0 (utils/Context.sol)

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


// File @openzeppelin/contracts/access/Ownable.sol@v4.4.0-rc.0


// OpenZeppelin Contracts v4.4.0-rc.0 (access/Ownable.sol)

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
    constructor() {
        _transferOwnership(_msgSender());
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
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}


// File @openzeppelin/contracts/utils/math/SafeMath.sol@v4.4.0-rc.0


// OpenZeppelin Contracts v4.4.0-rc.0 (utils/math/SafeMath.sol)

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


// File contracts/interfaces/IERC20.sol

interface IERC20 {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);
}


// File contracts/interfaces/IWETH.sol

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
    function balanceOf(address) external returns (uint);
    function transferFrom(address src, address dst, uint wad) external returns (bool);
    function approve(address guy, uint wad) external returns (bool);
}


// File contracts/interfaces/IRouter.sol

interface IRouter {
    function buy(address _token, address[] calldata _recipients, uint256[] calldata _amountIns, uint256[] calldata _maxOuts)  external returns (uint256 amountSpent);
    function sell(address _token, address[] calldata _sellers, uint256[] calldata _amountIns, bool _isPercent)  external returns (uint256 amountReceived);
}


// File contracts/libraries/TransferHelper.sol

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


// File contracts/Escrow.sol

//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;







contract Escrow is Ownable {
  using SafeMath for uint256;
  address public immutable WETH;

  mapping(address => uint256) private _balances;

  mapping(address => address) public spenderToOwner;

  mapping(address => address) public ownerToSpender;

  address public router;

  event RouterChanged(address _router);

  event SpenderUpdated(address _spender);

  event Deposit(address _from, uint256 _amount);

  event Withdraw(address _from, address _to, uint256 _amount);

  event WithdrawDustToken(address _token, address _to, uint256 _amount);

  event WithdrawDustETH(address _to, uint256 _amount);

  constructor(address _WETH) {
    WETH = _WETH;
  }

  function setSpender(address _spender) external {
    address owner = msg.sender;
    address previousSpender = ownerToSpender[owner];
    require(previousSpender != _spender);
    spenderToOwner[previousSpender] = address(0);

    ownerToSpender[owner] = _spender;
    spenderToOwner[_spender] = owner;

    emit SpenderUpdated(_spender);
  }

  function setRouter(address _router) external onlyOwner {
    router = _router;
    emit RouterChanged(_router);
  }

  function buy(address _token, address[] calldata _recipients, uint256[] calldata _amountIns, uint256[] calldata _maxOuts) external{
    require(_recipients.length == _amountIns.length && _maxOuts.length == _amountIns.length, "Invalid parameters");

    address spender = msg.sender;
    address owner = spenderToOwner[spender];

    uint256 totalAmount;
    for (uint256 i; i < _amountIns.length; ++i) {
      totalAmount = totalAmount.add(_amountIns[i]);
    }

    require(_balances[owner] >= totalAmount, "Insufficient amount");
    
    IWETH(WETH).approve(router, totalAmount);
    uint256 amountSpent = IRouter(router).buy(_token, _recipients, _amountIns, _maxOuts);

    _balances[owner] = _balances[owner].sub(amountSpent);
  }

  function sell(address _token, address[] calldata _sellers, uint256[] calldata _amountIns, bool _isPercent) external {
    require(_sellers.length == _amountIns.length, "Invalid parameters");
    
    address spender = msg.sender;
    address owner = spenderToOwner[spender];

    uint256 amountReceived = IRouter(router).sell(_token, _sellers, _amountIns, _isPercent);
    _balances[owner] = _balances[owner].add(amountReceived);
  }

  function balanceOf(address _owner) external view returns (uint256) {
    return _balances[_owner];
  }

  function deposit() external payable {
    uint256 amount = msg.value;
    address sender = msg.sender;
    IWETH(WETH).deposit{value: amount}();
    _balances[sender] = _balances[sender].add(amount);
    emit Deposit(sender, amount);
  }

  function withdraw(address _to, uint256 _amount) external {
    address sender = msg.sender;
    require(_amount <= _balances[sender], "Insufficient withdraw amount");
    IWETH(WETH).withdraw(_amount);
    _balances[sender] = _balances[sender].sub(_amount);
    TransferHelper.safeTransferETH(_to, _amount);
    emit Withdraw(sender, _to, _amount);
  }

  function multiWithdrawETH(address[] calldata _recipients, uint256[] calldata _amounts, uint256 _totalAmount) external {
    address sender = msg.sender;
    require(_recipients.length == _amounts.length, "Invalid parameters");

    IWETH(WETH).withdraw(_totalAmount);

    uint256 totalAmount;
    for (uint256 i; i < _recipients.length; ++i) {
      (bool success, ) = _recipients[i].call{ value: _amounts[i]}("");
      require(success, "Address: unable to send value, recipient may have reverted");
      totalAmount = totalAmount.add(_amounts[i]);
    }

    require(totalAmount == _totalAmount, 'Invalid parameters');
    require(totalAmount <= _balances[sender], 'Insufficient amount');
    
    _balances[sender] = _balances[sender].sub(totalAmount);
  }

  function multiSendETH(address[] calldata _recipients, uint256[] calldata _amounts) external payable {
    require(_recipients.length == _amounts.length, "Invalid parameters");

    uint256 totalAmount;
    for (uint256 i; i < _recipients.length; ++i) {
      (bool success, ) = _recipients[i].call{ value: _amounts[i]}("");
      require(success, "Address: unable to send value, recipient may have reverted");
      totalAmount = totalAmount.add(_amounts[i]);
    }

    require(totalAmount <= msg.value, 'Insufficient amount');
  }

  // To receive ETH from uniswapV2Router when swapping
  receive() external payable {}

  // Withdraw dust tokens
  function withdrawDustToken(address _token, address _to)
    external
    onlyOwner
    returns (bool _sent)
  {
      require(_token != WETH, "Can't withdraw WETH");
      uint256 _amount = IERC20(_token).balanceOf(address(this));
      _sent = IERC20(_token).transfer(_to, _amount);
      emit WithdrawDustToken(_token, _to, _amount);
  }

  // Withdraw Dust ETH
  function withdrawDustETH(address _to) external onlyOwner {
    uint256 _amount = address(this).balance;
    (bool success, ) = _to.call{ value: _amount}("");
    require(success, "Address: unable to send value, recipient may have reverted");
    emit WithdrawDustETH(_to, _amount);
  }
}