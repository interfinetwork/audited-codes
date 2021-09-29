// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

import './Token.sol';
import './SupportsInterface.sol';

/**
 * @title Grexie Token
 * @dev Simple ERC20 Token with standard token functions.
 */
contract GrexieToken is Token, SupportsInterface {
  string private constant NAME = 'Grexie';
  string private constant SYMBOL = 'GREX';
  uint8 private constant DECIMALS = 18;

  uint256 private constant TOTAL_SUPPLY = 10**15 * 10**18;

  /**
   * Grexie Token Constructor
   * @dev Create and issue tokens to msg.sender.
   */
  constructor() public {
    balances[msg.sender] = TOTAL_SUPPLY;
    supportedInterfaces[0x36372b07] = true; // ERC20
    supportedInterfaces[0x06fdde03] = true; // ERC20 name
    supportedInterfaces[0x95d89b41] = true; // ERC20 symbol
    supportedInterfaces[0x313ce567] = true; // ERC20 decimals
  }

  function name() external view returns (string memory _name) {
    return NAME;
  }

  function symbol() external view returns (string memory _symbol) {
    return SYMBOL;
  }

  function decimals() external view returns (uint8 _decimals) {
    return DECIMALS;
  }

  function totalSupply() external view returns (uint256 _totalSupply) {
    return TOTAL_SUPPLY;
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

import './SafeMath.sol';
import './ERC20Basic.sol';

/**
 * @title BasicToken
 * @dev Basic version of Token, with no allowances.
 */
contract BasicToken is ERC20Basic {
  using SafeMath for uint256;
  mapping(address => uint256) public balances;

  /**
   * BasicToken transfer function
   * @dev transfer token for a specified address
   * @param _to address to transfer to.
   * @param _value amount to be transferred.
   */
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(msg.sender != _to, 'cannot send to same account');
    //Safemath fnctions will throw if value is invalid
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    emit Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
   * BasicToken balanceOf function
   * @dev Gets the balance of the specified address.
   * @param _owner address to get balance of.
   * @return uint256 amount owned by the address.
   */
  function balanceOf(address _owner) public view returns (uint256 bal) {
    return balances[_owner];
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

/**
 * @dev A standard for detecting smart contract interfaces.
 */
interface ERC165 {
  /**
   * @dev Checks if the smart contract includes a specific interface.
   * @notice This function uses less than 30,000 gas.
   * @param _interfaceID The interface identifier, as specified in ERC-165.
   */
  function supportsInterface(bytes4 _interfaceID) external view returns (bool);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

import './ERC20Basic.sol';

/**
 * ERC20 interface
 * @title ERC20 interface
 * @notice https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {
  /**
   * allowance
   */
  function allowance(address owner, address spender)
    public
    view
    returns (uint256);

  /**
   * transferFrom
   */
  function transferFrom(
    address from,
    address to,
    uint256 value
  ) public returns (bool);

  /**
   * approve
   */
  function approve(address spender, uint256 value) public returns (bool);

  /**
   * Approval event
   */
  event Approval(address indexed owner, address indexed spender, uint256 value);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

/**
 * @title ERC20Basic
 * @dev Simple version of ERC20 interface
 * @notice https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
  /**
   * @dev Returns the name of the token.
   * @return _name Token name.
   */
  function name() external view returns (string memory _name);

  /**
   * @dev Returns the symbol of the token.
   * @return _symbol Token symbol.
   */
  function symbol() external view returns (string memory _symbol);

  /**
   * @dev Returns the number of decimals the token uses.
   * @return _decimals Number of decimals.
   */
  function decimals() external view returns (uint8 _decimals);

  /**
   * @dev Returns the total token supply.
   * @return _totalSupply Total supply.
   */
  function totalSupply() external view returns (uint256 _totalSupply);

  /**
   * Balance of address
   */
  function balanceOf(address who) public view returns (uint256);

  /**
   * Transfer value to address
   */
  function transfer(address to, uint256 value) public returns (bool);

  /**
   * Transfer event
   */
  event Transfer(address indexed from, address indexed to, uint256 value);
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

contract Migrations {
  address public owner = msg.sender;
  uint256 public lastCompletedMigration;

  modifier restricted() {
    require(
      msg.sender == owner,
      // solhint-disable-next-line quotes
      "This function is restricted to the contract's owner"
    );
    _;
  }

  function setCompleted(uint256 completed) public restricted {
    lastCompletedMigration = completed;
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 * @notice https://github.com/OpenZeppelin/zeppelin-solidity/blob/master/contracts/math/SafeMath.sol
 */
library SafeMath {
  /**
   * SafeMath mul function
   * @dev function for safe multiply
   **/
  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  /**
   * SafeMath div funciotn
   * @dev function for safe devide
   **/
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a / b;
    return c;
  }

  /**
   * SafeMath sub function
   * @dev function for safe subtraction
   **/
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
   * SafeMath add fuction
   * @dev function for safe addition
   **/
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }

  function toString(uint256 _i) internal pure returns (string memory) {
    if (_i == 0) {
      return '0';
    }
    uint256 j = _i;
    uint256 len;
    while (j != 0) {
      len++;
      j /= 10;
    }
    bytes memory bstr = new bytes(len);
    uint256 k = len;
    while (_i != 0) {
      k = k - 1;
      uint8 temp = (48 + uint8(_i - (_i / 10) * 10));
      bytes1 b1 = bytes1(temp);
      bstr[k] = b1;
      _i /= 10;
    }
    return string(bstr);
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

import './ERC165.sol';

/**
 * @dev Implementation of standard for detect smart contract interfaces.
 */
contract SupportsInterface is ERC165 {
  /**
   * @dev Mapping of supported intefraces.
   * @notice You must not set element 0xffffffff to true.
   */
  mapping(bytes4 => bool) internal supportedInterfaces;

  /**
   * @dev Contract constructor.
   */
  constructor() public {
    supportedInterfaces[0x01ffc9a7] = true; // ERC165
  }

  /**
   * @dev Function to check which interfaces are suported by this contract.
   * @param _interfaceID Id of the interface.
   */
  function supportsInterface(bytes4 _interfaceID) external view returns (bool) {
    return supportedInterfaces[_interfaceID];
  }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.5.8;

import './SafeMath.sol';
import './BasicToken.sol';
import './ERC20.sol';

/**
 * @title Token
 * @dev Token to meet the ERC20 standard
 * @notice https://github.com/ethereum/EIPs/issues/20
 */
contract Token is ERC20, BasicToken {
  mapping(address => mapping(address => uint256)) private allowed;

  /**
   * Token transferFrom function
   * @dev Transfer tokens from one address to another
   * @param _from address to send tokens from
   * @param _to address to transfer to
   * @param _value amout of tokens to be transfered
   */
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  ) public returns (bool) {
    uint256 _allowance = allowed[_from][msg.sender];
    // Safe math functions will throw if value invalid
    balances[_to] = balances[_to].add(_value);
    balances[_from] = balances[_from].sub(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  /**
   * Token approve function
   * @dev Aprove address to spend amount of tokens
   * @param _spender address to spend the funds.
   * @param _value amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) public returns (bool) {
    // To change the approve amount you first have to reduce the addresses`
    // allowance to zero by calling `approve(_spender, 0)` if it is not
    // already 0 to mitigate the race condition described here:
    // @notice https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    assert((_value == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * Token allowance method
   * @dev Ckeck that owners tokens is allowed to send to spender
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifing the amount of tokens still available for the spender.
   */
  function allowance(address _owner, address _spender)
    public
    view
    returns (uint256 remaining)
  {
    return allowed[_owner][_spender];
  }
}
