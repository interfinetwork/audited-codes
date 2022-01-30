//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IPool.sol";
library ConfigurePoolLibrary {
  using SafeMath for uint256;
  using SafeMath for uint32;
  using SafeMath for uint16;
  using SafeMath for uint8;

  function configurePool(
    address poolAddress,
    IPool.PoolModel calldata _pool, 
    IPool.PoolDetails calldata _details, 
    address _admin, 
    uint8 _poolPercentFee,
    uint8 _poolTokenPercentFee
  )
    public 
  {   
    IPool(poolAddress).setPoolModel(_pool, _details, _admin, msg.sender, _poolPercentFee);
    IERC20Metadata projectToken = IERC20Metadata(_pool.projectTokenAddress);
    uint256 totalTokenAmount=_pool.hardCap.mul(_pool.presaleRate).add(_pool.hardCap.mul(_pool.dexRate.mul(_pool.dexCapPercent))/100);
    totalTokenAmount=totalTokenAmount.div(10**18);
    totalTokenAmount=totalTokenAmount.add(totalTokenAmount.mul(_poolTokenPercentFee)/100);
    require(totalTokenAmount<=projectToken.balanceOf(msg.sender),"insufficient funds for transfer");
    projectToken.transferFrom(msg.sender, poolAddress, projectToken.balanceOf(msg.sender));
    // require(projectToken.balanceOf(poolAddress)==totalTokenAmount, "remove tax");
    //pay for the project owner
    // if(_poolTokenPercentFee>0)
    //   projectToken.transferFrom(msg.sender, _admin, totalTokenAmount.mul(_poolTokenPercentFee)/100);
  }
  

 
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


import "./Pool.sol";
library DeployPoolLibrary {

  function deployPool(
    address projectTokenAddress
  )
    public 
    returns (address poolAddress)
  {
    bytes memory bytecode = type(Pool).creationCode;
    bytes32 salt = keccak256(abi.encodePacked(msg.sender, projectTokenAddress));
    assembly {
        poolAddress := create2(0, add(bytecode, 32), mload(bytecode), salt)
    }
    
    return poolAddress;
  }
  

 
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;


import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./IPool.sol";
import "./DeployPoolLibrary.sol";
import "./ConfigurePoolLibrary.sol";
contract IDO is OwnableUpgradeable {
  using SafeMath for uint256;
  using SafeMath for uint32;
  using SafeMath for uint16;
  using SafeMath for uint8;


  address[] public poolAddresses;
  uint256[] public poolFixedFee;
  uint8 public poolPercentFee;
  uint8 public poolTokenPercentFee;
  mapping(address => address) public poolOwners;
  struct PoolModel {  
    uint256 hardCap; // how much project wants to raise
    uint256 softCap; // how much of the raise will be accepted as successful IDO
    uint256 presaleRate;
    uint8 dexCapPercent;
    uint256 dexRate;
    uint8 tier;
  }

  struct PoolDetails {
    uint256 startDateTime;
    uint256 endDateTime;
    uint256 listDateTime;
    uint256 minAllocationPerUser;
    uint256 maxAllocationPerUser;    
    uint16 dexLockup;
    // bool refund;
    bool whitelistable;
  }

  event LogPoolCreated(address poolOwner, address pool);
  event LogPoolKYCUpdate(address pool, bool kyc);
  event LogPoolAuditUpdate(address pool, bool audit, string auditLink);

  event LogPoolTierUpdate(address pool, uint8 tier);
  event LogPoolExtraData(address pool, string _extraData);
  event LogDeposit(address pool, address participant, uint256 amount);
  event LogPoolStatusChanged(address pool, uint256 status);  
  event LogFeeChanged(uint256[] poolFixedFee,
   uint8 poolPercentFee, uint8 poolTokenPercentFee);  
  event LogPoolRemoved(address pool);  
  event LogAddressWhitelisted(address pool, address[] whitelistedAddresses);
  event LogUpdateWhitelistable(address _pool, bool whitelistable);
  modifier _feeEnough(uint8 tier) {
    require(
      (msg.value >= poolFixedFee[tier]),
      "Not enough fee!"
    );
    _;
  }

  modifier _onlyPoolOwner(address _pool, address _owner) {
    require(
      poolOwners[_pool] == _owner,
      "Not Owner!"
    );
    _;
  }
  modifier _onlyPoolOwnerAndOwner(address _pool, address _owner) {
    require(
      poolOwners[_pool] == _owner || _owner==owner(),
      "Not Owner!"
    );
    _;
  }

  function initialize(uint256[] memory _poolFixedFee, uint8 _poolPercentFee, uint8 _poolTokenPercentFee) public initializer {
    OwnableUpgradeable.__Ownable_init();
    OwnableUpgradeable.__Ownable_init_unchained();
    poolFixedFee=_poolFixedFee;
    poolPercentFee=_poolPercentFee;
    poolTokenPercentFee=_poolTokenPercentFee;
  }

  function createPool(
    PoolModel calldata model,
    PoolDetails calldata details,   
    address _projectTokenAddress,
    string memory _extraData
  )
    external
    payable
    _feeEnough(model.tier)
    returns (address poolAddress)
  {
    poolAddress=DeployPoolLibrary.deployPool(_projectTokenAddress);
    ConfigurePoolLibrary.configurePool(
      poolAddress,
      IPool.PoolModel({
      hardCap: model.hardCap,
      softCap: model.softCap,      
      projectTokenAddress:_projectTokenAddress,      
      presaleRate:model.presaleRate,
      dexCapPercent:model.dexCapPercent,
      dexRate:model.dexRate,     
      kyc:false,
      status: IPool.PoolStatus(0),
      tier: IPool.PoolTier(model.tier)
    }), 
    IPool.PoolDetails({
      startDateTime: details.startDateTime,
      endDateTime: details.endDateTime,
      listDateTime: details.listDateTime,
      minAllocationPerUser:details.minAllocationPerUser,
      maxAllocationPerUser:details.maxAllocationPerUser,
      dexLockup:details.dexLockup,
      extraData:_extraData,
      // refund:details.refund,
      whitelistable:details.whitelistable,
      audit:false,
      auditLink:""
    }), owner(), poolPercentFee, poolTokenPercentFee);
    if(msg.value>0)
      payable(owner()).transfer(msg.value);
    
    poolAddresses.push(poolAddress);
    poolOwners[poolAddress]=msg.sender;
    emit LogPoolCreated(msg.sender, poolAddress);
  }

  function setAdminFee(uint256[] memory _poolFixedFee,
   uint8 _poolPercentFee, uint8 _poolTokenPercentFee)
  public
  onlyOwner()
  {
    poolFixedFee=_poolFixedFee;   
    poolPercentFee=_poolPercentFee;
    poolTokenPercentFee=_poolTokenPercentFee;
    emit LogFeeChanged(poolFixedFee, poolPercentFee, poolTokenPercentFee);
  }

  function removePool(address pool)
    external
    onlyOwner()
  {
    // try IPool(pool).status() returns (IPool.PoolStatus status) {
    //   if(status!=IPool.PoolStatus.Cancelled && status!=IPool.PoolStatus.Finished && status!=IPool.PoolStatus.Ended)
    //     IPool(pool).cancelPool(); 
    // } catch {
    // }
    
    for (uint index=0; index<poolAddresses.length; index++) {
      if(poolAddresses[uint(index)]==pool){
        for (uint i = index; i<poolAddresses.length-1; i++){
            poolAddresses[i] = poolAddresses[i+1];
        }
        delete poolAddresses[poolAddresses.length-1];
        poolAddresses.pop();
        break;
      }
    }
    emit LogPoolRemoved(pool);
  }

  function updateExtraData(address _pool, string memory _extraData)
    external
    _onlyPoolOwner(_pool, msg.sender)
  {
    IPool(_pool).updateExtraData(_extraData);  
    emit LogPoolExtraData(_pool, _extraData);
  }

  function updateKYCStatus(address _pool, bool _kyc)
    external
    onlyOwner()
  {
    IPool(_pool).updateKYCStatus(_kyc);  
    emit LogPoolKYCUpdate(_pool, _kyc);
  }

  function updateAuditStatus(address _pool, bool _audit, string memory _auditLink)
    external
    onlyOwner()
  {
    IPool(_pool).updateAuditStatus(_audit, _auditLink);  
    emit LogPoolAuditUpdate(_pool, _audit, _auditLink);
  }

  function updateTierStatus(address _pool, uint8 _tier)
    external
    onlyOwner()
  {
    IPool(_pool).updateTierStatus(IPool.PoolTier(_tier));  
    emit LogPoolTierUpdate(_pool, _tier);
  }




  function addAddressesToWhitelist(address _pool, address[] calldata whitelistedAddresses)
    external
    _onlyPoolOwner(_pool, msg.sender)
  {
    IPool(_pool).addAddressesToWhitelist(whitelistedAddresses); 
    emit LogAddressWhitelisted(_pool, whitelistedAddresses);
  }

  function updateWhitelistable(address _pool, bool whitelistable)
    external
    _onlyPoolOwner(_pool, msg.sender)
  {
    IPool(_pool).updateWhitelistable(whitelistable); 
    emit LogUpdateWhitelistable(_pool, whitelistable);
  }

  function deposit(address _pool)
    external
    payable
  {
    IPool(_pool).deposit{value: msg.value}(msg.sender); 
    emit LogDeposit(_pool, msg.sender, msg.value);
  }

  function cancelPool(address _pool)
    external
    _onlyPoolOwnerAndOwner(_pool, msg.sender)
  {
    IPool(_pool).cancelPool(); 
    emit LogPoolStatusChanged(_pool, uint(IPool.PoolStatus.Cancelled));
  }

  function claimToken(address _pool)
    external
  {
    IPool(_pool).claimToken(msg.sender); 
  }

  function refund(address _pool)
    external
  {
    IPool(_pool).refund(msg.sender); 
    emit LogPoolStatusChanged(_pool, uint(IPool.PoolStatus.Cancelled));
  }


  function endPool(address _pool)
    external
    _onlyPoolOwner(_pool, msg.sender)
  {
    IPool(_pool).endPool(); 
    emit LogPoolStatusChanged(_pool, uint(IPool.PoolStatus.Listed));
  }

  function unlockLiquidityDex(address _pool)
    external    
  {
    IPool(_pool).unlockLiquidityDex(); 
    emit LogPoolStatusChanged(_pool, uint(IPool.PoolStatus.Unlocked));
  }

}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface IPool {
  struct PoolModel {
    uint256 hardCap; // how much project wants to raise
    uint256 softCap; // how much of the raise will be accepted as successful IDO
    uint256 presaleRate;
    uint8 dexCapPercent;
    uint256 dexRate;
    address projectTokenAddress; //the address of the token that project is offering in return   
    PoolStatus status; //: by default “Upcoming”,
    PoolTier tier;
    bool kyc;
  }

  struct PoolDetails {
    uint256 startDateTime;
    uint256 endDateTime;
    uint256 listDateTime;
    uint256 minAllocationPerUser;
    uint256 maxAllocationPerUser;    
    uint16 dexLockup;
    string extraData;
    // bool refund;
    bool whitelistable;
    bool audit;
    string auditLink;
  }

  struct Participations {
    ParticipantDetails[] investorsDetails;
    uint256 count;
  }

  struct ParticipantDetails {
    address addressOfParticipant;
    uint256 totalRaisedInWei;
  }

  enum PoolStatus {
    Inprogress,
    Listed,
    Cancelled,
    Unlocked
  }
  enum PoolTier {
    Nothing,
    Gold,
    Platinum,
    Diamond
  }

  function setPoolModel(PoolModel calldata _pool, PoolDetails calldata _details, address _adminOwner, address _poolOwner, uint8 _poolETHFee)
    external;
  function updateExtraData(string memory _detailedPoolInfo) external;
  function updateKYCStatus(bool _kyc) external;
  function updateAuditStatus(bool _audit, string memory _auditLink) external;
  function updateTierStatus(PoolTier _tier) external;
  function addAddressesToWhitelist(address[] calldata whitelistedAddresses) external;
  function updateWhitelistable(bool _whitelistable) external;
  function deposit(address sender) external payable;
  function cancelPool() external;
  function claimToken(address claimer) external;
  function refund(address claimer) external;
  function endPool() external;
  function unlockLiquidityDex() external;
  function status() external view returns (PoolStatus);
  function endDateTime()  external view returns (uint256);
  function listDateTime()  external view returns (uint256);
  function startDateTime()  external view returns (uint256);
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./IPool.sol";
import "./Validations.sol";
import "./Whitelist.sol";
import "./IPancakeRouter02.sol";
import "./IPancakeFactory.sol";
import "./IPancakePair.sol";
import "./PoolLibrary.sol";
contract Pool is IPool, Whitelist {
  using SafeMath for uint256;
  using SafeMath for uint16;
  using SafeMath for uint8;
  IERC20Metadata private projectToken;
  PoolModel public poolInformation;
  PoolDetails public poolDetails;
  address private poolOwner;
  address private admin;
  address private factory;
  address[] public participantsAddress;
  mapping(address => uint256) public collaborations;
  uint256 public _weiRaised = 0;
  mapping(address => bool) public _didRefund;
  uint8 public  poolPercentFee;
  constructor() {
      factory = msg.sender;
  }


  function setPoolModel(PoolModel calldata _pool, IPool.PoolDetails calldata _details, address _admin, address _poolOwner, uint8 _poolPercentFee)
    external
    override
    _onlyFactory 
  {
    PoolLibrary._preValidatePoolCreation(_pool, _poolOwner, _poolPercentFee);
    poolInformation = _pool;
    PoolLibrary._preValidatePoolDetails(_details);
    poolDetails=_details;
    poolOwner=_poolOwner;
    admin=_admin;
    poolPercentFee=_poolPercentFee;
  }


  modifier _onlyFactory() {
    require(
      address(factory) == msg.sender,
      "Not factory!"
    );
    _;
  }
  


  function updateExtraData(string memory _extraData)
    external
    override    
    _onlyFactory
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    poolDetails.extraData = _extraData;  
  }

  function updateKYCStatus(bool _kyc)
    external
    override    
    _onlyFactory
  {
    poolInformation.kyc = _kyc;    
  }

  function updateAuditStatus(bool _audit, string memory _auditLink)
    external
    override    
    _onlyFactory
  {
    poolDetails.audit = _audit;    
    poolDetails.auditLink = _auditLink;  
  }

  function updateTierStatus(PoolTier _tier)
    external
    override    
    _onlyFactory
  {
    poolInformation.tier = _tier;    
  }

  function updateWhitelistable(bool _whitelistable)
    external
    override    
    _onlyFactory
  {
    PoolLibrary._poolIsUpcoming(poolInformation.status, poolDetails);
    poolDetails.whitelistable = _whitelistable;    
  }


  function addAddressesToWhitelist(address[] calldata whitelistedAddresses)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    addToWhitelist(whitelistedAddresses);
  }

  function deposit(address sender)
    external
    payable
    override
    _onlyFactory        
  {
     PoolLibrary._poolIsOngoing(poolInformation.status, poolDetails);
    _onlyWhitelisted(sender);
    PoolLibrary._minAllocationNotPassed(poolDetails.minAllocationPerUser, _weiRaised, poolInformation.hardCap);
    PoolLibrary._maxAllocationNotPassed(poolDetails.maxAllocationPerUser, collaborations[sender]);
    PoolLibrary._hardCapNotPassed(poolInformation.hardCap, _weiRaised);

   
    uint256 _amount = msg.value;
    _increaseRaisedWEI(_amount);
    _addToParticipants(sender);
  }

  function cancelPool()
    external
    override
    _onlyFactory    
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);
    poolInformation.status=PoolStatus.Cancelled;
    if(projectToken.balanceOf(address(this))>0)
      projectToken.transfer(address(poolOwner), projectToken.balanceOf(address(this)));
  }

  function refund(address claimer)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsCancelled(poolInformation, poolDetails, _weiRaised);
    if(_didRefund[claimer]!=true && collaborations[claimer]>0){
      _didRefund[claimer]=true;
      payable(claimer).transfer(collaborations[claimer]);
    }
    if(poolInformation.softCap<=_weiRaised)
      poolInformation.status=PoolStatus.Cancelled;
  }

  function claimToken(address claimer)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsListed(poolInformation);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);  
    uint256 _amount = collaborations[claimer].mul(poolInformation.presaleRate).div(10**18); 
    if(_didRefund[claimer]!=true && _amount>0){
      _didRefund[claimer]=true;
      projectToken.transfer(claimer, _amount);
    }
    
  }
  function endPool()
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsReadyList(poolInformation, poolDetails, _weiRaised);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);

    //pay for the project owner
    uint256 toAdminETHAmount=_weiRaised.mul(poolPercentFee).div(100);
    if(toAdminETHAmount>0)
      payable(admin).transfer(toAdminETHAmount);      
    uint256 rest=_weiRaised.sub(toAdminETHAmount);
    // send ETH and Token back to the pool owner
    uint256 dexETHAmount=poolInformation.hardCap.mul(poolInformation.dexCapPercent).div(100);
    if(dexETHAmount>=rest){
      dexETHAmount=rest;      
    }else{
      uint256 _toPoolOwner=rest.sub(dexETHAmount);
      if(_toPoolOwner>0)
        payable(poolOwner).transfer(_toPoolOwner);
    }
    uint256 dexTokenAmount=dexETHAmount.mul(poolInformation.dexRate).div(10**18); 
    //pay to the admin owner
    uint256 tokenToAdmin=projectToken.balanceOf(address(this)).sub(dexTokenAmount).sub(poolInformation.hardCap.mul(poolInformation.presaleRate).div(10**18));
    if(tokenToAdmin>0){
      projectToken.transfer(address(admin), tokenToAdmin);
      require(tokenToAdmin<=projectToken.balanceOf(address(admin)), "remove tax");
    }
    //refund to the pool owner
    uint256 tokenRest=projectToken.balanceOf(address(this)).sub(dexTokenAmount).sub(_weiRaised.mul(poolInformation.presaleRate).div(10**18)).sub(tokenToAdmin);
    // uint256 claimedToken=_weiRaised.mul(poolInformation.presaleRate).div(10**18)
    // if(poolDetails.refund==true)
    if(tokenRest>0)
      projectToken.transfer(address(poolOwner), tokenRest);
    // else
    //   projectToken.transfer(address(0), tokenRest);
    poolInformation.status=PoolStatus.Listed;
    
    ///////////////////////////////////////////////////////////////
    //When deploy on mainnet, upcomment 
    // add the liquidity
    IPancakeFactory pancakeFactory = IPancakeFactory(address(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc));
    address LPAddress=pancakeFactory.getPair(poolInformation.projectTokenAddress, address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd));
    require(LPAddress!=address(0x0), "already existed!");
    IPancakeRouter02 pancakeRouter = IPancakeRouter02(address(0x10ED43C718714eb63d5aA57B78B54704E256024E));    
    pancakeRouter.addLiquidityETH{value: dexETHAmount}(
        poolInformation.projectTokenAddress,
        dexTokenAmount,
        0, 
        0, 
        address(this),
        block.timestamp + 360
    );
    

  }

  function unlockLiquidityDex()
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsReadyUnlock(poolInformation, poolDetails);
    IPancakeFactory pancakeFactory = IPancakeFactory(address(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc));
    address LPAddress=pancakeFactory.getPair(poolInformation.projectTokenAddress, address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd));
    IPancakePair pancakePair=IPancakePair(LPAddress);
    uint LPBalance=pancakePair.balanceOf(address(this));
    if(LPBalance>0)
      pancakePair.transfer(poolOwner, LPBalance);
    poolInformation.status=IPool.PoolStatus.Unlocked;
  }


 function status() 
    external override view
    returns (IPool.PoolStatus)
  {
    return poolInformation.status;
  }

  function endDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.endDateTime;
  }
  function listDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.listDateTime;
  }
  function startDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.startDateTime;
  }

  function _increaseRaisedWEI(uint256 _amount) private {
    require(_amount > 0, "No WEI found!");

    _weiRaised =_weiRaised.add(_amount);

  }

  function _addToParticipants(address _address) private {
    if (!_didAlreadyParticipated(_address)) _addToListOfParticipants(_address);
    _keepRecordOfWEIRaised(_address);
  }

  function _didAlreadyParticipated(address _address)
    public
    view
    returns (bool isIt)
  {
    isIt = collaborations[_address] > 0;
  }

  function _addToListOfParticipants(address _address) private {
    participantsAddress.push(_address);
  }

  function _keepRecordOfWEIRaised(address _address) private {
    collaborations[_address] += msg.value;
  }

  function _onlyWhitelisted(address sender) public view {
    require(!poolDetails.whitelistable || block.timestamp>=poolDetails.startDateTime+10 minutes || isWhitelisted(sender), "Not!");
  }

}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import "./IPool.sol";
import "./Validations.sol";
import "./Whitelist.sol";
import "./IPancakeRouter02.sol";
import "./IPancakeFactory.sol";
import "./IPancakePair.sol";
import "./PoolLibrary.sol";
contract Pool is IPool, Whitelist {
  using SafeMath for uint256;
  using SafeMath for uint16;
  using SafeMath for uint8;
  IERC20Metadata private projectToken;
  PoolModel public poolInformation;
  PoolDetails public poolDetails;
  address private poolOwner;
  address private admin;
  address private factory;
  address[] public participantsAddress;
  mapping(address => uint256) public collaborations;
  uint256 public _weiRaised = 0;
  mapping(address => bool) public _didRefund;
  uint8 public  poolPercentFee;
  constructor() {
      factory = msg.sender;
  }


  function setPoolModel(PoolModel calldata _pool, IPool.PoolDetails calldata _details, address _admin, address _poolOwner, uint8 _poolPercentFee)
    external
    override
    _onlyFactory 
  {
    PoolLibrary._preValidatePoolCreation(_pool, _poolOwner, _poolPercentFee);
    poolInformation = _pool;
    PoolLibrary._preValidatePoolDetails(_details);
    poolDetails=_details;
    poolOwner=_poolOwner;
    admin=_admin;
    poolPercentFee=_poolPercentFee;
  }


  modifier _onlyFactory() {
    require(
      address(factory) == msg.sender,
      "Not factory!"
    );
    _;
  }
  


  function updateExtraData(string memory _extraData)
    external
    override    
    _onlyFactory
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    poolDetails.extraData = _extraData;  
  }

  function updateKYCStatus(bool _kyc)
    external
    override    
    _onlyFactory
  {
    poolInformation.kyc = _kyc;    
  }

  function updateAuditStatus(bool _audit, string memory _auditLink)
    external
    override    
    _onlyFactory
  {
    poolDetails.audit = _audit;    
    poolDetails.auditLink = _auditLink;  
  }

  function updateTierStatus(PoolTier _tier)
    external
    override    
    _onlyFactory
  {
    poolInformation.tier = _tier;    
  }

  function updateWhitelistable(bool _whitelistable)
    external
    override    
    _onlyFactory
  {
    PoolLibrary._poolIsUpcoming(poolInformation.status, poolDetails);
    poolDetails.whitelistable = _whitelistable;    
  }


  function addAddressesToWhitelist(address[] calldata whitelistedAddresses)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    addToWhitelist(whitelistedAddresses);
  }

  function deposit(address sender)
    external
    payable
    override
    _onlyFactory        
  {
     PoolLibrary._poolIsOngoing(poolInformation.status, poolDetails);
    _onlyWhitelisted(sender);
    PoolLibrary._minAllocationNotPassed(poolDetails.minAllocationPerUser, _weiRaised, poolInformation.hardCap);
    PoolLibrary._maxAllocationNotPassed(poolDetails.maxAllocationPerUser, collaborations[sender]);
    PoolLibrary._hardCapNotPassed(poolInformation.hardCap, _weiRaised);

   
    uint256 _amount = msg.value;
    _increaseRaisedWEI(_amount);
    _addToParticipants(sender);
  }

  function cancelPool()
    external
    override
    _onlyFactory    
  {
    PoolLibrary._poolIsNotCancelled(poolInformation);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);
    poolInformation.status=PoolStatus.Cancelled;
    if(projectToken.balanceOf(address(this))>0)
      projectToken.transfer(address(poolOwner), projectToken.balanceOf(address(this)));
  }

  function refund(address claimer)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsCancelled(poolInformation, poolDetails, _weiRaised);
    if(_didRefund[claimer]!=true && collaborations[claimer]>0){
      _didRefund[claimer]=true;
      payable(claimer).transfer(collaborations[claimer]);
    }
    if(poolInformation.softCap<=_weiRaised)
      poolInformation.status=PoolStatus.Cancelled;
  }

  function claimToken(address claimer)
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsListed(poolInformation);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);  
    uint256 _amount = collaborations[claimer].mul(poolInformation.presaleRate).div(10**18); 
    if(_didRefund[claimer]!=true && _amount>0){
      _didRefund[claimer]=true;
      projectToken.transfer(claimer, _amount);
    }
    
  }
  function endPool()
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsReadyList(poolInformation, poolDetails, _weiRaised);
    projectToken = IERC20Metadata(poolInformation.projectTokenAddress);

    //pay for the project owner
    uint256 toAdminETHAmount=_weiRaised.mul(poolPercentFee).div(100);
    if(toAdminETHAmount>0)
      payable(admin).transfer(toAdminETHAmount);      
    uint256 rest=_weiRaised.sub(toAdminETHAmount);
    // send ETH and Token back to the pool owner
    uint256 dexETHAmount=poolInformation.hardCap.mul(poolInformation.dexCapPercent).div(100);
    if(dexETHAmount>=rest){
      dexETHAmount=rest;      
    }else{
      uint256 _toPoolOwner=rest.sub(dexETHAmount);
      if(_toPoolOwner>0)
        payable(poolOwner).transfer(_toPoolOwner);
    }
    uint256 dexTokenAmount=dexETHAmount.mul(poolInformation.dexRate).div(10**18); 
    //pay to the admin owner
    uint256 tokenToAdmin=projectToken.balanceOf(address(this)).sub(dexTokenAmount).sub(poolInformation.hardCap.mul(poolInformation.presaleRate).div(10**18));
    if(tokenToAdmin>0){
      projectToken.transfer(address(admin), tokenToAdmin);
      require(tokenToAdmin<=projectToken.balanceOf(address(admin)), "remove tax");
    }
    //refund to the pool owner
    uint256 tokenRest=projectToken.balanceOf(address(this)).sub(dexTokenAmount).sub(_weiRaised.mul(poolInformation.presaleRate).div(10**18)).sub(tokenToAdmin);
    // uint256 claimedToken=_weiRaised.mul(poolInformation.presaleRate).div(10**18)
    // if(poolDetails.refund==true)
    if(tokenRest>0)
      projectToken.transfer(address(poolOwner), tokenRest);
    // else
    //   projectToken.transfer(address(0), tokenRest);
    poolInformation.status=PoolStatus.Listed;
    
    ///////////////////////////////////////////////////////////////
    //When deploy on mainnet, upcomment 
    // add the liquidity
    IPancakeFactory pancakeFactory = IPancakeFactory(address(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc));
    address LPAddress=pancakeFactory.getPair(poolInformation.projectTokenAddress, address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd));
    require(LPAddress!=address(0x0), "already existed!");
    IPancakeRouter02 pancakeRouter = IPancakeRouter02(address(0x10ED43C718714eb63d5aA57B78B54704E256024E));    
    pancakeRouter.addLiquidityETH{value: dexETHAmount}(
        poolInformation.projectTokenAddress,
        dexTokenAmount,
        0, 
        0, 
        address(this),
        block.timestamp + 360
    );
    

  }

  function unlockLiquidityDex()
    external
    override
    _onlyFactory
  {
    PoolLibrary._poolIsReadyUnlock(poolInformation, poolDetails);
    IPancakeFactory pancakeFactory = IPancakeFactory(address(0xB7926C0430Afb07AA7DEfDE6DA862aE0Bde767bc));
    address LPAddress=pancakeFactory.getPair(poolInformation.projectTokenAddress, address(0xae13d989daC2f0dEbFf460aC112a837C89BAa7cd));
    IPancakePair pancakePair=IPancakePair(LPAddress);
    uint LPBalance=pancakePair.balanceOf(address(this));
    if(LPBalance>0)
      pancakePair.transfer(poolOwner, LPBalance);
    poolInformation.status=IPool.PoolStatus.Unlocked;
  }


 function status() 
    external override view
    returns (IPool.PoolStatus)
  {
    return poolInformation.status;
  }

  function endDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.endDateTime;
  }
  function listDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.listDateTime;
  }
  function startDateTime() 
    external override view
    returns (uint256)
  {
    return poolDetails.startDateTime;
  }

  function _increaseRaisedWEI(uint256 _amount) private {
    require(_amount > 0, "No WEI found!");

    _weiRaised =_weiRaised.add(_amount);

  }

  function _addToParticipants(address _address) private {
    if (!_didAlreadyParticipated(_address)) _addToListOfParticipants(_address);
    _keepRecordOfWEIRaised(_address);
  }

  function _didAlreadyParticipated(address _address)
    public
    view
    returns (bool isIt)
  {
    isIt = collaborations[_address] > 0;
  }

  function _addToListOfParticipants(address _address) private {
    participantsAddress.push(_address);
  }

  function _keepRecordOfWEIRaised(address _address) private {
    collaborations[_address] += msg.value;
  }

  function _onlyWhitelisted(address sender) public view {
    require(!poolDetails.whitelistable || block.timestamp>=poolDetails.startDateTime+10 minutes || isWhitelisted(sender), "Not!");
  }

}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProjectToken is ERC20 {
  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _initialSupply
  ) ERC20(_name, _symbol) {
    _mint(msg.sender, _initialSupply);
  }
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract ProjectToken is ERC20 {
  constructor(
    string memory _name,
    string memory _symbol,
    uint256 _initialSupply
  ) ERC20(_name, _symbol) {
    _mint(msg.sender, _initialSupply);
  }
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import "@openzeppelin/contracts/access/Ownable.sol";
import "./Validations.sol";

contract Whitelist {
  mapping(address => bool) private whitelistedAddressesMap;
  address[] public whitelistedAddressesArray;

  event AddedToWhitelist(address indexed account);
  event RemovedFromWhitelist(address indexed accout);

  constructor() {}

  function addToWhitelist(address[] calldata _addresses)
    internal
    returns (bool success)
  {
    require(_addresses.length > 0, "an array of address is expected");

    for (uint256 i = 0; i < _addresses.length; i++) {
      address userAddress = _addresses[i];

      Validations.revertOnZeroAddress(userAddress);

      if (!isAddressWhitelisted(userAddress))
        addAddressToWhitelist(userAddress);
    }
    success = true;
  }

  function isWhitelisted(address _address)
    internal
    view
    _nonZeroAddress(_address)
    returns (bool isIt)
  {
    isIt = whitelistedAddressesMap[_address];
  }


  modifier _nonZeroAddress(address _address) {
    Validations.revertOnZeroAddress(_address);
    _;
  }

  function isAddressWhitelisted(address _address)
    private
    view
    returns (bool isIt)
  {
    isIt = whitelistedAddressesMap[_address];
  }

  function addAddressToWhitelist(address _address) private {
    whitelistedAddressesMap[_address] = true;
    whitelistedAddressesArray.push(_address);
    emit AddedToWhitelist(_address);
  }
}