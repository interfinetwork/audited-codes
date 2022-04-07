/**
 *  SPDX-License-Identifier: MIT
 *
 *                                .::----::.
 *                           .-=+*++======++*++-
 *                         =++=------------+*+-
 *                       +*=-----------=++=:
 *                     =*=-----------++=.
 *                    *+----------=*=.
 *                  .#=---------+*-
 *                 :#=--------+*:             .-=++*****+=:   .:---.     ....
 *                .#=++=----+*:           .=*#*++=++===+##%%%%%###%%%+++++==++++=:
 *             .-+**+#*---=*=   .:      :##+=*#*=-:::-==+--*#####%%=-=*=------::-*#:
 *           -++=--=#+---=*.   =%%%.  .*#-:+=:           :+=:+##%@=--##----------:=%*
 *         -*+-----#=---+*:==  -%#%+ :%+ -+        :::.    .*:+#%*-----------------=##
 *        =*------#+---=* %##%: :*%%#%+ -+          *++=.    *:+%+------------------=**
 *       :#------+#---=#  ####%#*+*@@#. #    .     -@@#++:    * *+-------------------+*-
 *       #=------#=---#:   =*#%%##%@@# :+   :+-==+#@@@@*++    # ++-------------------+-*
 *       %-------#---=*     .====*%@%#  *   .++*@@@@@#=:--    # -*-------------------+-%
 *       @------=#---+=     *#####%%##- +:   .=++##%#        ==  %-------------------=-#
 *       #=-----=#---*-      -+++= =%#*. *:    :-==+=.      =+   %-------------------=-%
 *       =*------%---*-            -%##:  =+. ----------:..*-   :#-------------------=-#
 *       .%------#=--+=             %##:   .-.           .-.    =+--------------------=*
 *      -***-----+*--=#             -%##:                       ++--------------------*-
 *     -*--#+-----#=--#:             ###=                       .%=------------------=%
 *     %=--=%=----=#--=%             :%###+                     :##+-----=*##%%%%#=--#.
 *     %----=#=----+#--=*             =@###***:                 :*-#%###%%#######@#*#:
 *     #=----=#=----+#=-+*            *@@#######+**::.          :*-#*****##%%**#**
 *     .#-----=#=----=#=-+*           .@@@@%#########***=**-=:  .#-****#%#%#***%+:
 *      :#=----=#+----=#+-=#:          -@@@@%#%################*:%-=%**%##%#***%+:
 *       .#=-----#+-----**--*+.         %@@@@@@##################%=-###%#####**%+#:
 *         +*=----+#=----+#=-=*+.       @@@@@@@%#####%############%--#%####*#*##+-=*
 *          -+*=---=**=----**=-=**=:. -%@@@@@@@@@###@%#############*--=++++++=---=#=
 *         .%*:+*=---=**=----+%##***##%@@@@@@*+*@@@@@%#####%#########=--------=*#%#%=
 *         :#=*+:=*+---+%*****%#*****##-=-=+*====%@@@@%####@%#%%#####%#*****#%####%*+
 *          #=-=*+-:+*%************###%%*+=====-#%%@@@@@%#%@%%=@#############%##@%#
 *           **---=*+-=+###******#+===========*#%##%@@%@@@*.: =%##%%####%@###%%%+.
 *            :+*+=--=+#*#%#####*#+==========+#%###@@@%@@@@*::**+: %###%@@####*=
 *               .:==++%***********###*+=====-###%@@@@@%@@@@@%=::=#%#%@@%%#%+
 *                      -=+*####*###%*====-==+@@@@@@@@@@%@@%%@@@@@@%%%@# :=.
 *                          =%##%%####%%%%%%%@@@***+++@@@%%@@#%@@@#:  =
 *                           +%###############%%@%%@@@@@@@@%%@@@*.
 *                             +#%%###############%@@@@@@%%@%#=
 *                               %%%%%%%%%%%%%%####%%%@%@@#=.
 *                               :@##@..@##@:.:----::.
 *                                #++#-=+-=#*+**#%:
 *                            =#=+++++**++*@#=++*@+
 *                            ::::..  ..:--+-    :
 *
 *  Parrotly (PBIRB) Token Presale
 *
 *  Website -------- https://parrotly.finance
 *  Whitepaper ----- https://parrotly.finance/resources/docs/Parrotly_Whitepaper.pdf
 *  Twitter -------- https://twitter.com/ParrotlyFinance
 **/

pragma solidity 0.8.13;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title Crowdsale
 * @dev
 * https://github.com/OpenZeppelin/openzeppelin-contracts/blob/58a3368215581509d05bd3ec4d53cd381c9bb40e/contracts/crowdsale/Crowdsale.sol
 * Crowdsale is a base contract for managing a token crowdsale,
 * allowing investors to purchase tokens with ether. This contract implements
 * such functionality in its most fundamental form and can be extended to provide additional
 * functionality and/or custom behavior.
 * The external interface represents the basic interface for purchasing tokens, and conforms
 * the base architecture for crowdsales. It is *not* intended to be modified / overridden.
 * The internal interface conforms the extensible and modifiable surface of crowdsales. Override
 * the methods to add functionality. Consider using 'super' where appropriate to concatenate
 * behavior.
 * UPDATED FOR 0.8.13 (added abstract keyword)
 */
abstract contract Crowdsale is Context, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    // The token being sold
    IERC20 private _token;

    // Address where funds are collected
    address payable private _wallet;

    // How many token units a buyer gets per wei.
    // The rate is the conversion between wei and the smallest and indivisible token unit.
    // So, if you are using a rate of 1 with a ERC20Detailed token with 3 decimals called TOK
    // 1 wei will give you 1 unit, or 0.001 TOK.
    uint256 private _rate;

    // Amount of wei raised
    uint256 private _weiRaised;

    /**
     * Event for token purchase logging
     * @param purchaser who paid for the tokens
     * @param beneficiary who got the tokens
     * @param value weis paid for purchase
     * @param amount amount of tokens purchased
     */
    event TokensPurchased(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    /**
     * @param incRate Number of token units a buyer gets per wei
     * @dev The rate is the conversion between wei and the smallest and indivisible
     * token unit. So, if you are using a rate of 1 with a ERC20Detailed token
     * with 3 decimals called TOK, 1 wei will give you 1 unit, or 0.001 TOK.
     * @param incWallet Address where collected funds will be forwarded to
     * @param incToken Address of the token being sold
     * UPDATED FOR 0.8.13 (updated param names)
     */
    constructor(
        uint256 incRate,
        address payable incWallet,
        IERC20 incToken
    ) {
        require(incRate > 0, "Rate is 0");
        require(incWallet != address(0), "Wallet is the zero address");
        require(address(incToken) != address(0), "Token is the zero address");

        _rate = incRate;
        _wallet = incWallet;
        _token = incToken;
    }

    /**
     * @dev fallback function ***DO NOT OVERRIDE***
     * Note that other contracts will transfer funds with a base gas stipend
     * of 2300, which is not enough to call buyTokens. Consider calling
     * buyTokens directly when purchasing tokens from a contract.
     * UPDATED FOR 0.8.13 (updated fallback function syntax)
     */
    fallback() external payable {
        buyTokens(_msgSender());
    }

    /**
     * @dev receive function ***DO NOT OVERRIDE***
     * ADDED FOR 0.8.13
     */
    receive() external payable {
        buyTokens(_msgSender());
    }

    /**
     * @return the token being sold.
     */
    function token() public view returns (IERC20) {
        return _token;
    }

    /**
     * @return the address where funds are collected.
     */
    function wallet() public view returns (address payable) {
        return _wallet;
    }

    /**
     * @return the number of token units a buyer gets per wei.
     */
    function rate() public view returns (uint256) {
        return _rate;
    }

    /**
     * @return the amount of wei raised.
     */
    function weiRaised() public view returns (uint256) {
        return _weiRaised;
    }

    /**
     * @dev low level token purchase ***DO NOT OVERRIDE***
     * This function has a non-reentrancy guard, so it shouldn't be called by
     * another `nonReentrant` function.
     * @param beneficiary Recipient of the token purchase
     */
    function buyTokens(address beneficiary) public payable nonReentrant {
        uint256 weiAmount = msg.value;

        _preValidatePurchase(beneficiary, weiAmount);

        // calculate token amount to be created
        uint256 tokens = _getTokenAmount(weiAmount);

        // update state
        _weiRaised = _weiRaised.add(weiAmount);

        _processPurchase(beneficiary, tokens);

        emit TokensPurchased(_msgSender(), beneficiary, weiAmount, tokens);

        _updatePurchasingState(beneficiary, weiAmount);

        _forwardFunds();
        _postValidatePurchase(beneficiary, weiAmount);
    }

    /**
     * @dev Validation of an incoming purchase. Use require statements to revert state when conditions are not met.
     * Use `super` in contracts that inherit from Crowdsale to extend their validations.
     * Example from CappedCrowdsale.sol's _preValidatePurchase method:
     *     super._preValidatePurchase(beneficiary, weiAmount);
     *     require(weiRaised().add(weiAmount) <= cap);
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     * ADDED VIRTUAL KEYWORD
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view virtual {
        require(beneficiary != address(0), "Beneficiary is the zero address");
        require(weiAmount != 0, "weiAmount is 0");
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
    }

    /**
     * @dev Validation of an executed purchase. Observe state and use revert statements to undo rollback when valid
     * conditions are not met.
     * @param beneficiary Address performing the token purchase
     * @param weiAmount Value in wei involved in the purchase
     */
    function _postValidatePurchase(address beneficiary, uint256 weiAmount) internal view {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Source of tokens. Override this method to modify the way in which the crowdsale ultimately gets and sends
     * its tokens.
     * @param beneficiary Address performing the token purchase
     * @param tokenAmount Number of tokens to be emitted
     */
    function _deliverTokens(address beneficiary, uint256 tokenAmount) internal {
        _token.safeTransfer(beneficiary, tokenAmount);
    }

    /**
     * @dev Executed when a purchase has been validated and is ready to be executed. Doesn't necessarily emit/send
     * tokens.
     * @param beneficiary Address receiving the tokens
     * @param tokenAmount Number of tokens to be purchased
     */
    function _processPurchase(address beneficiary, uint256 tokenAmount) internal {
        _deliverTokens(beneficiary, tokenAmount);
    }

    /**
     * @dev Override for extensions that require an internal state to check for validity (current user contributions,
     * etc.)
     * @param beneficiary Address receiving the tokens
     * @param weiAmount Value in wei involved in the purchase
     * ADDED VIRTUAL KEYWORD
     */
    function _updatePurchasingState(address beneficiary, uint256 weiAmount) internal virtual {
        // solhint-disable-previous-line no-empty-blocks
    }

    /**
     * @dev Override to extend the way in which ether is converted to tokens.
     * @param weiAmount Value in wei to be converted into tokens
     * @return Number of tokens that can be purchased with the specified _weiAmount
     * ADDED VIRTUAL KEYWORD
     */
    function _getTokenAmount(uint256 weiAmount) internal view virtual returns (uint256) {
        return weiAmount.mul(_rate);
    }

    /**
     * @dev Determines how ETH is stored/forwarded on purchases.
     */
    function _forwardFunds() internal {
        _wallet.transfer(msg.value);
    }
}

/**
 * @title Token presale contract for $PBIRB
 * @author Parrotly Finance, Inc.
 */
contract PbirbTokenPresale is Crowdsale, Ownable {
    mapping(address => bool) private _whitelistedAddresses;
    mapping(address => uint256) private _whitelistAddressSpend;
    mapping(address => uint256) private _pbirbPurchased;
    bool private _saleParametersLocked = false;
    bool private _whitelistSaleActive = false;
    bool private _publicSaleActive = false;
    bool private _whitelistSaleStarted = false;
    bool private _whitelistSaleEnded = false;
    uint256 private _whitelistSalePbirbSold;
    uint256 private _publicSalePbirbSold;
    uint256 private _whitelistSalePbirbCap = 187500000000 ether; // max pbirb available (WL)
    uint256 private _whitelistSaleRate = 5000000; // pbirb per wei (WL)
    uint256 private _publicSalePbirbCap = 287500000000 ether; // max pbirb available (public)
    uint256 private _publicSaleRate = 4545455; // pbirb per wei (public)
    uint256 private _maxPbirbPerAddress = 1250000000 ether; // max pbirb spend per adddress

    /**
     * @param rate Not used due to custom rate tracking
     * @param wallet Address where collected funds will be forwarded to
     * @param token Address of the token being sold
     */
    constructor(
        uint256 rate,
        address payable wallet,
        IERC20 token
    ) Crowdsale(rate, wallet, token) {}

    /**
     * @dev Throws if sale parameters are locked
     */
    modifier onlyWhenUnlocked() {
        require(_saleParametersLocked == false, "Sale parameters are locked");
        _;
    }

    /**
     * @inheritdoc Crowdsale
     */
    function _preValidatePurchase(address beneficiary, uint256 weiAmount) internal view override {
        super._preValidatePurchase(beneficiary, weiAmount);
        require(_saleParametersLocked, "Sale parameters are not locked");
        require(_whitelistSaleActive || _publicSaleActive, "Whitelist sale and public sale are both not active");

        if (_whitelistSaleActive) {
            _validateWhitelistSale(beneficiary, weiAmount);
        } else {
            _validatePublicSale(beneficiary, weiAmount);
        }
    }

    /**
     * @dev Validation specific to the whitelist portion of the sale
     * @param beneficiary address receiving the tokens
     * @param weiAmount Value in wei involved in the purchase
     */
    function _validateWhitelistSale(address beneficiary, uint256 weiAmount) internal view {
        require(checkAddressWhitelisted(beneficiary), "Beneficiary address is not whitelisted");

        uint256 tokens = _getTokenAmount(weiAmount);

        require(tokens <= _maxPbirbPerAddress, "Exceeds maximum buy amount");
        require(tokens <= _whitelistSalePbirbCap, "Exceeds whitelist cap");
        require(_pbirbPurchased[beneficiary] + tokens <= _maxPbirbPerAddress, "Beneficiary address total exceeds maximum buy amount");
    }

    /**
     * @dev Validation specific to the public portion of the sale
     * @param beneficiary address receiving the tokens
     * @param weiAmount Value in wei involved in the purchase
     */
    function _validatePublicSale(address beneficiary, uint256 weiAmount) internal view {
        uint256 tokens = _getTokenAmount(weiAmount);

        require(tokens <= _maxPbirbPerAddress, "Exceeds maximum buy amount");
        require(tokens <= _publicSalePbirbCap, "Exceeds public cap");
        require(_pbirbPurchased[beneficiary] + tokens <= _maxPbirbPerAddress, "Beneficiary address total exceeds maximum buy amount");
    }

    /**
     * @inheritdoc Crowdsale
     */
    function _getTokenAmount(uint256 weiAmount) internal view override returns (uint256) {
        if (_publicSaleActive) {
            return weiAmount * _publicSaleRate;
        }

        return weiAmount * _whitelistSaleRate;
    }

    /**
     * @inheritdoc Crowdsale
     */
    function _updatePurchasingState(address beneficiary, uint256 weiAmount) internal override {
        uint256 tokens = _getTokenAmount(weiAmount);
        if (_whitelistSaleActive) {
            _pbirbPurchased[beneficiary] += tokens;
            _whitelistSalePbirbSold += tokens;
        } else {
            _pbirbPurchased[beneficiary] += tokens;
            _publicSalePbirbSold += tokens;
        }
    }

    /**
     * @dev onlyOwner
     * Send remaining pbirb back to the owner
     */
    function endSale() public onlyOwner {
        require(_publicSaleActive, "Public sale has not started");
        _publicSaleActive = false;
        uint256 balance = token().balanceOf(address(this));
        token().transfer(owner(), balance);
    }

    /**
     * Getters & Setters
     */
    function getWhitelistSalePbirbSold() public view returns (uint256) {
        return _whitelistSalePbirbSold;
    }

    function getPublicSalePbirbSold() public view returns (uint256) {
        return _publicSalePbirbSold;
    }

    function getWhitelistSalePbirbCap() public view returns (uint256) {
        return _whitelistSalePbirbCap;
    }

    /**
     * @dev onlyOwner and onlyWhenUnlocked
     */
    function setWhitelistSalePbirbCap(uint256 cap) public onlyOwner onlyWhenUnlocked {
        _whitelistSalePbirbCap = cap;
    }

    function getPublicSalePbirbCap() public view returns (uint256) {
        return _publicSalePbirbCap;
    }

    /**
     * @dev onlyOwner and onlyWhenUnlocked
     */
    function setPublicSalePbirbCap(uint256 cap) public onlyOwner onlyWhenUnlocked {
        _publicSalePbirbCap = cap;
    }

    function getWhitelistSaleRate() public view returns (uint256) {
        return _whitelistSaleRate;
    }

    /**
     * @dev onlyOwner and onlyWhenUnlocked
     */
    function setWhitelistSaleRate(uint256 rate) public onlyOwner onlyWhenUnlocked {
        _whitelistSaleRate = rate;
    }

    function getPublicSaleRate() public view returns (uint256) {
        return _publicSaleRate;
    }

    /**
     * @dev onlyOwner and onlyWhenUnlocked
     */
    function setPublicSaleRate(uint256 rate) public onlyOwner onlyWhenUnlocked {
        _publicSaleRate = rate;
    }

    function getMaxPbirbPerAddress() public view returns (uint256) {
        return _maxPbirbPerAddress;
    }

    /**
     * @dev onlyOwner and onlyWhenUnlocked
     */
    function setMaxPbirbPerAddress(uint256 amount) public onlyOwner onlyWhenUnlocked {
        _maxPbirbPerAddress = amount;
    }

    function getSaleParametersLocked() public view returns (bool) {
        return _saleParametersLocked;
    }

    /**
     * @dev onlyOwner
     * Parameters cannot be unlocked
     */
    function lockSaleParameters() public onlyOwner {
        _saleParametersLocked = true;
    }

    function getWhitelistSaleActive() public view returns (bool) {
        return _whitelistSaleActive;
    }

    /**
     * @dev onlyOwner
     */
    function setWhitelistSaleActive(bool active) public onlyOwner {
        require(_saleParametersLocked, "Sale parameters are not locked");
        require(!_whitelistSaleEnded, "Whitelist sale has ended");

        _whitelistSaleActive = active;
        if (_whitelistSaleActive && !_whitelistSaleStarted) {
            _whitelistSaleStarted = true;
        }
    }

    function getPublicSaleActive() public view returns (bool) {
        return _publicSaleActive;
    }

    /**
     * @dev onlyOwner
     */
    function setPublicSaleActive(bool active) public onlyOwner {
        require(_saleParametersLocked, "Sale parameters are not locked");
        require(_whitelistSaleStarted, "Whitelist sale has not started");

        _publicSaleActive = active;
        if (_publicSaleActive && !_whitelistSaleEnded) {
            endWhitelistSale();
            transferWhitelistSaleTokensToPublicSaleCap();
            adjustMaxPbirbPerAddress();
        }
    }

    /**
     * @dev Set whitelist sale state according to the end of the whitelist sale
     */
    function endWhitelistSale() private {
        _whitelistSaleActive = false;
        _whitelistSaleEnded = true;
    }

    /**
     * @dev Any unsold whitelist sale tokens will be made available in the public sale
     */
    function transferWhitelistSaleTokensToPublicSaleCap() private {
        _publicSalePbirbCap += (_whitelistSalePbirbCap - _whitelistSalePbirbSold);
    }

    /**
     * @dev Adjust the max pbirb per address to play nice with the rounded rate
     */
    function adjustMaxPbirbPerAddress() private {
        _maxPbirbPerAddress = 1250000125 ether;
    }

    /**
     * @dev onlyOwner
     */
    function addAddressToWhitelist(address user) public onlyOwner {
        _whitelistedAddresses[user] = true;
    }

    /**
     * @dev onlyOwner
     */
    function addAddressesToWhitelist(address[] calldata users) public onlyOwner {
        for (uint256 i; i < users.length; i++) {
            _whitelistedAddresses[users[i]] = true;
        }
    }

    /**
     * @dev onlyOwner
     */
    function removeAddressFromWhitelist(address user) public onlyOwner {
        _whitelistedAddresses[user] = false;
    }

    /**
     * @dev onlyOwner
     */
    function isAddressWhitelisted(address user) public view onlyOwner returns (bool) {
        return checkAddressWhitelisted(user);
    }

    function singleAddressCheckWhitelist() public view returns (bool) {
        return _whitelistedAddresses[_msgSender()];
    }

    function singleAddressCheckPbirbAmountPurchased() public view returns (uint256) {
        return _pbirbPurchased[_msgSender()];
    }

    function singleAddressCheckPbirbAmountAvailable() public view returns (uint256) {
        return _maxPbirbPerAddress - _pbirbPurchased[_msgSender()];
    }

    function checkAddressWhitelisted(address user) private view returns (bool) {
        return _whitelistedAddresses[user];
    }
}