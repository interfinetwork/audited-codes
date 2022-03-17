// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.12;

interface ImdtLogic {
    function gnosis() external view returns (address);
}

import "./ImdtLogic.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract mdtERC20 is Ownable, ERC20 {
    ImdtLogic internal mdtLogic;

    constructor() ERC20("mdtProtocol Credit", "mdtC") {
        mdtLogic = ImdtLogic(owner());
    }

    function mint(address _account, uint256 _amount) external onlyOwner {
        super._mint(_account, _amount);
    }

    function burn(address _account, uint256 _amount) external onlyOwner {
        super._burn(_account, _amount);
    }

    function _approve(
        address _owner,
        address _spender,
        uint256 _amount
    ) internal override {
        require(_spender == owner(), "Not mdtLogic");

        super._approve(_owner, _spender, _amount);
    }

    function _beforeTokenTransfer(
        address _from,
        address _to,
        uint256 _amount
    ) internal override {
        bool allowedFrom = _from == address(0) || _from == mdtLogic.gnosis();
        bool allowedTo = _to == address(0) || _to == mdtLogic.gnosis();
        require(allowedFrom || allowedTo, "Burnable/Mintable Only");

        super._beforeTokenTransfer(_from, _to, _amount);
    }
}


import "./mdtERC20.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

contract mdtLogic is Initializable, ReentrancyGuard, Context {
    using SafeERC20 for mdtERC20;
    using SafeERC20 for IERC20;
    using Address for address;
    using Counters for Counters.Counter;

    uint256 internal RATE;
    address internal GNOSIS;
    address internal DOLLAR;
    address internal ROYALTY;
    mdtERC20 internal CREDIT;
    IUniswapV2Router02 internal ROUTER;

    ShareStruct internal SHARE;
    struct ShareStruct {
        uint256 GNOSIS;
        uint256 ROYALTY;
    }

    GovernanceStruct internal GOVERNANCE;
    struct GovernanceStruct {
        uint256 DOLLAR_PEGGED_PER_CREDIT;
        uint256 CREDIT_PER_LOYALTY_POINT;
        uint256 CREDIT_PER_MARKSMAN_DAILY;
        uint256 CREDIT_PER_MARKSMAN_WEEKLY;
        uint256 CREDIT_PER_MARKSMAN_MONTHLY;
        uint256 CREDIT_PER_MARKSMAN_INDEFINITE;
        uint256 CREDIT_PER_SNIPER_WALLETS_COUNT;
    }

    DiscountsStruct internal DISCOUNTS;
    struct DiscountsStruct {
        uint256 SPECIAL_CLI;
        uint256 SPECIAL_UI;
        uint256 DIAMOND_CLI;
        uint256 DIAMOND_UI;
        uint256 GOLD_CLI;
        uint256 GOLD_UI;
        uint256 SILVER_CLI;
        uint256 SILVER_UI;
        uint256 BRONZE_CLI;
        uint256 BRONZE_UI;
    }

    LoyaltyStruct internal LOYALTY;
    struct LoyaltyStruct {
        uint256 BURN;
        uint256 MINT;
        uint256 SPEND;
    }

    mapping(address => bool) internal RELAYER_ROLE;
    mapping(address => bool) internal BLACKLIST_ROLE;

    mapping(address => bool) internal SPECIAL_ROLE;
    mapping(address => bool) internal DIAMOND_ROLE;
    mapping(address => bool) internal GOLD_ROLE;
    mapping(address => bool) internal SILVER_ROLE;
    mapping(address => bool) internal BRONZE_ROLE;

    Counters.Counter internal SNIPE;
    Counters.Counter internal SNIPER;
    mapping(address => bool) internal SNIPER_REGISTERED;
    mapping(address => uint256) internal SNIPER_LOYALTY_POINT;
    mapping(address => uint256) internal SNIPER_MARKSMAN_STATUS;
    mapping(address => Counters.Counter) internal SNIPER_WALLETS_COUNT;

    mapping(uint256 => uint256) internal BLOCKCHAIN_MULTIPLIER;

    event RoleGranted(
        address indexed account,
        address indexed sender,
        string role
    );

    event RoleRevoked(
        address indexed account,
        address indexed sender,
        string role
    );

    event LoyaltyUpdated(
        address indexed account,
        uint256 beforePoint,
        uint256 afterPoint
    );

    event MarksmanUpdated(
        address indexed account,
        uint256 startTime,
        uint256 endTime
    );

    event WalletsUpdated(
        address indexed account,
        uint256 beforeCount,
        uint256 afterCount
    );

    modifier onlyGnosis() {
        require(_msgSender() == GNOSIS, "Not Gnosis");
        _;
    }

    modifier onlyRelayer() {
        require(RELAYER_ROLE[_msgSender()], "Not Relayer");
        _;
    }

    modifier registerSnipe() {
        SNIPE.increment();
        _;
    }

    modifier registerSniper() {
        if (!SNIPER_REGISTERED[_msgSender()]) {
            SNIPER_REGISTERED[_msgSender()] = true;
            SNIPER.increment();
        }
        _;
    }

    constructor() initializer {}

    function initialize(
        uint256 _rate,
        address _gnosis,
        address _dollar,
        address _royalty,
        address _router
    ) external initializer {
        require(
            _gnosis.isContract() &&
                _dollar.isContract() &&
                _royalty.isContract() &&
                _router.isContract(),
            "Invalid Initialization"
        );

        RATE = _rate;
        GNOSIS = _gnosis;
        DOLLAR = _dollar;
        ROYALTY = _royalty;
        CREDIT = new mdtERC20();
        ROUTER = IUniswapV2Router02(_router);
        _setShareDefault();
        _setGovernanceDefault();
        _setDiscountsDefault();
        _setLoyaltyDefault();
    }

    receive() external payable {}

    function recoverEth() external onlyGnosis {
        payable(GNOSIS).transfer(address(this).balance);
    }

    function recoverToken(IERC20 _token) external onlyGnosis {
        _token.safeTransfer(GNOSIS, _token.balanceOf(address(this)));
    }

    function rate() external view returns (uint256) {
        return RATE;
    }

    function setRate(uint256 _rate) external onlyGnosis {
        RATE = _rate;
    }

    function gnosis() external view returns (address) {
        return GNOSIS;
    }

    function dollar() external view returns (address) {
        return DOLLAR;
    }

    function royalty() external view returns (address) {
        return ROYALTY;
    }

    function credit() external view returns (address) {
        return address(CREDIT);
    }

    function router() external view returns (address) {
        return address(ROUTER);
    }

    function share() external view returns (ShareStruct memory) {
        return SHARE;
    }

    function setShare(uint256 _gnosis, uint256 _royalty) external onlyGnosis {
        if (_gnosis == 0 && _royalty == 0) {
            _setShareDefault();
        } else {
            require(_gnosis + _royalty == 100, "Invalid Share");

            SHARE = ShareStruct({GNOSIS: _gnosis, ROYALTY: _royalty});
        }
    }

    function _setShareDefault() internal {
        SHARE = ShareStruct({GNOSIS: 80, ROYALTY: 20});
    }

    function governance() external view returns (GovernanceStruct memory) {
        return GOVERNANCE;
    }

    function setGovernance(
        uint256 _dollar_pegged_per_credit,
        uint256 _credit_per_loyalty_point,
        uint256 _credit_per_marksman_daily,
        uint256 _credit_per_marksman_weekly,
        uint256 _credit_per_marksman_monthly,
        uint256 _credit_per_marksman_indefinite,
        uint256 _credit_per_sniper_wallets_count
    ) external onlyGnosis {
        if (
            _dollar_pegged_per_credit == 0 &&
            _credit_per_loyalty_point == 0 &&
            _credit_per_marksman_daily == 0 &&
            _credit_per_marksman_weekly == 0 &&
            _credit_per_marksman_monthly == 0 &&
            _credit_per_marksman_indefinite == 0 &&
            _credit_per_sniper_wallets_count == 0
        ) {
            _setGovernanceDefault();
        } else {
            require(_dollar_pegged_per_credit != 0, "Math Overflow");

            GOVERNANCE = GovernanceStruct({
                DOLLAR_PEGGED_PER_CREDIT: _dollar_pegged_per_credit,
                CREDIT_PER_LOYALTY_POINT: _credit_per_loyalty_point,
                CREDIT_PER_MARKSMAN_DAILY: _credit_per_marksman_daily,
                CREDIT_PER_MARKSMAN_WEEKLY: _credit_per_marksman_weekly,
                CREDIT_PER_MARKSMAN_MONTHLY: _credit_per_marksman_monthly,
                CREDIT_PER_MARKSMAN_INDEFINITE: _credit_per_marksman_indefinite,
                CREDIT_PER_SNIPER_WALLETS_COUNT: _credit_per_sniper_wallets_count
            });
        }
    }

    function _setGovernanceDefault() internal {
        GOVERNANCE = GovernanceStruct({
            DOLLAR_PEGGED_PER_CREDIT: 100,
            CREDIT_PER_LOYALTY_POINT: 5,
            CREDIT_PER_MARKSMAN_DAILY: 15000,
            CREDIT_PER_MARKSMAN_WEEKLY: 52500,
            CREDIT_PER_MARKSMAN_MONTHLY: 105000,
            CREDIT_PER_MARKSMAN_INDEFINITE: 157500,
            CREDIT_PER_SNIPER_WALLETS_COUNT: 25000
        });
    }

    function discounts() external view returns (DiscountsStruct memory) {
        return DISCOUNTS;
    }

    function setDiscounts(
        uint256 _special_cli,
        uint256 _special_ui,
        uint256 _diamond_cli,
        uint256 _diamond_ui,
        uint256 _gold_cli,
        uint256 _gold_ui,
        uint256 _silver_cli,
        uint256 _silver_ui,
        uint256 _bronze_cli,
        uint256 _bronze_ui
    ) external onlyGnosis {
        if (
            _special_cli == 0 &&
            _special_ui == 0 &&
            _diamond_cli == 0 &&
            _diamond_ui == 0 &&
            _gold_cli == 0 &&
            _gold_ui == 0 &&
            _silver_cli == 0 &&
            _silver_ui == 0 &&
            _bronze_cli == 0 &&
            _bronze_ui == 0
        ) {
            _setDiscountsDefault();
        } else {
            DISCOUNTS = DiscountsStruct({
                SPECIAL_CLI: _special_cli,
                SPECIAL_UI: _special_ui,
                DIAMOND_CLI: _diamond_cli,
                DIAMOND_UI: _diamond_ui,
                GOLD_CLI: _gold_cli,
                GOLD_UI: _gold_ui,
                SILVER_CLI: _silver_cli,
                SILVER_UI: _silver_ui,
                BRONZE_CLI: _bronze_cli,
                BRONZE_UI: _bronze_ui
            });
        }
    }

    function _setDiscountsDefault() internal {
        DISCOUNTS = DiscountsStruct({
            SPECIAL_CLI: 100,
            SPECIAL_UI: 100,
            DIAMOND_CLI: 100,
            DIAMOND_UI: 75,
            GOLD_CLI: 75,
            GOLD_UI: 75,
            SILVER_CLI: 50,
            SILVER_UI: 50,
            BRONZE_CLI: 25,
            BRONZE_UI: 25
        });
    }

    function loyalty() external view returns (LoyaltyStruct memory) {
        return LOYALTY;
    }

    function setLoyalty(
        uint256 _burn,
        uint256 _mint,
        uint256 _spend
    ) external onlyGnosis {
        if (_burn == 0 && _mint == 0 && _spend == 0) {
            _setLoyaltyDefault();
        } else {
            LOYALTY = LoyaltyStruct({BURN: _burn, MINT: _mint, SPEND: _spend});
        }
    }

    function _setLoyaltyDefault() internal {
        LOYALTY = LoyaltyStruct({BURN: 50, MINT: 100, SPEND: 50});
    }

    function relayer(address _account) external view returns (bool) {
        return RELAYER_ROLE[_account];
    }

    function addRelayer(address _account) external onlyGnosis {
        if (!RELAYER_ROLE[_account]) {
            RELAYER_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "RELAYER_ROLE");
        }
    }

    function removeRelayer(address _account) external onlyGnosis {
        if (RELAYER_ROLE[_account]) {
            RELAYER_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "RELAYER_ROLE");
        }
    }

    function blacklist(address _account) external view returns (bool) {
        return BLACKLIST_ROLE[_account];
    }

    function addBlacklist(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            if (!BLACKLIST_ROLE[_accounts[i]]) {
                BLACKLIST_ROLE[_accounts[i]] = true;
                emit RoleGranted(_accounts[i], _msgSender(), "BLACKLIST_ROLE");
            }
        }
    }

    function removeBlacklist(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            if (BLACKLIST_ROLE[_accounts[i]]) {
                BLACKLIST_ROLE[_accounts[i]] = false;
                emit RoleRevoked(_accounts[i], _msgSender(), "BLACKLIST_ROLE");
            }
        }
    }

    function special(address _account) external view returns (bool) {
        return SPECIAL_ROLE[_account];
    }

    function _addSpecial(address _account) internal {
        if (!SPECIAL_ROLE[_account]) {
            SPECIAL_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "SPECIAL_ROLE");
        }
    }

    function _removeSpecial(address _account) internal {
        if (SPECIAL_ROLE[_account]) {
            SPECIAL_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "SPECIAL_ROLE");
        }
    }

    function upgradeSpecial(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _addSpecial(_accounts[i]);
            _removeDiamond(_accounts[i]);
            _removeGold(_accounts[i]);
            _removeSilver(_accounts[i]);
            _removeBronze(_accounts[i]);
        }
    }

    function diamond(address _account) external view returns (bool) {
        return DIAMOND_ROLE[_account];
    }

    function _addDiamond(address _account) internal {
        if (!DIAMOND_ROLE[_account]) {
            DIAMOND_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "DIAMOND_ROLE");
        }
    }

    function _removeDiamond(address _account) internal {
        if (DIAMOND_ROLE[_account]) {
            DIAMOND_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "DIAMOND_ROLE");
        }
    }

    function upgradeDiamond(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSpecial(_accounts[i]);
            _addDiamond(_accounts[i]);
            _removeGold(_accounts[i]);
            _removeSilver(_accounts[i]);
            _removeBronze(_accounts[i]);
        }
    }

    function gold(address _account) external view returns (bool) {
        return GOLD_ROLE[_account];
    }

    function _addGold(address _account) internal {
        if (!GOLD_ROLE[_account]) {
            GOLD_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "GOLD_ROLE");
        }
    }

    function _removeGold(address _account) internal {
        if (GOLD_ROLE[_account]) {
            GOLD_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "GOLD_ROLE");
        }
    }

    function upgradeGold(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSpecial(_accounts[i]);
            _removeDiamond(_accounts[i]);
            _addGold(_accounts[i]);
            _removeSilver(_accounts[i]);
            _removeBronze(_accounts[i]);
        }
    }

    function silver(address _account) external view returns (bool) {
        return SILVER_ROLE[_account];
    }

    function _addSilver(address _account) internal {
        if (!SILVER_ROLE[_account]) {
            SILVER_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "SILVER_ROLE");
        }
    }

    function _removeSilver(address _account) internal {
        if (SILVER_ROLE[_account]) {
            SILVER_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "SILVER_ROLE");
        }
    }

    function upgradeSilver(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSpecial(_accounts[i]);
            _removeDiamond(_accounts[i]);
            _removeGold(_accounts[i]);
            _addSilver(_accounts[i]);
            _removeBronze(_accounts[i]);
        }
    }

    function bronze(address _account) external view returns (bool) {
        return BRONZE_ROLE[_account];
    }

    function _addBronze(address _account) internal {
        if (!BRONZE_ROLE[_account]) {
            BRONZE_ROLE[_account] = true;
            emit RoleGranted(_account, _msgSender(), "BRONZE_ROLE");
        }
    }

    function _removeBronze(address _account) internal {
        if (BRONZE_ROLE[_account]) {
            BRONZE_ROLE[_account] = false;
            emit RoleRevoked(_account, _msgSender(), "BRONZE_ROLE");
        }
    }

    function upgradeBronze(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSpecial(_accounts[i]);
            _removeDiamond(_accounts[i]);
            _removeGold(_accounts[i]);
            _removeSilver(_accounts[i]);
            _addBronze(_accounts[i]);
        }
    }

    function revokeRoles(address[] memory _accounts) external onlyRelayer {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSpecial(_accounts[i]);
            _removeDiamond(_accounts[i]);
            _removeGold(_accounts[i]);
            _removeSilver(_accounts[i]);
            _removeBronze(_accounts[i]);
        }
    }

    function snipe() external view returns (uint256) {
        return SNIPE.current();
    }

    function sniper() external view returns (uint256) {
        return SNIPER.current();
    }

    function sniperLoyaltyPoint(address _account)
        external
        view
        returns (uint256)
    {
        return SNIPER_LOYALTY_POINT[_account];
    }

    function _addSniperLoyaltyPoint(address _account, uint256 _point) internal {
        uint256 beforePoint = SNIPER_LOYALTY_POINT[_account];
        SNIPER_LOYALTY_POINT[_account] = beforePoint + _point;
        uint256 afterPoint = SNIPER_LOYALTY_POINT[_account];
        emit LoyaltyUpdated(_account, beforePoint, afterPoint);
    }

    function GnosisAddSniperLoyaltyPoint(
        address[] memory _accounts,
        uint256 _point
    ) external onlyGnosis {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _addSniperLoyaltyPoint(_accounts[i], _point);
        }
    }

    function _removeSniperLoyaltyPoint(address _account, uint256 _point)
        internal
    {
        uint256 beforePoint = SNIPER_LOYALTY_POINT[_account];
        SNIPER_LOYALTY_POINT[_account] = beforePoint - _point;
        uint256 afterPoint = SNIPER_LOYALTY_POINT[_account];
        emit LoyaltyUpdated(_account, beforePoint, afterPoint);
    }

    function GnosisRemoveSniperLoyaltyPoint(
        address[] memory _accounts,
        uint256 _point
    ) external onlyGnosis {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _removeSniperLoyaltyPoint(_accounts[i], _point);
        }
    }

    function sniperMarksmanStatus(address _account)
        external
        view
        returns (uint256)
    {
        return SNIPER_MARKSMAN_STATUS[_account];
    }

    function _updateSniperMarksmanStatus(address _account, uint256 _time)
        internal
    {
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _time;
        SNIPER_MARKSMAN_STATUS[_account] = endTime;
        emit MarksmanUpdated(_account, startTime, endTime);
    }

    function GnosisUpdateSniperMarksmanStatus(
        address[] memory _accounts,
        uint256 _time
    ) external onlyGnosis {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _updateSniperMarksmanStatus(_accounts[i], _time);
        }
    }

    function sniperWalletsCount(address _account)
        external
        view
        returns (uint256)
    {
        return SNIPER_WALLETS_COUNT[_account].current();
    }

    function _increaseSniperWalletsCount(address _account) internal {
        uint256 beforeCount = SNIPER_WALLETS_COUNT[_account].current();
        SNIPER_WALLETS_COUNT[_account].increment();
        uint256 afterCount = SNIPER_WALLETS_COUNT[_account].current();
        emit WalletsUpdated(_account, beforeCount, afterCount);
    }

    function GnosisIncreaseSniperWalletsCount(address[] memory _accounts)
        external
        onlyGnosis
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _increaseSniperWalletsCount(_accounts[i]);
        }
    }

    function _decreaseSniperWalletsCount(address _account) internal {
        uint256 beforeCount = SNIPER_WALLETS_COUNT[_account].current();
        SNIPER_WALLETS_COUNT[_account].decrement();
        uint256 afterCount = SNIPER_WALLETS_COUNT[_account].current();
        emit WalletsUpdated(_account, beforeCount, afterCount);
    }

    function GnosisDecreaseSniperWalletsCount(address[] memory _accounts)
        external
        onlyGnosis
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _decreaseSniperWalletsCount(_accounts[i]);
        }
    }

    function _resetSniperWalletsCount(address _account) internal {
        uint256 beforeCount = SNIPER_WALLETS_COUNT[_account].current();
        SNIPER_WALLETS_COUNT[_account].reset();
        uint256 afterCount = SNIPER_WALLETS_COUNT[_account].current();
        emit WalletsUpdated(_account, beforeCount, afterCount);
    }

    function GnosisResetSniperWalletsCount(address[] memory _accounts)
        external
        onlyGnosis
    {
        for (uint256 i = 0; i < _accounts.length; i++) {
            _resetSniperWalletsCount(_accounts[i]);
        }
    }

    function blockchainMultiplier(uint256 _blockchain)
        external
        view
        returns (uint256)
    {
        return BLOCKCHAIN_MULTIPLIER[_blockchain];
    }

    function setBlockchainMultiplier(uint256 _blockchain, uint256 _multiplier)
        external
        onlyGnosis
    {
        BLOCKCHAIN_MULTIPLIER[_blockchain] = _multiplier;
    }

    function sniperRate(
        uint256 _blockchain,
        address _account,
        uint256 _version
    ) public view returns (uint256) {
        uint256 multiplierPerSnipe = 100;
        if (BLOCKCHAIN_MULTIPLIER[_blockchain] != 0) {
            multiplierPerSnipe = BLOCKCHAIN_MULTIPLIER[_blockchain];
        }

        uint256 tierDiscountPercent = 0;
        if (SPECIAL_ROLE[_account]) {
            if (_version == 0) {
                tierDiscountPercent = DISCOUNTS.SPECIAL_CLI;
            } else {
                tierDiscountPercent = DISCOUNTS.SPECIAL_UI;
            }
        } else if (DIAMOND_ROLE[_account]) {
            if (_version == 0) {
                tierDiscountPercent = DISCOUNTS.DIAMOND_CLI;
            } else {
                tierDiscountPercent = DISCOUNTS.DIAMOND_UI;
            }
        } else if (GOLD_ROLE[_account]) {
            if (_version == 0) {
                tierDiscountPercent = DISCOUNTS.GOLD_CLI;
            } else {
                tierDiscountPercent = DISCOUNTS.GOLD_UI;
            }
        } else if (SILVER_ROLE[_account]) {
            if (_version == 0) {
                tierDiscountPercent = DISCOUNTS.SILVER_CLI;
            } else {
                tierDiscountPercent = DISCOUNTS.SILVER_UI;
            }
        } else if (BRONZE_ROLE[_account]) {
            if (_version == 0) {
                tierDiscountPercent = DISCOUNTS.BRONZE_CLI;
            } else {
                tierDiscountPercent = DISCOUNTS.BRONZE_UI;
            }
        }

        uint256 rateAfterDiscount = RATE - ((RATE * tierDiscountPercent) / 100);
        uint256 rateAfterMultiplier = rateAfterDiscount * multiplierPerSnipe;
        if (_version == 0) {
            return rateAfterMultiplier / 2;
        } else {
            return rateAfterMultiplier;
        }
    }

    function mintCredit(
        IERC20 _token,
        uint256 _amount,
        address _recipient
    ) external nonReentrant registerSniper {
        uint256 amountIn = _amount;
        if (address(_token) != DOLLAR) {
            address[] memory path = new address[](2);
            path[0] = address(_token);
            path[1] = DOLLAR;

            uint256[] memory amounts = ROUTER.getAmountsOut(_amount, path);
            amountIn = amounts[1];
        }

        uint256 creditFormula = amountIn * 100;
        uint256 amountOut = creditFormula / GOVERNANCE.DOLLAR_PEGGED_PER_CREDIT;
        uint256 amountOutMin = (1 ether * RATE) / 100;

        if (amountOut >= amountOutMin) {
            _token.safeTransferFrom(_msgSender(), address(this), amountIn);
            _token.safeTransfer(GNOSIS, (amountIn * SHARE.GNOSIS) / 100);
            _token.safeTransfer(ROYALTY, (amountIn * SHARE.ROYALTY) / 100);

            CREDIT.mint(_recipient, amountIn);
            _addSniperLoyaltyPoint(
                _msgSender(),
                (amountIn * LOYALTY.MINT) / 100
            );
        } else {
            revert("Too Little");
        }
    }

    function redeemLoyaltyPoint(uint256 _amount, address _recipient)
        external
        nonReentrant
        registerSniper
    {
        require(
            SNIPER_LOYALTY_POINT[_msgSender()] >= _amount,
            "Insufficient Point"
        );

        uint256 creditFormula = _amount * GOVERNANCE.CREDIT_PER_LOYALTY_POINT;
        uint256 amountOut = creditFormula / 100;
        uint256 amountOutMin = (1 ether * RATE) / 100;

        if (amountOut >= amountOutMin) {
            _removeSniperLoyaltyPoint(_msgSender(), _amount);
            CREDIT.mint(_recipient, amountOut);
        } else {
            revert("Too Little");
        }
    }

    function frontendMarksman(address _account) public view returns (bool) {
        return SNIPER_MARKSMAN_STATUS[_account] >= block.timestamp;
    }

    function activateMarksman(uint256 _duration)
        external
        nonReentrant
        registerSniper
    {
        require(!frontendMarksman(_msgSender()), "Marksman Active");
        require(_sniperRoleId(_msgSender()) >= 2, "No Permission");

        uint256 creditFormula;
        uint256 marksmanTime;
        if (_duration == 1) {
            creditFormula = 1 ether * GOVERNANCE.CREDIT_PER_MARKSMAN_DAILY;
            marksmanTime = 1 days;
        } else if (_duration == 7) {
            creditFormula = 1 ether * GOVERNANCE.CREDIT_PER_MARKSMAN_WEEKLY;
            marksmanTime = 7 days;
        } else if (_duration == 28) {
            creditFormula = 1 ether * GOVERNANCE.CREDIT_PER_MARKSMAN_MONTHLY;
            marksmanTime = 28 days;
        } else if (_duration == 99) {
            require(_sniperRoleId(_msgSender()) >= 3, "No Permission");

            creditFormula = 1 ether * GOVERNANCE.CREDIT_PER_MARKSMAN_INDEFINITE;
            marksmanTime = 365 days * 99;
        } else {
            revert("Invalid Duration");
        }

        if (_sniperRoleId(_msgSender()) >= 4) {
            creditFormula = creditFormula / 2;
        }

        uint256 amountIn = creditFormula / 100;
        CREDIT.safeTransferFrom(_msgSender(), GNOSIS, amountIn);
        _addSniperLoyaltyPoint(_msgSender(), (amountIn * LOYALTY.SPEND) / 100);
        _updateSniperMarksmanStatus(_msgSender(), marksmanTime);
    }

    function frontendWalletsCount(address _account)
        external
        view
        returns (uint256)
    {
        uint256 totalWalletsCount = SNIPER_WALLETS_COUNT[_account].current();
        if (SPECIAL_ROLE[_account] || DIAMOND_ROLE[_account]) {
            totalWalletsCount = totalWalletsCount + 5;
        } else if (GOLD_ROLE[_account]) {
            totalWalletsCount = totalWalletsCount + 1;
        }

        return totalWalletsCount + 1;
    }

    function upgradeWalletsCount() external nonReentrant registerSniper {
        require(_sniperRoleId(_msgSender()) >= 3, "No Permission");

        uint256 amountIn = (1 ether *
            GOVERNANCE.CREDIT_PER_SNIPER_WALLETS_COUNT) / 100;

        CREDIT.safeTransferFrom(_msgSender(), GNOSIS, amountIn);
        _addSniperLoyaltyPoint(_msgSender(), (amountIn * LOYALTY.SPEND) / 100);
        _increaseSniperWalletsCount(_msgSender());
    }

    function executeSnipe(
        uint256 _blockchain,
        uint256 _version,
        uint256 _multiplier
    ) external nonReentrant registerSnipe registerSniper returns (bool) {
        require(_multiplier > 0, "Math Overflow");

        uint256 costPerSnipe = sniperRate(_blockchain, _msgSender(), _version);
        costPerSnipe = costPerSnipe * _multiplier;
        CREDIT.burn(_msgSender(), costPerSnipe);
        _addSniperLoyaltyPoint(
            _msgSender(),
            (costPerSnipe * LOYALTY.BURN) / 100
        );

        return true;
    }

    function _sniperRoleId(address _account) internal view returns (uint256) {
        if (DIAMOND_ROLE[_account]) {
            return 4;
        } else if (GOLD_ROLE[_account]) {
            return 3;
        } else if (SILVER_ROLE[_account]) {
            return 2;
        } else if (BRONZE_ROLE[_account]) {
            return 1;
        } else {
            return 0;
        }
    }

    function version() external pure returns (string memory) {
        return "1.0.0";
    }
}

import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "@openzeppelin/contracts/utils/Context.sol";

contract mdtProxy is TransparentUpgradeableProxy, Context {
    constructor(address _logic)
        TransparentUpgradeableProxy(_logic, _msgSender(), "")
    {}
}