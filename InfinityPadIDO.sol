// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.6.12;
pragma experimental ABIEncoderV2;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 *
 *
 */

import "./common/SafeMath.sol";
import "./common/IBEP20.sol";

contract IPAD {
    address payable public owner;

    uint256 public transactionFees = 3;

    struct Buyer {
        uint256 tokenPurchased;
        address buyerAddress;
        uint256 paidAmount;
    }

    mapping(uint256 => Buyer[]) public buyerIndex;

    struct TokenInf {
        string tokenName;
        string tokenSymbol;
        uint256 decimal;
        uint256 totalSupply;
    }

    TokenInf public tokenInformation;

    struct Token {
        IBEP20 tokenAddress;
        uint256 tokenPrice;
        uint256 amount;
        uint256 tokenLeft;
        uint256 bnbCount;
        uint256 startTime;
        uint256 endTime;
        uint256 id;
        address payable seller;
        TokenInf tokenInf;
        bool status;
    }

    mapping(uint256 => Token) public token;

    uint256 serialNumber;

    constructor() public {
        owner = msg.sender;
    }

    event PurchasedTokens(
        uint256 indexed tokenId,
        address indexed buyerAddress,
        uint256 amountPaid,
        uint256 tokenPurchased
    );
    event RegisteredToken(Token token);
    event TokenDistribution(address indexed seller);
    event DeletedToken(uint256 tokenId);
    event TransactionFeesUpdate(uint256 ownerFees);
    event EmergencyWithdraw(address ownerAddress);

    modifier validateTokenId(uint256 id) {
        require(token[id].status == true, "Token do not exist");
        _;
    }

    modifier onlyOwner {
        require(msg.sender == owner, "Not admin");
        _;
    }

    modifier validateIDO(
        IBEP20 tokenAddress,
        uint256 tokenPrice,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    ) {
        require(tokenPrice > 0, "Token price should be greater than zero");
        require(amount > 0, "Amount should be greater than zero");
        require(
            SafeMath.add(block.timestamp, 604800) < startTime,
            "Enter correct start time"
        );
        require(endTime >= startTime, "Enter correct end time");
        uint256 balance = tokenAddress.balanceOf(address(msg.sender));
        require(balance >= amount, "Insufficient balance");

        _;
    }

    /*
     * @notice Submit token by seller on IPAD
     * @param   tokenAddress: Seller token's address
     * @param   tokenPrice: Seller token's price 
     * @param   amount: Amount of token deposited by seller on contract for selling
     * @param   startTime: Time at which selling starts
     * @param   endTime: Time at which selling ends

     */

    function submitToken(
        IBEP20 tokenAddress,
        uint256 tokenPrice,
        uint256 amount,
        uint256 startTime,
        uint256 endTime
    )
        external
        validateIDO(tokenAddress, tokenPrice, amount, startTime, endTime)
        returns (bool)
    {
        tokenAddress.transferFrom(msg.sender, address(this), amount);
        tokenInformation.tokenName = tokenAddress.name();
        tokenInformation.tokenSymbol = tokenAddress.symbol();
        tokenInformation.decimal = tokenAddress.decimals();
        tokenInformation.totalSupply = tokenAddress.totalSupply();
        serialNumber = SafeMath.add(serialNumber, 1);
        token[serialNumber] = Token({
            tokenAddress: tokenAddress,
            tokenPrice: tokenPrice,
            amount: amount,
            tokenLeft: amount,
            bnbCount: 0,
            startTime: startTime,
            endTime: endTime,
            id: serialNumber,
            seller: msg.sender,
            tokenInf: tokenInformation,
            status: true
        });

        emit RegisteredToken(token[serialNumber]);
        return true;
    }

    /*
     * @notice emergency Withdraw 
     * @param  id :Token id of the seller
       @dev only by owner
     */

    function emergencyWithdrawTokens(uint256 id)
        external
        payable
        validateTokenId(id)
        onlyOwner
    {
        require(token[id].status == true, "Assets are cliamed or deleted");
        token[id].tokenLeft=0;
        token[id].tokenAddress.transfer(owner, token[id].amount);
        if (token[id].bnbCount > 0) {
            uint256 bnbBalance=token[id].bnbCount;
            token[id].bnbCount=0;
            owner.transfer(bnbBalance);
        }

        token[id].status = false;
        emit EmergencyWithdraw(address(msg.sender));
    }

    /*
     * @notice Update transaction fees
     * @param  fees : Updated fees
       @dev only by owner
     */

    function updateFees(uint256 fees) external onlyOwner() {
        require(fees > 0 && fees <= 5, "Entered correct fees range");
        transactionFees = fees;
        emit TransactionFeesUpdate(transactionFees);
    }

    /*
     * @notice Purchase token
     * @param  id :Token id of the seller
     */

    function purchaseToken(uint256 id) external payable validateTokenId(id) {
        require(token[id].endTime >= block.timestamp, "Token sale over");

        require(token[id].startTime <= block.timestamp, "Selling not started");

        require(msg.value > 0, "Insufficient balance");

        uint256 tokenPurchase =
            SafeMath.div(SafeMath.mul(token[id].tokenPrice, msg.value), 10**18);

        require(
            tokenPurchase <= token[id].tokenLeft && tokenPurchase > 0,
            "Token limit reached"
        );

        buyerIndex[id].push(
            Buyer({
                tokenPurchased: tokenPurchase,
                paidAmount: msg.value,
                buyerAddress: msg.sender
            })
        );

        token[id].tokenLeft = SafeMath.sub(token[id].tokenLeft, tokenPurchase);
        token[id].bnbCount = SafeMath.add(token[id].bnbCount, msg.value);

        emit PurchasedTokens(id, msg.sender, msg.value, tokenPurchase);
    }

    /*
     * @notice Claim Token
     * @param  id :Token id of the seller
     */

    function claimToken(uint256 id) public validateTokenId(id) onlyOwner {
        require(
            token[id].endTime <= block.timestamp || token[id].tokenLeft == 0,
            "Something went wrong"
        );
        require(buyerIndex[id].length > 0, "No buyer for the token");

        uint256 ownerFees;
        uint256 sellerAmount;

        for (uint256 i = 0; i < buyerIndex[id].length; i++) {
            token[id].tokenAddress.transfer(
                buyerIndex[id][i].buyerAddress,
                buyerIndex[id][i].tokenPurchased
            );
            uint256 deductedFees =
                SafeMath.div(
                    SafeMath.mul(transactionFees, buyerIndex[id][i].paidAmount),
                    100
                );
            ownerFees = SafeMath.add(ownerFees, deductedFees);
            sellerAmount = SafeMath.add(
                sellerAmount,
                SafeMath.sub(buyerIndex[id][i].paidAmount, deductedFees)
            );
            buyerIndex[id][i].tokenPurchased = 0;
            buyerIndex[id][i].paidAmount = 0;
        }

        token[id].bnbCount = 0;
        uint256 unSoldToken = token[id].tokenLeft;
        token[id].tokenLeft = 0;
        owner.transfer(ownerFees);
        token[id].seller.transfer(sellerAmount);
        if (unSoldToken != 0) {
            token[id].tokenAddress.transfer(token[id].seller, unSoldToken);
        }

        token[id].status = false;

        emit TokenDistribution(token[id].seller);
    }

    /*
     * @notice delete token 
     * @param  id :Token id of the seller
       @dev only by owner
     */

    function deleteToken(uint256 id) external validateTokenId(id) onlyOwner {
        require(
            token[id].status == false || token[id].startTime > block.timestamp,
            "Token is distributed or withdrawn or selling started"
        );

        if (token[id].tokenLeft > 0) {
            uint256 amount = token[id].tokenLeft;
            token[id].tokenLeft = 0;
            token[id].tokenAddress.transfer(token[id].seller, amount);
        }

        delete token[id];
        emit DeletedToken(id);
    }
}