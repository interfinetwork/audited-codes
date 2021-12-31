// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

interface IMelodity {
    /**
     * Lock the provided amount of MELD for "relativeReleaseTime" seconds starting from now
     * NOTE: This method is capped
     * NOTE: time definition in the locks is relative!
     */
    function insertLock(
        address account,
        uint256 amount,
        uint256 relativeReleaseTime
    ) external;

    function saleLock(address account, uint256 amount) external;

	function burnUnsold(uint256 amountToBurn) external;
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "./IMelodity.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "./Referrable.sol";

contract Crowdsale is Referrable, ReentrancyGuard {
    IMelodity private melodity;
    PaymentTier[] public paymentTier;
	
    uint256 public saleStart = 1642147200;	// Friday, January 14, 2022 08:00:00
    uint256 public saleEnd = 1648771199;	// Thursday, March 31, 2022 23:59:59

	// Do inc. company wallet
	address public multisigWallet = 0x01Af10f1343C05855955418bb99302A6CF71aCB8;

    // used to store the amount of funds actually available for the contract,
    // this value is created in order to avoid eventually running out of funds in case of a large number of
    // interactions occurring at the same time.
    uint256 public supply = 350_000_000 ether;
    uint256 public distributed;

    event Buy(address indexed from, uint256 amount);
	event Destroied(uint256 burnedFunds);

    struct PaymentTier {
        uint256 rate;
        uint256 lowerLimit;
        uint256 upperLimit;
    }

	mapping(address => uint256) public toRefund;

	/**
     * Network: Binance Smart Chain (BSC)
     * Melodity Bep20: 0x13E971De9181eeF7A4aEAEAA67552A6a4cc54f43

	 * Network: Binance Smart Chain TESTNET (BSC)
     * Melodity Bep20: 0x5EaA8Be0ebe73C0B6AdA8946f136B86b92128c55

	 * Referrable prize 0.5%
     */
    constructor() Referrable(5, 1) {
        melodity = IMelodity(0x13E971De9181eeF7A4aEAEAA67552A6a4cc54f43);

		paymentTier.push(
			PaymentTier({
				rate: 6000,
				lowerLimit: 0,
				upperLimit: 25_000_000_000000000000000000
			})
		);
		paymentTier.push(
			PaymentTier({
				rate: 3000,
				lowerLimit: 25_000_000_000000000000000000,
				upperLimit: 125_000_000_000000000000000000
			})
		);
		paymentTier.push(
			PaymentTier({
				rate: 1500,
				lowerLimit: 125_000_000_000000000000000000,
				upperLimit: 225_000_000_000000000000000000
			})
		);
		paymentTier.push(
			PaymentTier({
				rate: 750,
				lowerLimit: 225_000_000_000000000000000000,
				upperLimit: 325_000_000_000000000000000000
			})
		);
		paymentTier.push(
			PaymentTier({
				rate: 375,
				lowerLimit: 325_000_000_000000000000000000,
				upperLimit: 350_000_000_000000000000000000
			})
		);
    }

        receive() external payable {
        revert("Direct funds receiving not enabled, call 'buy' directly");
    }

    function buy(address _ref) public nonReentrant payable {
		require(
			block.timestamp > saleStart,
			"ICO not started yet, come back starting from Friday, January 14, 2022 08:00:00"
		);
		require(
			block.timestamp < saleEnd,
			"ICO ended, sorry you're too late"
		);
		require(
			supply > 0,
			"ICO ended, everything was sold"
		);

        // compute the amount of token to buy based on the current rate
        (uint256 tokensToBuy, uint256 exceedingEther) = computeTokensAmount(msg.value);

		// refund eventually exceeding eth
        if(exceedingEther > 0) {
			uint256 _toRefund = toRefund[msg.sender] + exceedingEther;
			toRefund[msg.sender] = _toRefund;
        }

		// avoid impossibility to transfer funds to smart contracts (like gnosis safe multisig).
		// this is a workaround for the 2300 fixed gas problem
		(bool success, ) = multisigWallet.call{value: msg.value - exceedingEther}("");
		require(success, "Unable to proxy the transferred funds to the multisig wallet");

		(uint256 referredPrize, uint256 totalPrize) = computeReferralPrize(_ref, tokensToBuy);

		// change the core value asap
		distributed += tokensToBuy + totalPrize;
		supply -= tokensToBuy + totalPrize;

		tokensToBuy += referredPrize;
        
        // Mint new tokens for each submission
		melodity.saleLock(msg.sender, tokensToBuy);
        emit Buy(msg.sender, tokensToBuy);
    }    

    function computeTokensAmount(uint256 funds) public view returns(uint256, uint256) {
        uint256 futureMinted = distributed;
        uint256 tokensToBuy;
        uint256 currentRoundTokens;      
        uint256 etherUsed = funds; 
        uint256 futureRound; 
        uint256 rate;
        uint256 upperLimit;

        for(uint256 i = 0; i < paymentTier.length; i++) {
            // minor performance improvement, caches the value
            upperLimit = paymentTier[i].upperLimit;

            if(
                etherUsed > 0 &&                                 // Check if there are still some funds in the request
                futureMinted >= paymentTier[i].lowerLimit &&     // Check if the current rate can be applied with the lowerLimit
                futureMinted < upperLimit                        // Check if the current rate can be applied with the upperLimit
                ) {
                // minor performance improvement, caches the value
                rate = paymentTier[i].rate;
                
                // Keep a static counter and reset it in each round
                // NOTE: Order is important in value calculation
                currentRoundTokens = etherUsed * 1e18 / 1 ether * rate;

                // minor performance optimization, caches the value
                futureRound = futureMinted + currentRoundTokens;
                // If the tokens to mint exceed the upper limit of the tier reduce the number of token bounght in this round
                if(futureRound >= upperLimit) {
                    currentRoundTokens -= futureRound - upperLimit;
                }

                // Update the futureMinted counter with the currentRoundTokens
                futureMinted += currentRoundTokens;

                // Recomputhe the available funds
                etherUsed -= currentRoundTokens * 1 ether / rate / 1e18;

                // And add the funds to the total calculation
                tokensToBuy += currentRoundTokens;
            }
        }

        // minor performance optimization, caches the value
        uint256 new_minted = distributed + tokensToBuy;
        uint256 exceedingEther;
        // Check if we have reached and exceeded the funding goal to refund the exceeding ether
        if(new_minted >= supply) {
            uint256 exceedingTokens = new_minted - supply;
            
            // Convert the exceedingTokens to ether and refund that ether
            exceedingEther = etherUsed + (exceedingTokens * 1 ether / paymentTier[paymentTier.length -1].rate / 1e18);

            // Change the tokens to buy to the new number
            tokensToBuy -= exceedingTokens;
        }

        return (tokensToBuy, exceedingEther);
    }

    function destroy() nonReentrant public {
		// permit the destruction of the contract only an hour after the end of the sale,
		// this avoid any evil miner to trigger the function before the real ending time
		require(
			block.timestamp > saleEnd + 1 hours, 
			"Destruction not enabled yet, you may call this function starting from Friday, April 1, 2022 00:59:59 UTC"
		);
		require(supply > 0, "Remaining supply already burned or all funds sold");
		uint256 remainingSupply = supply;
		
        // burn all unsold MELD
		supply = 0;

		emit Destroied(remainingSupply);
    }

	function redeemReferralPrize() public nonReentrant override {
		require(
			referrals[msg.sender].prize != 0,
			"No referral prize to redeem"
		);
		require(
			block.timestamp > saleEnd, 
			"Referral prize can be redeemed only after the end of the ICO"
		);

		uint256 prize = referrals[msg.sender].prize;
		referrals[msg.sender].prize = 0;

		melodity.insertLock(msg.sender, prize, 0);
		emit ReferralPrizeRedeemed(msg.sender);
	}

	function refund() public nonReentrant {
		require(toRefund[msg.sender] > 0, "Nothing to refund");

		uint256 _refund = toRefund[msg.sender];
		toRefund[msg.sender] = 0;

		// avoid impossibility to refund funds in case transaction are executed from a contract
		// (like gnosis safe multisig), this is a workaround for the 2300 fixed gas problem
		(bool refundSuccess, ) = msg.sender.call{value: _refund}("");
		require(refundSuccess, "Unable to refund exceeding ether");
	}

    function isStarted() public view returns(bool) { return block.timestamp >= saleStart; }
}
// SPDX-License-Identifier: MIT
pragma solidity 0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";

abstract contract Referrable {
	using EnumerableSet for EnumerableSet.AddressSet;

	event ReferralCreated(address creator);
	event ReferralUsed(address referrer, address referred);
	event ReferralPrizeRedeemed(address referrer);

	struct Referral {
		uint256 referrerPrize;
		uint256 referredPrize;
		uint256 prize;
	}

	mapping(address => Referral) public referrals;
	
	EnumerableSet.AddressSet private alreadyReferred;
	uint256 public baseReferral;
	uint256 public baseReferralDecimals;

	/**
		@param _baseReferral Maximum referral prize that will be splitted between the referrer
				and the referred
		@param _baseReferralDecimals Number of decimal under the base (18) the referral value is.
				This values allow for decimal values like 0.5%, the minimum is 0.[0 x 17 times]1 
	 */
	constructor(uint256 _baseReferral, uint256 _baseReferralDecimals) {
		baseReferralDecimals = _baseReferralDecimals;
		
		// high precision (18 decimals) the base referral is already in the normalized form
		// 1_[0 x 18 times] = 1%
		// 5_[0 x 17 times] = 0.5%
		baseReferral = _baseReferral * 10 ** (18 - _baseReferralDecimals);
	}

	/**
		@param _referrerPercent Percentage of baseReferral that is destinated to the referrer,
				18 decimal position needed for the unit
		@param _referredPercent Percentage of baseReferral that is destinated to the referred,
				18 decimal position needed for the unit
	 */
	function createReferral(uint256 _referrerPercent, uint256 _referredPercent) public {
		require(
			_referrerPercent + _referredPercent == 100 * 10 ** 18,
			"All the referral percentage must be distributed (100%)"
		);
		require(
			referrals[msg.sender].referrerPrize == 0 || referrals[msg.sender].referredPrize == 0,
			"Referral already initialized, unable to edit it"
		);
		require(
			referrals[msg.sender].prize == 0,
			"Referral has already been used, unable to edit it"
		);

		uint256 referrerPrize = baseReferral * _referrerPercent / 10 ** 20; // 18 decimals + transposition from integer to percentage
		uint256 referredPrize = baseReferral * _referredPercent / 10 ** 20; // 18 decimals + transposition from integer to percentage

		referrals[msg.sender] = Referral({
			referrerPrize: referrerPrize,
			referredPrize: referredPrize,
			prize: 0
		});

		emit ReferralCreated(msg.sender);
	}

	/**
		@param _ref Referrer address
		@param _value Value of the currency whose bonus should be computed
		@return (
			Referred bonus based on the submitted _value,
			Total value of the bonus, may be used for minting calculations
		)
	 */
	function computeReferralPrize(address _ref, uint256 _value) internal returns(uint256, uint256) {	
		if (
			// check if the referrer address is active and compute the referral if it is
			referrals[_ref].referrerPrize + referrals[_ref].referredPrize == baseReferral &&
			
			// check that no other referral have veen used before, if any referral have been used
			// any new ref-code will not be considered
			!alreadyReferred.contains(msg.sender)
			) {
			// insert the sender in the list of the referred user locking it from any other call
			alreadyReferred.add(msg.sender);

			uint256 referrerBonus = _value * referrals[_ref].referrerPrize / 10 ** 20; // 18 decimals + transposition from integer to percentage
			uint256 referredBonus = _value * referrals[_ref].referredPrize / 10 ** 20; // 18 decimals + transposition from integer to percentage

			referrals[_ref].prize += referrerBonus;

			emit ReferralUsed(_ref, msg.sender);
			return (referredBonus, referrerBonus + referredBonus);
		}
		// fallback to no bonus if the ref code is not active or already used a ref code
		return (0, 0);
	}

	function redeemReferralPrize() virtual public;

	function getReferrals() public view returns(Referral memory) {
		return referrals[msg.sender];
	}
}
