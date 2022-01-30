//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

interface ILock {
  event LockAdded(address _token, uint256 _endDateTime, uint256 _amount, address _owner, bool _isLiquidity, address creator, uint256 _startDateTime);
  event UnlockLiquidity(address _token, uint256 _endDateTime, uint256 _amount, address _owner);
  event UnlockToken(address _token, uint256 _endDateTime, uint256 _amount, address _owner);

  struct TokenList {
    uint256 amount;
    uint256 startDateTime;
    uint256 endDateTime;
    address owner;
    address creator;
  }
  function liquidities(uint) external view returns (address);
  function tokens(uint) external view returns (address);
  function add(address _token, uint256 _endDateTime, uint256 _amount, address _owner, bool _isLiquidity) external;
  function unlockLiquidity(address _token) external returns (bool);
  function unlockToken(address _token) external returns (bool);
}
//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "./IPancakePair.sol";
import "./ILock.sol";
contract Lock is ILock {
  using SafeMath for uint256;
  address[] public override liquidities;
  address[] public override tokens;

  mapping(address=>TokenList[]) public liquidityList;
  mapping(address=>TokenList[]) public tokenList;
  function add(address _token, uint256 _endDateTime, uint256 _amount, address _owner, bool _isLiquidity) external override{
    require(_amount>0, "zero amount!");
    require(_endDateTime>block.timestamp,"duration!");
    require(_token!=address(0x0),"duration!");
    require(_owner!=address(0x0),"owner!");
    if(_isLiquidity){      
      address token0=IPancakePair(_token).token0();
      address token1=IPancakePair(_token).token1();
      require(token0!=address(0x0) && token1!=address(0x0), "not a liquidity");
      IPancakePair(_token).transferFrom(msg.sender, address(this), _amount);
      if(liquidityList[_token].length==0)
        liquidities.push(_token);
      bool isExisted=false;
      for(uint i=0;i<liquidityList[_token].length;i++){
        if(liquidityList[_token][i].owner==_owner && liquidityList[_token][i].endDateTime==_endDateTime){
          if(liquidityList[_token][i].amount==0){
            liquidityList[_token][i].startDateTime=block.timestamp;
          }
          liquidityList[_token][i].amount=liquidityList[_token][i].amount.add(_amount);
          isExisted=true;
          break;
        }
      }
      if(!isExisted){
        liquidityList[_token].push(TokenList({
          amount:_amount,
          startDateTime:block.timestamp,
          endDateTime:_endDateTime,
          owner:_owner,
          creator:msg.sender
        }));
      }      
    }else{
      IERC20Metadata(_token).transferFrom(msg.sender, address(this), _amount);
      if(tokenList[_token].length==0)
        tokens.push(_token);
      bool isExisted=false;
      for(uint i=0;i<tokenList[_token].length;i++){
        if(tokenList[_token][i].owner==_owner && tokenList[_token][i].endDateTime==_endDateTime){
          if(tokenList[_token][i].amount==0){
            tokenList[_token][i].startDateTime=block.timestamp;
          }
          tokenList[_token][i].amount=tokenList[_token][i].amount.add(_amount);
          isExisted=true;
          break;
        }
      }
      if(!isExisted){
        tokenList[_token].push(TokenList({
          amount:_amount,
          startDateTime:block.timestamp,
          endDateTime:_endDateTime,
          owner:_owner,
          creator:msg.sender
        }));
      }      
    }
    emit LockAdded(_token, _endDateTime, _amount, _owner, _isLiquidity, msg.sender, block.timestamp);
  }
  function unlockLiquidity(address _token) external override returns (bool){
    bool isExisted=false;
    uint256 _amount;
    for(uint i=0;i<liquidityList[_token].length;i++){
      if(liquidityList[_token][i].owner==msg.sender && liquidityList[_token][i].endDateTime<block.timestamp && liquidityList[_token][i].amount>0){
        isExisted=true;
        _amount=liquidityList[_token][i].amount;
        liquidityList[_token][i].amount=0;
        IPancakePair(_token).transferFrom(address(this), msg.sender, _amount);        
        emit UnlockLiquidity(_token, liquidityList[_token][i].endDateTime, _amount, liquidityList[_token][i].owner);
      }
    }
    require(isExisted==true, "no existed");
    
    return isExisted;
  }
  function unlockToken(address _token) external override returns (bool){
    bool isExisted=false;
    for(uint i=0;i<tokenList[_token].length;i++){
      if(tokenList[_token][i].owner==msg.sender && tokenList[_token][i].endDateTime<block.timestamp && tokenList[_token][i].amount>0){
        isExisted=true;
        uint256 _amount=tokenList[_token][i].amount;
        tokenList[_token][i].amount=0;
        IERC20Metadata(_token).transferFrom(address(this), msg.sender, _amount);        
        emit UnlockToken(_token, tokenList[_token][i].endDateTime, _amount, tokenList[_token][i].owner);
      }
    }
    require(isExisted==true, "no existed");
    return isExisted;
  }


}