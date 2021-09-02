// SPDX-License-Identifier: MIT
pragma solidity ^0.7.4;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@chainlink/contracts/src/v0.7/VRFConsumerBase.sol";
import "../library/Governance.sol";
import "../interface/INftAsset.sol";
import "./SantaV2.sol";

contract SantaFactoryV2 is Governance, VRFConsumerBase, IERC721Receiver {
    using Address for address;
    using SafeMath for uint256;
    struct SantaV2Data {
        uint256 id;
        uint256 face_value;
        uint256 createdTime;
    }
    event SantaV2NFTAdded(
        uint256 indexed id,
        address author,
        uint256 face_value
    );
    uint256 public _stakingPowaBase = 10000;
    // for minters
    mapping(address => bool) public _minters;
    mapping(address => bool) public _claimMembers;
    mapping(uint256 => SantaV2Data) public _santas;

    uint256 _maxNftCount = 0;
    ERC20 _cifiTokenContract = ERC20(0x0);
    SantaV2 public _santa = SantaV2(0x0);

    uint256 _linkFee = 0;
    bytes32 _linkKeyHash = bytes32("");
    mapping(bytes32 => address) public requestIdToAddress;
    mapping(bytes32 => uint256) public requestIdToFaceValue;

    constructor(
        address cifi,
        uint256 maxNftCount,
        address vrfCoordinator,
        address linkToken,
        bytes32 linkKeyHash,
        uint256 linkFee
    ) VRFConsumerBase(vrfCoordinator, linkToken) {
        _cifiTokenContract = ERC20(cifi);
        _maxNftCount = maxNftCount;
        _santa = new SantaV2(
            "Citien Finance",
            "sNFT2",
            "https://api.santafeapp.io/test-asset/"
        );
        _linkFee = linkFee;
        _linkKeyHash = linkKeyHash;
    }

    /**
     * @dev for set min burn time
     */

    function addMinter(address minter) public onlyGovernance {
        _minters[minter] = true;
    }

    function removeMinter(address minter) public onlyGovernance {
        _minters[minter] = false;
    }

    function getFaceValue(uint256 tokenId) public view returns (uint256) {
        SantaV2Data memory santa_data = _santas[tokenId];
        return santa_data.face_value;
    }

    /**
     * @dev set cifi contract address
     */
    function setCifiContract(address cifi) public onlyGovernance {
        _cifiTokenContract = ERC20(cifi);
    }

    function mint(uint256 face_value) public returns (bytes32) {
        require(face_value > 0, "face_value should be grater than 0!");
        require(
            _cifiTokenContract.allowance(msg.sender, address(this)) >=
                face_value,
            "Allownce is less than face_value!"
        );

        require(
            _cifiTokenContract.balanceOf(msg.sender) >= face_value,
            "Your balance is less than face value!"
        );

        require(
            LINK.balanceOf(address(this)) >= _linkFee,
            "Not enough LINK - fill contract with faucet"
        );
        require(
            _santa.totalSupply() < _maxNftCount,
            "Total tokens were already minted!"
        );
        _cifiTokenContract.transferFrom(msg.sender, address(this), face_value);
        bytes32 requestId = requestRandomness(_linkKeyHash, _linkFee);
        requestIdToAddress[requestId] = msg.sender;
        requestIdToFaceValue[requestId] = face_value;
        return requestId;
    }

    function fulfillRandomness(bytes32 requestId, uint256 randomness)
        internal
        override
    {
        require(
            _santa.totalSupply() < _maxNftCount,
            "Total tokens were already minted!"
        );
        address requestAddress = requestIdToAddress[requestId];
        uint256 nftID = (randomness % _maxNftCount) + 1;

        while (_santa.exists(nftID)) {
            nftID = ((nftID + 1) % _maxNftCount) + 1;
        }
        uint256 face_value = requestIdToFaceValue[requestId];

        _santa.mint(requestAddress, nftID);

        SantaV2Data memory santa_data;
        santa_data.id = nftID;
        santa_data.face_value = face_value;
        santa_data.createdTime = block.timestamp;
        _santas[nftID] = santa_data;
        emit SantaV2NFTAdded(nftID, requestAddress, face_value);
    }

    function getClass(uint256 stakingPowa) public view returns (uint256) {
        if (stakingPowa < _stakingPowaBase.mul(500).div(1000)) {
            return 1;
        } else if (
            _stakingPowaBase.mul(500).div(1000) <= stakingPowa &&
            stakingPowa < _stakingPowaBase.mul(800).div(1000)
        ) {
            return 2;
        } else if (
            _stakingPowaBase.mul(800).div(1000) <= stakingPowa &&
            stakingPowa < _stakingPowaBase.mul(900).div(1000)
        ) {
            return 3;
        } else if (
            _stakingPowaBase.mul(900).div(1000) <= stakingPowa &&
            stakingPowa < _stakingPowaBase.mul(980).div(1000)
        ) {
            return 4;
        } else if (
            _stakingPowaBase.mul(980).div(1000) <= stakingPowa &&
            stakingPowa < _stakingPowaBase.mul(998).div(1000)
        ) {
            return 5;
        } else {
            return 6;
        }
    }

    function retrieveToken(uint256 tokenId) external returns (bool) {
        SantaV2Data memory santa_data = _santas[tokenId];
        require(santa_data.id > 0, "SantaFactoryV2: not exist");
        require(
            _santa.ownerOf(tokenId) == msg.sender,
            "SantaFactoryV2: Invalid owner"
        );
        if (santa_data.face_value >= 0) {
            _cifiTokenContract.transfer(
                _santa.ownerOf(tokenId),
                santa_data.face_value
            );
            santa_data.face_value = 0;
            _santas[tokenId] = santa_data;
        }
    }

    function burn(uint256 tokenId) external returns (bool) {
        SantaV2Data memory santa_data = _santas[tokenId];
        require(santa_data.id > 0, "not exist");

        _santa.safeTransferFrom(msg.sender, address(this), tokenId);
        if (santa_data.face_value >= 0) {
            _cifiTokenContract.transfer(
                _santa.ownerOf(tokenId),
                santa_data.face_value
            );
        }
        _santa.burn(tokenId);
        delete _santas[tokenId];
        return true;
    }

    function onERC721Received(
        address,
        address,
        uint256,
        bytes memory
    ) public virtual override returns (bytes4) {
        return this.onERC721Received.selector;
    }
}