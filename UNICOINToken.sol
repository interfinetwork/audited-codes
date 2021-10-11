// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/// @title A base MisBlock token contract
/// @author Anderson L
/// @notice This contract is inherited by MisBlockETH and MisBlockBSC token contracts.
/// @dev All functions requiring onlyOwner are also pausable.

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import '@openzeppelin/contracts/access/Ownable.sol';
import "@openzeppelin/contracts/utils/Address.sol";
import '@openzeppelin/contracts/security/Pausable.sol';
import "./interfaces/UniswapInterfaces.sol";

contract MisBlockBase is ERC20, Pausable, Ownable {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) private _rOwned;
    mapping (address => uint256) private _tOwned;
    mapping (address => mapping (address => uint256)) private _tokenAllowances;

    mapping (address => bool) private _isExcludedFromFee;

    mapping (address => bool) private _isExcluded;
    address[] private _excluded;
   
    uint256 private constant MAX = ~uint256(0) / 1000;
    uint256 private _tTotal = 0;
    uint256 private _rTotal = 0;
    uint256 private _tFeeTotal;

    uint256 public deployTime = block.timestamp;
    
    uint256 public taxFee;
    uint256 public liquidityFee;
    
    IUniswapV2Router02 public immutable uniswapV2Router;
    address public immutable uniswapV2Pair;
    
    bool inSwapAndLiquify;
    bool public swapAndLiquifyEnabled = true;
    
    // Should re-set following 2 values as our token's requirement.
    uint256 public maxTxAmount = 5000000 ether;
    uint256 private constant TOKEN_SELL_TO_LIQUIDITY = 500000 ether;
    
    event MinTokensBeforeSwapUpdated(uint256 minTokensBeforeSwap);
    event SwapAndLiquifyEnabledUpdated(bool enabled);
    event SwapAndLiquify(
        uint256 tokensSwapped,
        uint256 ethReceived,
        uint256 tokensIntoLiqudity
    );
    event TransferForVesting(address recipient, uint256 amount);
    event Mint(address account, uint256 amount);
    event AllocateVesting(address indexed vestingContract, uint256 amount, uint256 timestamp);

    modifier lockTheSwap {
        inSwapAndLiquify = true;
        _;
        inSwapAndLiquify = false;
    }

    struct LockFund {
        uint256 amount;
        uint256 releasetime;
    }
    
    mapping (address => bool) public isSwapAddress;
    address[] public swapAddresses;
    mapping (address => LockFund[]) private _lockFundsArray;
    
    /// @notice Constructor. The token name is UNICOIN and the symbol name is UNICN.
    /// @dev Should input swapaddress as PCS router address in BSC contract and UNISWAP router addres in ETH contract.
    /// @param swapaddress An address of pcs or uniswap router contract.
    /// @param initialMintAmount An address of pcs or uniswap router contract.
    constructor(address swapaddress, uint256 initialMintAmount) ERC20("UNICOIN", "UNICN") {
        _tTotal = initialMintAmount;
        _rTotal = MAX.sub(MAX.mod(_tTotal));
        _rOwned[_msgSender()] = _rTotal;

        // Uniswap Address should be in SwapAddress list
        isSwapAddress[swapaddress] = true;
        swapAddresses.push(swapaddress);

        //exclude owner and this contract from fee
        _isExcludedFromFee[owner()] = true;
        _isExcludedFromFee[address(this)] = true;

        IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(swapaddress);

        // set the rest of the contract variables
        uniswapV2Router = _uniswapV2Router;

         // Create a uniswap pair for this new token
        uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory())
            .createPair(address(this), _uniswapV2Router.WETH());

        emit Transfer(address(0), _msgSender(), _tTotal);
        
    }

    /// @notice We are despositing 1T tokens initially and allowing to mint 9T tokens more. This function can be called by only owner.
    function mint(address account, uint256 amount) external onlyOwner whenNotPaused {
        _mint(account, amount);
        emit Mint(account, amount);
    }
    
    /// @dev We should check reflection value should not be overr uint256's max value.
    function _mint(address account, uint256 amount) internal override virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        (uint256 rAmount,,,,,) = _getValues(amount);
        require((~uint256(0) - rAmount) > _rTotal , "Mint value is exceeded limitation");

        _rOwned[account] = _rOwned[account].add(rAmount);
        if(_isExcluded[account]) {
            _tOwned[account] = _tOwned[account].add(amount);
        }
        _rTotal += rAmount;
        _tTotal += amount;
    }

    /// @notice Getting totalSupply.
    function totalSupply() public view override returns (uint256) {
        return _tTotal;
    }

    /**
     * @notice Getting balance of the account.      
     * @dev Checking the account is including in Reward List or not.     
     */
    function balanceOf(address account) public view override returns (uint256) {
        if (_isExcluded[account]) return _tOwned[account];
        return tokenFromReflection(_rOwned[account]);
    }

    /**
     * @dev Checking whether the account is contract address or not.     
     */
    // function isContract(address account) internal view returns (bool) { 
    //     uint32 size;
    //     assembly {
    //         size := extcodesize(account)
    //     }
    //     return (size > 0);
    // }

    /**
    * @notice This function is standard transfer function.
    * @dev Moves `amount` tokens from the caller's account to `recipient`.
    *
    * Taking fees and set timelock by proper logic.
    * Returns a boolean value indicating whether the operation succeeded.
    *
    * Emits a {Transfer} event.
    */
    function transfer(address recipient, uint256 amount) public override returns (bool) {
        _transferBase(_msgSender(), recipient, amount);        
        return true;
    }

    /**
    * @notice This function is to getting allowance of spender.
    * @dev Returns the remaining number of tokens that `spender` will be
    * allowed to spend on behalf of `sender` through {transferFrom}. This is
    * zero by default.
    *
    * This value changes when {approve} or {transferFrom} are called.
    */
    function allowance(address sender, address spender) public view override returns (uint256) {
        return _tokenAllowances[sender][spender];
    }

    /**
     * @notice This function is to approve transfer.
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) public override returns (bool) {
        _approveBase(_msgSender(), spender, amount);
        return true;
    }

    /**
    * @notice This function is for delegating transfer.
    * @dev Moves `amount` tokens from `sender` to `recipient` using the
    * allowance mechanism. `amount` is then deducted from the caller's
    * allowance.
    *
    * Returns a boolean value indicating whether the operation succeeded.
    *
    * Emits a {Transfer} event.
    */
    function transferFrom(address sender, address recipient, uint256 amount) public override returns (bool) {
        require(sender != recipient, "sender and recipient is same address");
        _transferBase(sender, recipient, amount);
        _approveBase(sender, _msgSender(), _tokenAllowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    /**
     * @notice This function is to increase allowance.
     * @dev Adds `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {Approval} event.
     */
    function increaseAllowance(address spender, uint256 addedValue) public override virtual returns (bool) {
        _approveBase(_msgSender(), spender, _tokenAllowances[_msgSender()][spender].add(addedValue));
        return true;
    }

    /**
     * @notice This function is to decrease allowance.
     * @dev Subs `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits an {Approval} event.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public override virtual returns (bool) {
        _approveBase(_msgSender(), spender, _tokenAllowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }
    /**
     * @notice This function is to check whether the account is excluded from reward or not.
     * @dev Check the account is excluded from reward or not.
     *
     * Returns a boolean value indicating whether the account is excluded from reward or not.
     *
     */
    function isExcludedFromReward(address account) external view returns (bool) {
        return _isExcluded[account];
    }

    /**
     * @notice Get total Fees taken by taxes.     
     */
    function totalFees() external view returns (uint256) {
        return _tFeeTotal;
    }

    /**
    * @notice This function is to deliver tokens to account holders.
    */
    function deliver(uint256 tAmount) external {
        address sender = _msgSender();
        require(!_isExcluded[sender], "Excluded addresses cannot call this function");
        (uint256 rAmount,,,,,) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rTotal = _rTotal.sub(rAmount);
        _tFeeTotal = _tFeeTotal.add(tAmount);
    }

    /**    
     * @notice Getting reflection value from token value.     
     */
    function reflectionFromToken(uint256 tAmount, bool deductTransferFee) external view returns(uint256) {
        require(tAmount <= _tTotal, "Amount must be less than supply");
        if (!deductTransferFee) {
            (uint256 rAmount,,,,,) = _getValues(tAmount);
            return rAmount;
        } else {
            (,uint256 rTransferAmount,,,,) = _getValues(tAmount);
            return rTransferAmount;
        }
    }

    /**    
     * @notice Getting token value from reflection value.     
     */
    function tokenFromReflection(uint256 rAmount) public view returns(uint256) {
        require(rAmount <= _rTotal, "Amount must be less than total reflections");
        uint256 currentRate =  _getRate();
        return rAmount.div(currentRate);
    }

    /**
     * @notice exclude the account from the reward list.
     *
     * Must be called from only owner.
     *
     */
    function excludeFromReward(address account) external onlyOwner whenNotPaused {
        // require(account != 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, 'We can not exclude Uniswap router.');
        require(!_isExcluded[account], "Account is already excluded");
        if(_rOwned[account] > 0) {
            _tOwned[account] = tokenFromReflection(_rOwned[account]);
        }
        _isExcluded[account] = true;
        _excluded.push(account);
    }

    /**
     * @notice include the account into the reward list.
     *
     * Must be called from only owner.
     *
     */
    function includeInReward(address account) external onlyOwner whenNotPaused {
        require(_isExcluded[account], "Account is already excluded");
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_excluded[i] == account) {
                _excluded[i] = _excluded[_excluded.length - 1];
                _tOwned[account] = 0;
                _isExcluded[account] = false;
                _excluded.pop();
                break;
            }
        }
    }

    /**
     * @notice exclude the account from the taking fee. taxes are not applied for accounts from this list.
     *
     * Must be called from only owner.
     *
     */
    function excludeFromFee(address account) external onlyOwner whenNotPaused {
        _isExcludedFromFee[account] = true;
    }
    
    /**
     * @notice include the account into the taking fee. taxes would be applied for accounts from this list.
     *
     * Must be called from only owner.
     *
     */
    function includeInFee(address account) external onlyOwner {
        _isExcludedFromFee[account] = false;
    }
    
    /**
     * @notice setting maximum transfer amount as percentage.
     *
     * Must be called from only owner.
     *
     */
    function setMaxTxPercent(uint256 maxTxPercent) external onlyOwner whenNotPaused {
        maxTxAmount = _tTotal.mul(maxTxPercent).div(
            10**2
        );
    }

    /**
     * @notice enable/disable Swap and Liquidity feature.
     *
     * Must be called from only owner.
     *
     */
    function setSwapAndLiquifyEnabled(bool enabled) external onlyOwner whenNotPaused {
        swapAndLiquifyEnabled = enabled;
        emit SwapAndLiquifyEnabledUpdated(enabled);
    }
    
    /**
     * @notice burn tokens from the account.
     *
     * Must be called from only owner.
     *
     */
    function burn(address account, uint256 tAmount) external onlyOwner whenNotPaused {
        uint256 burnerBalance = balanceOf(account);
        require(burnerBalance >= tAmount, "Burnning amount is exceed balance");
        (uint256 rAmount, , , , , ) = _getValues(tAmount);
        
        _rOwned[account] = _rOwned[account].sub(rAmount);
        if(_isExcluded[account]) {
            _tOwned[account] = _tOwned[account].sub(tAmount);
        }
        _rTotal = _rTotal.sub(rAmount);
        _tTotal = _tTotal.sub(tAmount);
    }

    /**
     * @dev Inspired from Reflect Finance concept.
     * to recieve ETH from uniswapV2Router when swaping
     */     
    receive() external payable {}

    /**
     * @dev applying fees. called by transfer functions.
     *
     * Internal function.
     *
     */
    function _reflectFee(uint256 rFee, uint256 tFee) private {
        _rTotal = _rTotal.sub(rFee);
        _tFeeTotal = _tFeeTotal.add(tFee);
    }

    /**
     * @dev Internal function to get values related with reflection feature based on transfer amount.
     * - rAmount : reflection amount for tAmount
     * - rTransferAmount : reflection amount for tTransferAmount
     * - rFee : reflection amount for tFee
     * - tTransferAmount : transfer amount without all taxes(fee and liquidity)
     * - tFee : tax fee for account holders
     * - tLiquidity : tax fee for liquidity
     */
    function _getValues(uint256 tAmount) private view returns (uint256, uint256, uint256, uint256, uint256, uint256) {
        (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(tAmount);
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(tAmount, tFee, tLiquidity, _getRate());
        return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
    }

    /**
     * @dev Internal function to get token values based on transfer amount. called by {_getValues}
     * - tTransferAmount : transfer amount without all taxes(fee and liquidity)
     * - tFee : tax fee for account holders
     * - tLiquidity : tax fee for liquidity
     */
    function _getTValues(uint256 tAmount) private view returns (uint256, uint256, uint256) {
        uint256 tFee = calculateTaxFee(tAmount);
        uint256 tLiquidity = calculateLiquidityFee(tAmount);
        uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
        return (tTransferAmount, tFee, tLiquidity);
    }

    /**
     * @dev Internal function to get reflection values based on token values. called by {_getValues}
     * - rAmount : reflection amount for tAmount
     * - rTransferAmount : reflection amount for tTransferAmount
     * - rFee : reflection amount for tFee
     */
    function _getRValues(uint256 tAmount, uint256 tFee, uint256 tLiquidity, uint256 currentRate) private pure returns (uint256, uint256, uint256) {
        uint256 rAmount = tAmount.mul(currentRate);
        uint256 rFee = tFee.mul(currentRate);
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
        return (rAmount, rTransferAmount, rFee);
    }

    /**
     * @dev Internal function to get rate between token and reflection value
     */
    function _getRate() private view returns(uint256) {
        (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
        return rSupply.div(tSupply);
    }

    /**
     * @dev Internal function to get total Supply of token and reflection. called by {_getRate}
     */
    function _getCurrentSupply() private view returns(uint256, uint256) {
        uint256 rSupply = _rTotal;
        uint256 tSupply = _tTotal;      
        for (uint256 i = 0; i < _excluded.length; i++) {
            if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply) return (_rTotal, _tTotal);
            rSupply = rSupply.sub(_rOwned[_excluded[i]]);
            tSupply = tSupply.sub(_tOwned[_excluded[i]]);
        }
        if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
        return (rSupply, tSupply);
    }
    
    /**
    * @dev Internal function to to apply liquidity fee.
    */
    function _takeLiquidity(uint256 tLiquidity) private {
        uint256 currentRate =  _getRate();
        uint256 rLiquidity = tLiquidity.mul(currentRate);
        _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
        if(_isExcluded[address(this)])
            _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
    }
    
    /**
    * @dev Internal function to calculate tax fee. Used 1000 instead of 100 for max percent to avoid decimals. For example, 7.5% will be calculated by 75/1000
    */
    function calculateTaxFee(uint256 amount) private view returns (uint256) {
        return amount.mul(taxFee).div(
            10**3
        );
    }

    /**
    * @dev Internal function to calculate liquidity fee. Used 1000 instead of 100 for max percent to avoid decimals. For example, 7.5% will be calculated by 75/1000
    */
    function calculateLiquidityFee(uint256 amount) private view returns (uint256) {
        return amount.mul(liquidityFee).div(
            10**3
        );
    }
    
    /**
    * @dev Internal function to set tax fees.
    * First Month : 7.5%, Second Month : 5%, Third Month : 2.5%, From Fourth Month : 0
    */
    function _setTaxFee(bool takeFee) private {
        if (!takeFee) {
            taxFee = 0;
            liquidityFee = 0;
        } else if ( block.timestamp < deployTime + 30 days) {
            taxFee = 75;
            liquidityFee = 75;
        } else if ( block.timestamp < deployTime + 60 days) {
            taxFee = 50;
            liquidityFee = 50;
        } else if ( block.timestamp < deployTime + 90 days) {
            taxFee = 25;
            liquidityFee = 25;
        } else {
            taxFee = 0;
            liquidityFee = 0;
        }

    }
    
    /**
    * @notice Checking whether the address is excluded from fee or not
    */
    function isExcludedFromFee(address account) external view returns(bool) {
        return _isExcludedFromFee[account];
    }

    /**
    * @dev Internal function to approve.
    * Emits a {Approval} event.
    */
    function _approveBase(address sender, address spender, uint256 amount) private {
        require(sender != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _tokenAllowances[sender][spender] = amount;
        emit Approval(sender, spender, amount);
    }

    /**
    * @dev Internal function for standard transfer.
    */
    function _transferBase(
        address from,
        address to,
        uint256 amount
    ) private {
        
        require(from != address(0), "ERC20: transfer from the zero address");
        require(to != address(0), "ERC20: transfer to the zero address");
        require(amount > 0, "Transfer amount must be greater than zero");
        if(from != owner() && to != owner())
            require(amount <= maxTxAmount, "Transfer amount exceeds the maxTxAmount.");

        uint256 senderBalance = balanceOf(from);
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        
        //indicates if fee should be deducted from transfer
        bool takeFee = true;
        
        //if from address is not in SwapAddress list, not taking fee
        if(!isSwapAddress[from]){
            takeFee = false;
        }
        
        //if any account belongs to _isExcludedFromFee account then remove the fee
        if(_isExcludedFromFee[from] || _isExcludedFromFee[to]){
            takeFee = false;
        }

        //it will check timelock
        _beforeTokenTransferBase(from, amount);
        
        //transfer amount, it will take tax, burn, liquidity fee
        _tokenTransfer(from,to,amount,takeFee);

        //it will calculate timelock
        _afterTokenTransferBase(from, to, amount);

        // is the token balance of this contract address over the min number of
        // tokens that we need to initiate a swap + liquidity lock?
        // also, don't get caught in a circular liquidity event.
        // also, don't swap & liquify if sender is uniswap pair.
        uint256 contractTokenBalance = balanceOf(address(this));
        
        if(contractTokenBalance >= maxTxAmount)
        {
            contractTokenBalance = maxTxAmount;
        }
        
        bool overMinTokenBalance = contractTokenBalance >= TOKEN_SELL_TO_LIQUIDITY;
        if (
            overMinTokenBalance &&
            !inSwapAndLiquify &&
            from != uniswapV2Pair &&
            swapAndLiquifyEnabled
        ) {
            contractTokenBalance = TOKEN_SELL_TO_LIQUIDITY;
            //add liquidity
            swapAndLiquify(contractTokenBalance);
        }
    }

    /**
    * @dev Internal function of swap feature.
    * Emits {SwapAndLiquify}
    */
    function swapAndLiquify(uint256 contractTokenBalance) private lockTheSwap {
        // split the contract balance into halves
        uint256 half = contractTokenBalance.div(2);
        uint256 otherHalf = contractTokenBalance.sub(half);

        // capture the contract's current ETH balance.
        // this is so that we can capture exactly the amount of ETH that the
        // swap creates, and not make the liquidity event include any ETH that
        // has been manually sent to the contract
        uint256 initialBalance = address(this).balance;

        // swap tokens for ETH
        swapTokensForEth(half); // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

        // how much ETH did we just swap into?
        uint256 newBalance = address(this).balance.sub(initialBalance);

        // add liquidity to uniswap
        addLiquidity(otherHalf, newBalance);
        
    }

    /**
    * @dev Internal function for swapTokensForEth.
    */
    function swapTokensForEth(uint256 tokenAmount) private {
        // generate the uniswap pair path of token -> weth
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = uniswapV2Router.WETH();

        _approveBase(address(this), address(uniswapV2Router), tokenAmount);

        // make the swap
        uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            tokenAmount,
            0, // accept any amount of ETH
            path,
            address(this),
            block.timestamp
        );
    }

    /**
    * @dev Internal function for addLiquidity.
    */
    function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
        // approve token transfer to cover all possible scenarios
        _approveBase(address(this), address(uniswapV2Router), tokenAmount);

        // add the liquidity
        (uint token, uint eth, uint liquidity) = uniswapV2Router.addLiquidityETH{value: ethAmount}(
            address(this),
            tokenAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            owner(),
            block.timestamp
        );

        emit SwapAndLiquify(token, eth, liquidity);
    }

    /**
    * @dev Internal function of transfer.
    * this method is responsible for taking all fee, if takeFee is true
    */    
    function _tokenTransfer(address sender, address recipient, uint256 amount,bool takeFee) private {
        _setTaxFee(takeFee);
        
        if (_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferFromExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
            _transferToExcluded(sender, recipient, amount);
        } else if (!_isExcluded[sender] && !_isExcluded[recipient]) {
            _transferStandard(sender, recipient, amount);
        } else if (_isExcluded[sender] && _isExcluded[recipient]) {
            _transferBothExcluded(sender, recipient, amount);
        } else {
            _transferStandard(sender, recipient, amount);
        }
    }

    /**
    * @dev called in case of both of sender and recipient are in reward list.
    */   
    function _transferStandard(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
    * @dev called in case of only sender is in reward list.
    */   
    function _transferToExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);           
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
    * @dev called in case of only recipient is in reward list.
    */   
    function _transferFromExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);   
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
    * @dev called in case of both are not in reward list.
    */   
    function _transferBothExcluded(address sender, address recipient, uint256 tAmount) private {
        (uint256 rAmount, uint256 rTransferAmount, uint256 rFee, uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getValues(tAmount);
        _tOwned[sender] = _tOwned[sender].sub(tAmount);
        _rOwned[sender] = _rOwned[sender].sub(rAmount);
        _tOwned[recipient] = _tOwned[recipient].add(tTransferAmount);
        _rOwned[recipient] = _rOwned[recipient].add(rTransferAmount);        
        _takeLiquidity(tLiquidity);
        _reflectFee(rFee, tFee);
        emit Transfer(sender, recipient, tTransferAmount);
    }

    /**
    * @notice getting the list of addresses set as applying timelock from. All tokens transfered from addresses of this list is time locked by proper logic.
    */ 
    function getSwapAddresses() external view returns (address[] memory){
        return swapAddresses;
    }

    /**
    * @notice add swap address
    */ 
    function addSwapAddress(address account) external onlyOwner whenNotPaused {
        require(!isSwapAddress[account], "Account is already in list of swap addresses");
        isSwapAddress[account] = true;        
        swapAddresses.push(account);
    }

    /**
    * @notice remove swap address
    */ 
    function removeSwapAddress(address account) external onlyOwner whenNotPaused {
        require(isSwapAddress[account] == true, "Account is not in list of swap addresses");
        for (uint256 i = 0; i < swapAddresses.length; i++) {
            if (swapAddresses[i] == account) {
                swapAddresses[i] = swapAddresses[swapAddresses.length - 1];
                isSwapAddress[account] = false;
                swapAddresses.pop();
                break;
            }
        }
    }

    /**
    * @dev Internal function to be called before token transfer.
    * Check time locked funds.
    * If the address is having 1000 tokens. And 500 tokens were time locked.
    * At this point if the account wants to transfer 600 tokens, then it will be reverted since the user is having only 500 tokens available.
    */ 

    function _beforeTokenTransferBase(
        address from,
        uint256 amount
    ) private {
        LockFund[] storage lockFunds = _lockFundsArray[from];
        if(lockFunds.length < 1) return;
        uint256 lockedFundsSum = 0;
        for (uint i = 0; i < lockFunds.length; i++) {
            if(lockFunds[i].releasetime > block.timestamp)
            {
                lockedFundsSum += lockFunds[i].amount;
            }
        }
        require(balanceOf(from) - lockedFundsSum >= amount, "Some of your balances were locked. And you don't have enough unlocked balance for this transaction.");
    }

    /**
    * @dev Internal function to be called after token transfer.
    * Applying time lock against tokens transferred from addresses in the timelock list
    */ 

    function _afterTokenTransferBase(
        address from,
        address to,
        uint256 amount
    ) private {
        if(!isSwapAddress[from]) return;
        LockFund[] storage lockFunds = _lockFundsArray[to];
        lockFunds.push(LockFund(amount.div(10), block.timestamp + 1 days));
        for (uint256 i = 1; i < 10; i++) {
            lockFunds.push(LockFund(amount.div(10), block.timestamp + 1 days + i * 1 weeks));
        }
    }
}


/// @title A MisBlock token contract to be launced on BSC network
/// @author Anderson L
/// @notice This contract is inherited from MisBlockBase.

import "./MisBlockBase.sol";

contract MisBlockBSC is MisBlockBase {
    constructor(uint256 initialMintAmount) MisBlockBase(0x10ED43C718714eb63d5aA57B78B54704E256024E, initialMintAmount) {
        
    }
}



/// @title A MisBlock token contract to be launced on Ethereum network
/// @author Anderson L
/// @notice This contract is inherited from MisBlockBase.

import "./MisBlockBase.sol";

contract MisBlockETH is MisBlockBase {
    constructor(uint256 initialMintAmount) MisBlockBase(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D, initialMintAmount) {
        
    }
}