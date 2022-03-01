// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Context.sol";
import "./Ownable.sol";
import "./Pausable.sol";
import "./Establishments.sol";
import "./SafeMath.sol";

contract DevToken is Context, Ownable, Pausable, Establishments {
    using SafeMath for uint256;

    //  Our Tokens required variables that are needed to operate everything
    uint256 private _totalSupply;
    uint8 private _decimals;
    string private _symbol;
    string private _name;

    // _balances is a mapping that contains a address as KEY and the balance of the address as the value
    mapping(address => uint256) private _balances;

    // _balances dogscrew utility token balance
    mapping(address => uint256) private dousd_balances;

    // _allowances is used to manage and control allownace An allowance is the right to use another accounts balance, or part of it
    mapping(address => mapping(address => uint256)) private _allowances;

    // Events are created below. Transfer event is a event that notify the blockchain that a transfer of assets has taken place
    event Transfer(address indexed from, address indexed to, uint256 value);

    // Blacklist that restrict swap.
    mapping(address => bool) public blacklist;

    //  Approval is emitted when a new Spender is approved to spend Tokens on the Owners account
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        string memory token_name,
        string memory short_symbol,
        uint8 token_decimals,
        uint256 token_totalSupply
    ) {
        _name = token_name;
        _symbol = short_symbol;
        _decimals = token_decimals;

        _totalSupply = token_totalSupply * (uint256(10)**_decimals);
        _balances[owner()] = _totalSupply;

        emit Transfer(address(0), address(this), _totalSupply);
    }

    // decimals will return the number of decimal precision the Token is deployed with
    function decimals() external view returns (uint8) {
        return _decimals;
    }

    // symbol will return the Token's symbol
    function symbol() external view returns (string memory) {
        return _symbol;
    }

    // name will return the Token's symbol
    function name() external view returns (string memory) {
        return _name;
    }

    // totalSupply will return the tokens total supply of tokens
    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    // balanceOf will return the account balance for the given account (DOGSC)
    function balanceOf(address account) external view returns (uint256) {
        return _balances[account];
    }

    // balanceOf will return the account balance for the given account (DOUSD)
    function balanceOfDogsUSD(address account) external view returns (uint256) {
        return dousd_balances[account];
    }

    // _mint will create tokens on the address inputted and then increase the total supply
    function _mint(address account, uint256 amount) internal {
        require(account != address(0), "DevToken: cannot mint to zero address");

        // Increase total supply
        _totalSupply = _totalSupply.add(amount);

        // Add amount to the account balance using the balance mapping
        _balances[account] = _balances[account].add(amount);

        // Emit our event to log the action
        emit Transfer(address(0), account, amount);
    }

    // _burn will destroy tokens from an address inputted and then decrease total supply
    // An Transfer event will emit with receiever set to zero address
    function _burn(address account, uint256 amount) internal {
        require(
            account != address(0),
            "DevToken: cannot burn from zero address"
        );
        require(
            _balances[account] >= amount,
            "DevToken: Cannot burn more than the account owns"
        );

        // Remove the amount from the account balance
        _balances[account] = _balances[account].sub(
            amount,
            "DevToken: burn amount exceeds balance"
        );

        // Decrease totalSupply
        _totalSupply = _totalSupply.sub(amount);

        // Emit event, use zero address as reciever
        emit Transfer(account, address(0), amount);
    }

    //  burn is used to destroy tokens on an address
    function burn(address account, uint256 amount)
        public
        onlyOwner
        returns (bool)
    {
        _burn(account, amount);
        return true;
    }

    //  mint is used to create tokens and assign them to msg.sender
    function mint(address account, uint256 amount)
        public
        onlyOwner
        returns (bool)
    {
        _mint(account, amount);
        return true;
    }

    //  transfer is used to transfer funds from the sender to the recipient  This function is only callable from outside the contract. For internal usage see
    function transfer(address recipient, uint256 amount)
        external
        whenNotPaused
        returns (bool)
    {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    // _transfer is used for internal transfers
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        require(sender != address(0), "DevToken: transfer from zero address");
        require(recipient != address(0), "DevToken: transfer to zero address");
        require(
            _balances[sender] >= amount,
            "DevToken: cant transfer more than your account holds"
        );

        _balances[sender] = _balances[sender].sub(
            amount,
            "DEVTOKEN: transfer amount exceeds balance"
        );

        _balances[recipient] = _balances[recipient].add(amount);

        emit Transfer(sender, recipient, amount);
    }

    //  getOwner just calls Ownables owner function.
    function getOwner() external view returns (address) {
        return owner();
    }

    //  allowance is used view how much allowance an spender has
    function allowance(address owner, address spender)
        external
        view
        returns (uint256)
    {
        return _allowances[owner][spender];
    }

    // approve will use the senders address and allow the spender to use X amount of tokens on his behalf
    function approve(address spender, uint256 amount)
        external
        whenNotPaused
        returns (bool)
    {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    // _approve is used to add a new Spender to a Owners account
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal {
        require(
            owner != address(0),
            "DevToken: approve cannot be done from zero address"
        );
        require(
            spender != address(0),
            "DevToken: approve cannot be to zero address"
        );

        // Set the allowance of the spender address at the Owner mapping over accounts to the amount
        _allowances[owner][spender] = amount;

        emit Approval(owner, spender, amount);
    }

    // transferFrom is uesd to transfer Tokens from a Accounts allowance Spender address should be the token holder
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external whenNotPaused returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(
            currentAllowance >= amount,
            "DevToken: You cannot spend that much on this account"
        );

        _approve(sender, _msgSender(), currentAllowance.sub(amount));

        return true;
    }

    // Adds allowance to a account from the function caller address
    function increaseAllowance(address spender, uint256 addedValue)
        public
        whenNotPaused
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].add(addedValue)
        );

        return true;
    }

    // Decrease the allowance on the account inputted from the caller address
    function decreaseAllowance(address spender, uint256 subtractedValue)
        public
        whenNotPaused
        returns (bool)
    {
        _approve(
            _msgSender(),
            spender,
            _allowances[_msgSender()][spender].sub(
                subtractedValue,
                "DEVTOKEN: decreased allowance below zero"
            )
        );

        return true;
    }

    // GAME

    // Start and stop swap
    bool public swapActive = true;

    // Start and stop Attack
    bool public attackActive = true;

    // tokens busd for dogsc
    uint256 public swapAmount = 1;

    // change percentage of crew damaged
    uint256 public percentageOfCrewDamaged = 25;

    // early withdrawal penalty
    uint256 public penalty = 75;

    // ramdom number generator
    uint256 randNonce = 0;

    // winner struct
    struct winnerStruct {
        uint256 earned_tokens;
        uint256 win_rate;
        uint256 winner;
        bool damaged_crew;
        bool status;
    }

    // Attack struct
    event EventSendAttack(
        address attack_you,
        uint256 earned_tokens,
        uint256 win_rate,
        uint256 winner,
        bool damaged_crew,
        bool status
    );

    // event emit
    event EventLifeContract(
        address attack_you,
        string idCrew,
        uint256 amounttoken,
        bool status
    );
    // from DOUSD -> DOGSC
    event _swapDOUSDfromDOGSC(
        address buyer,
        uint256 dogsc,
        uint256 dousd,
        bool discount
    );

    // Edit reserved whitelist spots
    function editBlackList(address _address, bool _block)
        public
        onlyOwner
    {
        blacklist[_address] = _block;
    }

    // check if your account is blocked
    function blockedAccount(address _address) public view returns (bool) {
        return blacklist[_address];
    }

    //  we change utility token (DOUSD) of the game for dogs (DOGS) /  DOUSD -> DOGSC
    function swaDOUSDFromDOGSC(uint256 tokenAmountToDOUSD, bool discount)
        public
        whenNotPaused
        returns (bool)
    {
        // verificamos que le swap este activo
        require(swapActive, "swap isn't active");

        // check if your account is blocked
        bool isBlocked = blacklist[_msgSender()];
        require(!isBlocked, "Your account is blocked");

        // Check that the requested amount of tokens to sell is more than 0
        require(
            tokenAmountToDOUSD > 0,
            "Specify an amount of token greater than zero"
        );

        // Check that the user's token balance is enough to do the swap
        uint256 userBalance = dousd_balances[_msgSender()];
        require(
            userBalance >= tokenAmountToDOUSD,
            "Your balance is lower than the amount of tokens you want to sell"
        );

        // quemo los token de utilidad (DOUSD)
        dousd_balances[_msgSender()] = dousd_balances[_msgSender()].sub(
            tokenAmountToDOUSD
        );

        uint256 amount = 0;
        if (discount) {
            uint256 _amount = tokenAmountToDOUSD * swapAmount;
            amount = (_amount * penalty) / 100;
        } else {
            amount = tokenAmountToDOUSD * swapAmount;
        }

        // Transfer token to the msg.sender
        _mint(_msgSender(), amount);

        // emitimos el evento
        emit _swapDOUSDfromDOGSC(
            _msgSender(),
            tokenAmountToDOUSD,
            amount,
            discount
        );

        return true;
    }

    // receives tokens for the operation of the game dynamics (DOGSC)
    function lifeContracts(uint256 tokenAmount, string memory idCrew)
        public
        returns (bool)
    {
        require(attackActive, "attack isn't active");

        // verifico que tenga token suficientes
        uint256 userBalance = _balances[_msgSender()];
        require(
            userBalance >= tokenAmount,
            "Your balance is lower than the amount of tokens you want to sell"
        );

        // le enviamos los tokens al contrato
        _balances[address(this)] = _balances[address(this)].add(tokenAmount);

        // quemamos los toke del sender
        _burn(_msgSender(), tokenAmount);

        emit EventLifeContract(_msgSender(), idCrew, tokenAmount, true);
        return true;
    }

    // function to choose a winner in the attack
    function sendAttack(uint256 establishmentId, uint256 crewLife)
        public
        payable
        returns (winnerStruct memory _propertyObj)
    {
        require(msg.value > 0, "Send BNB to buy some tokens");

        // verificamos que le swap este activo
        require(attackActive, "attack isn't active");

        uint256 userBalance = _balances[_msgSender()];

        // debe tener minimo un token de dogs
        require(userBalance >= 1, "you have to have minimum 1 dogs to attack");

        // obtenemos los datos de estableciemiento
        establishmentInfo storage s = _establishments[establishmentId];

        // tiene que enviar fee
        require(msg.value >= s.fee, "Send BNB to buy some tokens (FEE)");

        // verificamos que no esta cerrado
        require(s.status, "closed establishment");

        //  ejecutamaos el metodo que determina quien gana
        uint256 winner = randMod(100);
        // verificamos si la crew sufre danos
        bool damaged_crew = winner <= percentageOfCrewDamaged ? true : false;

        uint256 earned_tokens = 0;

        // si gana entra en este if
        if (winner <= s.win_rate) {
            // le pasamos los dogsUSd al balance del sender
            earned_tokens = calculateProfit(crewLife, s.earned_tokens);

            // le pasamos los dogsUSd al balance del sender
            dousd_balances[_msgSender()] = dousd_balances[_msgSender()].add(
                earned_tokens
            );

            // emitimos un evento
            emit EventSendAttack(
                _msgSender(),
                earned_tokens,
                s.win_rate,
                winner,
                damaged_crew,
                true
            );
            return
                winnerStruct(
                    earned_tokens,
                    winner,
                    s.win_rate,
                    damaged_crew,
                    true
                );
        }

        // emitimos el evento
        emit EventSendAttack(
            _msgSender(),
            earned_tokens,
            s.win_rate,
            winner,
            damaged_crew,
            false
        );
    }

    function calculateProfit(uint256 crewLife, uint256 earned_tokens)
        internal
        pure
        returns (uint256)
    {
        if (crewLife == 100) {
            return earned_tokens;
        }
        return (earned_tokens * crewLife) / 100;
    }

    // Defining a function to generate
    // a random number
    function randMod(uint256 _modulus) public returns (uint256) {
        // increase nonce
        randNonce++;
        return
            uint256(
                keccak256(
                    abi.encodePacked(block.timestamp, msg.sender, randNonce)
                )
            ) % _modulus;
    }

    // Start and stop Attack
    function setAttackActive(bool val) public onlyOwner {
        attackActive = val;
    }

    // Start and stop swap
    function setSwapActive(bool val) public onlyOwner {
        swapActive = val;
    }

    // change price swap
    function setPriceSwapActive(uint256 val) public onlyOwner {
        swapAmount = val;
    }

    // change percentage of crew damaged
    function changePercentageDamaged(uint256 val) public onlyOwner {
        percentageOfCrewDamaged = val;
    }

    // change early withdrawal penalty
    function changePenalty(uint256 val) public onlyOwner {
        penalty = val;
    }

    /**
     * @notice Allow the owner of the contract to withdraw BNB
     */
    function withdraw() public onlyOwner {
        uint256 ownerBalance = address(this).balance;
        require(ownerBalance > 0, "Owner has not balance to withdraw");

        (bool sent, ) = _msgSender().call{value: address(this).balance}("");
        require(sent, "Failed to send user balance back to the owner");
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

/*
 *
 * This contract is only required for intermediate, library-like contracts.
 */
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor() {}

    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view returns (bytes memory) {
        this;
        return msg.data;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(
        address indexed previousOwner,
        address indexed newOwner
    );

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(isOwner(), "Ownable: only owner can call this function");
        _;
    }

    /**
     * @dev Returns true if the caller is the current owner.
     */
    function isOwner() public view returns (bool) {
        return _msgSender() == _owner;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public onlyOwner {
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public onlyOwner {
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     */
    function _transferOwnership(address newOwner) internal {
        require(
            newOwner != address(0),
            "Ownable: only owner can call this function"
        );
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
    event Pause();
    event Unpause();

    bool public paused = false;

    //  modifier to allow actions only when the contract IS paused
    modifier whenNotPaused() {
        require(!paused);
        _;
    }

    //  modifier to allow actions only when the contract IS NOT paused
    modifier whenPaused() {
        require(paused);
        _;
    }

    // called by the owner to pause, triggers stopped state
    function pause() public onlyOwner whenNotPaused returns (bool) {
        paused = true;
        emit Pause();
        return true;
    }

    // called by the owner to unpause, returns to normal state
    function unpause() public onlyOwner whenPaused returns (bool) {
        paused = false;
        emit Unpause();
        return true;
    }

    // used to check if the contract is paused
    function getStatusPause() public view returns (bool) {
        return paused;
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./SafeMath.sol";

contract Establishments is Ownable {
    using SafeMath for uint256;

    struct establishmentInfo {
        string name;
        string imagen;
        uint256 fee;
        uint256 earned_tokens;
        uint256 mp_min;
        uint256 mp_max;
        uint256 win_rate;
        bool status;
    }

    mapping(uint256 => establishmentInfo) _establishments;
    uint256[] public establishmentSid;

    function registerEstablishment(
        string memory _name,
        uint256 _fee,
        uint256 _earned_tokens,
        uint256 _mp_min,
        uint256 _mp_max,
        uint256 _win_rate,
        bool _status,
        uint256 _id
    ) public onlyOwner {
        establishmentInfo storage newEstablishment = _establishments[_id];
        newEstablishment.name = _name;
        newEstablishment.fee = _fee;
        newEstablishment.earned_tokens = _earned_tokens;
        newEstablishment.mp_min = _mp_min;
        newEstablishment.mp_max = _mp_max;
        newEstablishment.win_rate = _win_rate;
        newEstablishment.status = _status;
        establishmentSid.push(_id);
    }

    // update of establishments
    function updateEstablishment(
        string memory _name,
        uint256 _fee,
        uint256 _earned_tokens,
        uint256 _mp_min,
        uint256 _mp_max,
        uint256 _win_rate,
        bool _status,
        uint256 id
    ) public onlyOwner returns (bool success) {
        _establishments[id].status = false;
        _establishments[id].name = _name;
        _establishments[id].fee = _fee;
        _establishments[id].earned_tokens = _earned_tokens;
        _establishments[id].mp_min = _mp_min;
        _establishments[id].mp_max = _mp_max;
        _establishments[id].win_rate = _win_rate;
        _establishments[id].status = _status;
        return true;
    }

    // we deactivate establishment
    function deleteEstablishment(uint256 id)
        public
        onlyOwner
        returns (bool success)
    {
        _establishments[id].status = false;
        return true;
    }

    // we get the amount of registered establishment
    function getEstablishmentCount() public view returns (uint256 entityCount) {
        return establishmentSid.length;
    }

    // we get establishments
    function getEstablishment(uint256 id)
        public
        view
        returns (
            string memory,
            uint256,
            uint256,
            uint256,
            uint256,
            uint256,
            bool
        )
    {
        establishmentInfo storage s = _establishments[id];
        return (
            s.name,
            s.fee,
            s.earned_tokens,
            s.mp_min,
            s.mp_max,
            s.win_rate,
            s.status
        );
    }
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/math/SafeMath.sol)
pragma solidity ^0.8.4;


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