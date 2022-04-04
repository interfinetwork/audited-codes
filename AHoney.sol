// SPDX-License-Identifier: MIT
pragma solidity ^0.8.10;

// OpenZeppelin Contracts (last updated v4.5.0) (token/ERC20/IERC20.sol)
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
// OpenZeppelin Contracts v4.4.1 (access/Ownable.sol)

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

// OpenZeppelin Contracts v4.4.1 (utils/Context.sol)

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
/*
 * @title MerkleProof
 * @dev Merkle proof verification
 * @note Based on https://github.com/ameensol/merkle-tree-solidity/blob/master/src/MerkleProof.sol
 */
library MerkleProof {
  /*
   * @dev Verifies a Merkle proof proving the existence of a leaf in a Merkle tree. Assumes that each pair of leaves
   * and each pair of pre-images is sorted.
   * @param _proof Merkle proof containing sibling hashes on the branch from the leaf to the root of the Merkle tree
   * @param _root Merkle root
   * @param _leaf Leaf of Merkle tree
   */
  function verifyProof(bytes _proof, bytes32 _root, bytes32 _leaf) public pure returns (bool) {
    // Check if proof length is a multiple of 32
    if (_proof.length % 32 != 0) return false;

    bytes32 proofElement;
    bytes32 computedHash = _leaf;

    for (uint256 i = 32; i <= _proof.length; i += 32) {
      assembly {
        // Load the current element of the proof
        proofElement := mload(add(_proof, i))
      }

      if (computedHash < proofElement) {
        // Hash(current computed hash + current element of the proof)
        computedHash = keccak256(computedHash, proofElement);
      } else {
        // Hash(current element of the proof + current computed hash)
        computedHash = keccak256(proofElement, computedHash);
      }
    }

    // Check if the computed hash (root) is equal to the provided root
    return computedHash == _root;
  }
}

contract AHoney is Ownable {

    IERC20 HONEY;
    IERC20 DAI;

    bytes32 public merkleRoot;

    event BuyHoney(address sender, uint aHNY, uint DAIPaid);
    event Redeem(address sender, uint amount);

    mapping(address => uint) public aHNYBalance;
    uint public HNYPrice = 100;

    bool public isRedeemLocked = true;
    uint public aHNYReserve = 1000000 ether;
    uint public HNYReserve;

    uint constant maxaHNY = 1000000 ether;
    uint public maxCap = 50 ether;

    mapping(address => uint) public totalRedeemed;
    mapping(address => uint) public totalaHNYPurchased;

    /**
    * @dev Prevents redeeming of tokens until unlocked
    */
    modifier onlyIfUnlocked() {
        require(!isRedeemLocked, "Redeem is currently locked!");
        _;
    }

    /**
    * @dev Only allows purchasing of aHNY if redeeming is locked
    */
    modifier onlyIfLocked() {

        require(isRedeemLocked, "Purchasing is Locked!");
        _;

    }

    /**
    * @dev checks if the wallet address is whitelisted by verifying if the proof is valid
    */
    modifier onlyWhitelisted(bytes32[] calldata merkleProof) {
        bytes32 leaf = keccak256(abi.encodePacked(msg.sender));
        require(MerkleProof.verify(merkleProof, merkleRoot, leaf), "Not a whitelisted address");
        _;
    }

    /**
    * @dev sets the address
    */
    constructor(address _honey, address _dai) {
        HONEY = IERC20(_honey);
        DAI = IERC20(_dai);
    }

     /**
    * @dev Purchase aHNY for dai
    * Requires the caller to be on the whitelist, and redeeming to be locked
    */
    function buy(uint quantity, bytes32[] calldata proof) public onlyIfLocked onlyWhitelisted(proof) {

        require(quantity > 0, "Quantity should be non-zero");

        require(quantity % 10 ether == 0, "Quantity should be multiples of 10");

        uint amount = quantity * HNYPrice;

        require((totalaHNYPurchased[msg.sender] + quantity) <= maxCap, "Quantity exceeding max cap");
        require(DAI.balanceOf(msg.sender) >= amount, "Insufficient DAI balance");
        require(amount <= aHNYReserve, "Insufficient aHNY balance");
        
        DAI.transferFrom(msg.sender, address(this), amount);
        aHNYBalance[msg.sender] += quantity;
        totalaHNYPurchased[msg.sender] += quantity;
        aHNYReserve -= amount;

        emit BuyHoney(msg.sender, quantity, amount);
    }

    /**
    * @dev Redeems purchased aHNY for honey
    * Requires redeeming to be unlocked
    */
    function redeem(uint amount) public onlyIfUnlocked {
        uint balance = aHNYBalance[msg.sender];
        require(balance >= amount, "Insufficient aHNY balance to redeem");

        aHNYBalance[msg.sender] -= amount;
        HNYReserve -= amount;
        totalRedeemed[msg.sender] += amount;
        HONEY.transfer(msg.sender, amount);

        emit Redeem(msg.sender, amount);
    }


    // View functions

    function aHNYBalanceOf(address _addr) public view returns(uint) {
        return aHNYBalance[_addr];
    }

    function totalHNYRedeemed(address _addr) public view returns(uint) {
        return totalRedeemed[_addr];
    }

    function getTotalPurchased() public view returns(uint) {

        return maxaHNY - aHNYReserve;

    }

    // Owner functions

    /**
    * @dev set the honey token contract address address
    * Requires the sender to be the owner of this contract
    */
    function SetHoneyAddress(address _honey) public onlyOwner {

        HONEY = IERC20(_honey);

    }

    /**
    * @dev Deposits honey into the contract, updating reserves
    * Requires the sender to be the owner of this contract, and prevents depositing more honey than aHNY purchased
    */
    function HNYDeposit(uint amount) public onlyOwner {

        require(HONEY.balanceOf(msg.sender) >= amount, "Insufficient token balance to deposit!");
        require(HNYReserve + amount <= getTotalPurchased(), "Depositing more honey than aHny purchased");
        HONEY.transferFrom(msg.sender, address(this), amount);
        HNYReserve += amount;
        
    }

    /**
    * @dev Sets the merkle root, which is used to verify if a address is on the whitelist
    * Requires the sender to be the owner of this contract
    */
    function updateMerkleRoot(bytes32 root) public onlyOwner {
        merkleRoot = root;
    }

    /**
    * @dev Sets the lock, determining if aHNY can be bought, or Hony can be redeemed
    * Requires the sender to be the owner of this contract
    */
    function setRedeemLock(bool _value) public onlyOwner {
        isRedeemLocked = _value;
    }

    /**
    * @dev Withdraws DAI from the contract to the callers wallet
    * Requires the sender to be the owner of this contract
    */
    function withdrawDai() public onlyOwner {

		uint256 balance = DAI.balanceOf(address(this));
		DAI.transfer(msg.sender, balance);
	}

}