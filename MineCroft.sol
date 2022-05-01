// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;
import "./Ownable.sol";

contract MineCroft is Ownable {
    uint256 public constant CROFT_TO_HIRE_1MINER = (100 * 1 days) / 9; //960k croft to hire 1 miner, 9%apr daily
    uint256 private constant PSN = 10000;
    uint256 private PSNH = 5000;
    uint256 private constant devFeeVal = 2;
    bool private _initialized;
    mapping(address => uint256) public croftMiners;
    mapping(address => uint256) private claimedCroft;
    mapping(address => uint256) private lastHireTime;
    mapping(address => address) private referrals;
    uint256 private marketCroft = 100000 * CROFT_TO_HIRE_1MINER;

    mapping(address => bool) private hasParticipated;
    uint256 public uniqueUsers;

    modifier initialized() {
        require(_initialized, "Contract not initialized");
        _;
    }

    function hireMiner(address ref) public initialized {
        if (
            ref != msg.sender &&
            referrals[msg.sender] == address(0) &&
            ref != address(0)
        ) {
            referrals[msg.sender] = ref;
        }

        uint256 croftUsed = getMyCroft(msg.sender);
        uint256 myCroftRewards = getCroftSincelastHireTime(msg.sender);
        claimedCroft[msg.sender] += myCroftRewards;

        uint256 newMiners = claimedCroft[msg.sender] / CROFT_TO_HIRE_1MINER;

        claimedCroft[msg.sender] -= (CROFT_TO_HIRE_1MINER * newMiners);
        croftMiners[msg.sender] += newMiners;

        lastHireTime[msg.sender] = block.timestamp;

        //send referral croft
        claimedCroft[referrals[msg.sender]] += croftUsed / 8;

        //boost market to nerf miners hoarding
        marketCroft += croftUsed / 5;

        if (!hasParticipated[msg.sender]) {
            hasParticipated[msg.sender] = true;
            uniqueUsers++;
        }
        if (!hasParticipated[ref] && ref != address(0)) {
            hasParticipated[ref] = true;
            uniqueUsers++;
        }
    }

    function sellCroft() public initialized {
        uint256 hasCroft = getMyCroft(msg.sender);
        uint256 croftValue = calculateCroftSell(hasCroft);
        uint256 fee = devFee(croftValue);
        claimedCroft[msg.sender] = 0;
        lastHireTime[msg.sender] = block.timestamp;
        marketCroft += hasCroft;
        payable(owner()).transfer(fee);
        payable(msg.sender).transfer(croftValue - fee);
        if (croftMiners[msg.sender] == 0) uniqueUsers--;
    }

    function buyCroft(address ref) external payable initialized {
        _buyCroft(ref, msg.value);
    }

    //to prevent sniping
    function seedMarket() public payable onlyOwner {
        require(!_initialized, "Already initialized");
        _initialized = true;
        _buyCroft(0x0000000000000000000000000000000000000000, msg.value);
    }

    function _buyCroft(address ref, uint256 amount) private {
        uint256 croftBought = calculateCroftBuy(
            amount,
            address(this).balance - amount
        );
        croftBought -= devFee(croftBought);
        uint256 fee = devFee(amount);
        payable(owner()).transfer(fee);
        claimedCroft[msg.sender] += croftBought;

        hireMiner(ref);
    }

    function croftRewardsToCRO(address adr) external view returns (uint256) {
        uint256 hasCroft = getMyCroft(adr);
        uint256 croftValue;
        try this.calculateCroftSell(hasCroft) returns (uint256 value) {
            croftValue = value;
        } catch {}
        return croftValue;
    }

    function calculateTrade(
        uint256 rt,
        uint256 rs,
        uint256 bs
    ) private view returns (uint256) {
        return (PSN * bs) / (PSNH + (PSN * rs + PSNH * rt) / rt);
    }

    function calculateCroftSell(uint256 croft) public view returns (uint256) {
        return calculateTrade(croft, marketCroft, address(this).balance);
    }

    function calculateCroftBuy(uint256 eth, uint256 contractBalance)
        public
        view
        returns (uint256)
    {
        return calculateTrade(eth, contractBalance, marketCroft);
    }

    function calculateCroftBuySimple(uint256 eth)
        external
        view
        returns (uint256)
    {
        return calculateCroftBuy(eth, address(this).balance);
    }

    function devFee(uint256 amount) private pure returns (uint256) {
        return (amount * devFeeVal) / 100;
    }

    function getMyCroft(address adr) public view returns (uint256) {
        return claimedCroft[adr] + getCroftSincelastHireTime(adr);
    }

    function getCroftSincelastHireTime(address adr)
        public
        view
        returns (uint256)
    {
        return getCroftAccumulationValue(adr) * croftMiners[adr];
    }

    /*for the front end, it returns a value between 0 and CROFT_TO_HIRE_1MINER, when reached CROFT_TO_HIRE_1MINER 
    user will stop accumulating croft and should compound or sell to get others
    */
    function getCroftAccumulationValue(address adr)
        public
        view
        returns (uint256)
    {
        uint256 timePassed = block.timestamp - lastHireTime[adr];
        return
            CROFT_TO_HIRE_1MINER < timePassed
                ? CROFT_TO_HIRE_1MINER
                : timePassed;
    }
    function contributeToTVL() external payable initialized{

    }
}
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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
// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

pragma solidity ^0.8.0;

import "./Context.sol";

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
