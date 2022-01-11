// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface AggregatorV3Interface {

    /*
  function decimals()
    external
    view
    returns (
      uint8
    );

  function description()
    external
    view
    returns (
      string memory
    );

  function version()
    external
    view
    returns (
      uint256
    );

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(
    uint80 _roundId
  )
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
    */

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

interface IMcpNFT is IERC721 {

    function mint(
                  address to,
                  uint8 top,
                  uint8 bottom,
                  uint8 left,
                  uint8 right,
                  string calldata URI
                  ) external returns (uint256 size);

    function update(uint256 tokenId, string calldata URI) external;

    function release() external;

    function getAvailable() external returns (uint256);

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Address.sol";

import "./IMcpNFT.sol";

contract McpNFT is ERC721, IMcpNFT {
    using Strings for uint256;
    using Address for address payable;

    bool private _released;

    uint256 private _nextTokenId;

    uint256 private _available;

    address private _platform;

    // from 0 to 99 block id
    struct Zone {
        uint256 created;
        uint8 left;
        uint8 right;
        uint8 top;
        uint8 bottom;
        string URI;
    }

    // tokenId => zones
    mapping (uint256 => Zone) private _zone;

    // canvasId (x, y) => 0 = clear, 1 = border, 2=top
    mapping (uint8 => mapping (uint8 => uint8)) private _canvas;

    constructor(address platform) ERC721("MCP NFT", "MCP") {
        _platform = platform;
        _nextTokenId = 1; // tokenId 0 is not used (was whole canvas)
        _released = false;
        _available = 100 * 100; // number of 10x10 pixels blocs available
    }

    modifier onlyPlatform() {
        require(_platform == _msgSender(), "caller is not the platform");
        _;
    }

    event PixelZone(
                uint256 tokenId,
                uint8 left,
                uint8 right,
                uint8 top,
                uint8 bottom,
                string URI
                );

    function mint(
                  address to,
                  uint8 left,
                  uint8 right,
                  uint8 top,
                  uint8 bottom,
                  string calldata URI
                  ) external override onlyPlatform()
        returns (uint256)
    {
        require (!_released, 'mint has ended');
        require (left <= right && top <= bottom, 'invalid parameters');
        require (right <= 99 && bottom <= 99, 'outbound parameters');

        if (top > 0) {
            for (uint8 y = top - 1; y >= 0; y--) {
                if (_canvas[left][y] == 1) break;
                require (_canvas[left][y] == 0, 'not available');
                if (y == 0) break;
            }
        }

        for (uint8 x = left; x <= right; x++) {
            require (_canvas[x][top] == 0, 'not available');
            _canvas[x][top] = bottom - top + 1;
            if (bottom > top) {
                require (_canvas[x][bottom] == 0, 'not available');
                _canvas[x][bottom] = 1;
            }
        }

        if (bottom > top) {
            for (uint8 y = top+1; y <= bottom-1; y++) {
                require (_canvas[left][y] == 0, 'not available');
                _canvas[left][y] = 1;
                if (right > left) {
                    for (uint8 x = left+1; x < right; x+=1) {
                        require (_canvas[x][y] == 0, 'not available');
                    }
                    require (_canvas[right][y] == 0, 'not available');
                    _canvas[right][y] = 1;
                }
            }
        }

        uint256 size = uint256(right - left + 1) * uint256(bottom - top + 1);
        _available -= size;

        _zone[_nextTokenId] = Zone({
            created: block.timestamp,
            left: left,
            right: right,
            top: top,
            bottom: bottom,
            URI: URI
        });

        emit PixelZone(_nextTokenId, left, right, top,  bottom, URI);

        _mint(to, _nextTokenId);
        _nextTokenId++;

        return size;
    }

    function update(uint256 tokenId, string calldata URI) external override onlyPlatform() {
        require(block.timestamp < _zone[tokenId].created + 1 days, 'too late');

        _zone[tokenId].URI = URI;

        emit PixelZone(
                       tokenId,
                       _zone[tokenId].left,
                       _zone[tokenId].right,
                       _zone[tokenId].top,
                       _zone[tokenId].bottom,
                       URI
                       );
    }

    function release() external override onlyPlatform() {
        _zone[1].created = block.timestamp;
        _released = true;
    }

    function getAvailable() external view virtual override returns (uint256) {
        return _available;
    }

    // override ERC721 standard not to authorize transfer before release
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual override returns (bool) {
        return _released && super._isApprovedOrOwner(spender, tokenId);
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

import "./AggregatorV3Interface.sol";
import "./IMcpNFT.sol";

contract McpPlatform is Ownable {
    using Address for address payable;

    AggregatorV3Interface internal priceFeed;

    address private _erc721;

    uint256 private _usdBlockPrice; // 8 decimals

    constructor (address aggregator) {
        priceFeed = AggregatorV3Interface(aggregator);
        _usdBlockPrice = 100000000 * 100; // by default 100$ per block = 1$ per pixel
    }

    function withdraw() external onlyOwner() {
        payable(owner()).sendValue(address(this).balance);
    }

    function release() external onlyOwner() {
        IMcpNFT(_erc721).release();
    }

    function setNFT(address erc721) external onlyOwner() {
        _erc721 = erc721;

        // tokenId 1 is the central zone 200*200 pixels
        // change ipfs for new network ...

        IMcpNFT(_erc721).mint(
                              _msgSender(),
                              40,
                              59,
                              40,
                              59,
                              'ipfs://QmVZkvkQGY3tSER8fy9YXiNC7KnYZyHCvsU6FXcQcpM8iY'
                              );
        /*        */
    }

    function setUsdBlockPrice(uint256 price) external onlyOwner() {
        _usdBlockPrice = price;
    }

    function ethPrice(uint256 usdPrice) public view returns (uint256) {
        ( , int price, , , ) = priceFeed.latestRoundData();
        return usdPrice * 10**18 / uint256(price);
    }

    function getPrice(
                  uint8 left,
                  uint8 right,
                  uint8 top,
                  uint8 bottom) external view returns (uint256) {

        uint256 size = uint256(right - left + 1) * uint256(bottom - top + 1);

        return ethPrice(_usdBlockPrice * size);
    }

    function mint(
                  uint8 left,
                  uint8 right,
                  uint8 top,
                  uint8 bottom,
                  string memory URI) payable external {

        uint256 size = IMcpNFT(_erc721).mint(
                                             _msgSender(),
                                             left,
                                             right,
                                             top,
                                             bottom,
                                             URI
                                             );

        require(msg.value >= ethPrice(_usdBlockPrice * size), 'price not reached');
    }

    function update(uint256 tokenId, string memory URI) payable external {
        require(IMcpNFT(_erc721).ownerOf(tokenId) == _msgSender(), 'not owner');

        IMcpNFT(_erc721).update(tokenId, URI);
    }


}
// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

contract Migrations {
  address public owner = msg.sender;
  uint public last_completed_migration;

  modifier restricted() {
    require(
      msg.sender == owner,
      "This function is restricted to the contract's owner"
    );
    _;
  }

  function setCompleted(uint completed) public restricted {
    last_completed_migration = completed;
  }
}
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

contract MockAggregator {

    function latestRoundData()
        external
        pure
        returns (
                 uint80,  // roundId
                 int256,  // answer
                 uint256, // startedAt - Timestamp of when the round started.
                 uint256, // updatedAt - Timestamp of when the round was updated.
                 uint80   // answeredInRound - The round ID of the round in which the answer was computed.
                 ) {
        return (
                92233720368547765673,
                228092615813,
                1627480590,
                1627480590,
                92233720368547765673
                );

    }

}

