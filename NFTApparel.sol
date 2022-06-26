// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract ApparelAddressRegistry is Ownable {
    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;

    /// @notice Auction contract
    address public auction;

    /// @notice Marketplace contract
    address public marketplace;

    /// @notice NFTFactory contract
    address public factory;

    /// @notice TokenRegistry contract
    address public tokenRegistry;

    /// @notice PriceFeed contract
    address public priceFeed;

    /**
     @notice Update Marketplace contract
     @dev Only admin
     */
    function updateMarketplace(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    /**
     @notice Update Auction contract
     @dev Only admin
     */
    function updateAuction(address _auction) external onlyOwner {
        auction = _auction;
    }

    /**
     @notice Update NFTFactory contract
     @dev Only admin
     */
    function updateNFTFactory(address _factory) external onlyOwner {
        factory = _factory;
    }

    /**
     @notice Update token registry contract
     @dev Only admin
     */
    function updateTokenRegistry(address _tokenRegistry) external onlyOwner {
        tokenRegistry = _tokenRegistry;
    }

    /**
     @notice Update price feed contract
     @dev Only admin
     */
    function updatePriceFeed(address _priceFeed) external onlyOwner {
        priceFeed = _priceFeed;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

interface IApparelAddressRegistry {
    function auction() external view returns (address);

    function marketplace() external view returns (address);

    function tokenRegistry() external view returns (address);
}

interface IApparelMarketplace {
    function minters(address, uint256) external view returns (address);

    function royalties(address, uint256) external view returns (uint16);

    function collectionRoyalties(address)
        external
        view
        returns (
            uint16,
            address,
            address
        );

    function getPrice(address) external view returns (int256);
}

interface IApparelTokenRegistry {
    function enabled(address) external returns (bool);
}

/**
 * @notice Secondary sale auction contract for NFTs
 */
contract ApparelAuction is OwnableUpgradeable, ReentrancyGuardUpgradeable {
    using AddressUpgradeable for address;

    /// @notice Event emitted only on construction. To be used by indexers
    event ApparelAuctionContractDeployed();

    event PauseToggled(bool isPaused);

    event AuctionCreated(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address payToken
    );

    event UpdateAuctionEndTime(
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 endTime
    );

    event UpdateAuctionStartTime(
        address indexed nftAddress,
        uint256 indexed tokenId,
        uint256 startTime
    );

    event UpdateAuctionReservePrice(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address payToken,
        uint256 reservePrice
    );

    event UpdatePlatformFee(uint256 platformFee);

    event UpdatePlatformFeeRecipient(address payable platformFeeRecipient);

    event UpdateMinBidIncrement(uint256 minBidIncrement);

    event UpdateBidWithdrawalLockTime(uint256 bidWithdrawalLockTime);

    event BidPlaced(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event BidWithdrawn(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event BidRefunded(
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed bidder,
        uint256 bid
    );

    event AuctionResulted(
        address oldOwner,
        address indexed nftAddress,
        uint256 indexed tokenId,
        address indexed winner,
        address payToken,
        int256 unitPrice,
        uint256 winningBid
    );

    event AuctionCancelled(address indexed nftAddress, uint256 indexed tokenId);

    /// @notice Parameters of an auction
    struct Auction {
        address owner;
        address payToken;
        uint256 minBid;
        uint256 reservePrice;
        uint256 startTime;
        uint256 endTime;
        bool resulted;
    }

    /// @notice Information about the sender that placed a bit on an auction
    struct HighestBid {
        address payable bidder;
        uint256 bid;
        uint256 lastBidTime;
    }

    /// @notice ERC721 Address -> Token ID -> Auction Parameters
    mapping(address => mapping(uint256 => Auction)) public auctions;

    /// @notice ERC721 Address -> Token ID -> highest bidder info (if a bid has been received)
    mapping(address => mapping(uint256 => HighestBid)) public highestBids;

    /// @notice globally and across all auctions, the amount by which a bid has to increase
    uint256 public minBidIncrement;

    /// @notice global bid withdrawal lock time
    uint256 public bidWithdrawalLockTime;

    /// @notice global platform fee, assumed to always be to 1 decimal place i.e. 25 = 2.5%
    uint256 public platformFee;

    /// @notice where to send platform fee funds to
    address payable public platformFeeRecipient;

    /// @notice Address registry
    IApparelAddressRegistry public addressRegistry;

    /// @notice for switching off auction creations, bids and withdrawals
    bool public isPaused;

    modifier whenNotPaused() {
        require(!isPaused, "contract paused");
        _;
    }

    modifier onlyMarketplace() {
        require(
            addressRegistry.marketplace() == _msgSender(),
            "not marketplace contract"
        );
        _;
    }

    /// @notice Contract initializer
    function initialize(address payable _platformFeeRecipient)
        public
        initializer
    {
        require(
            _platformFeeRecipient != address(0),
            "ApparelAuction: Invalid Platform Fee Recipient"
        );

        platformFeeRecipient = _platformFeeRecipient;
        emit ApparelAuctionContractDeployed();

        minBidIncrement = 1;
        bidWithdrawalLockTime = 20 minutes;
        platformFee = 25;

        __Ownable_init();
        __ReentrancyGuard_init();
    }

    /**
     @notice Creates a new auction for a given item
     @dev Only the owner of item can create an auction and must have approved the contract
     @dev In addition to owning the item, the sender also has to have the MINTER role.
     @dev End time for the auction must be in the future.
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _payToken Paying token
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     */
    function createAuction(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _reservePrice,
        uint256 _startTimestamp,
        bool minBidReserve,
        uint256 _endTimestamp
    ) external whenNotPaused {
        // Ensure this contract is approved to move the token
        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                IERC721(_nftAddress).isApprovedForAll(
                    _msgSender(),
                    address(this)
                ),
            "not owner and or contract not approved"
        );

        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    IApparelTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );

        _createAuction(
            _nftAddress,
            _tokenId,
            _payToken,
            _reservePrice,
            _startTimestamp,
            minBidReserve,
            _endTimestamp
        );
    }

    /**
     @notice Places a new bid, out bidding the existing bidder if found and criteria is reached
     @dev Only callable when the auction is open
     @dev Bids from smart contracts are prohibited to prevent griefing with always reverting receiver
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     @param _bidAmount Bid amount
     */
    function placeBid(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _bidAmount
    ) external nonReentrant whenNotPaused {
        require(_msgSender().isContract() == false, "no contracts permitted");

        // Check the auction to see if this is a valid bid
        Auction memory auction = auctions[_nftAddress][_tokenId];

        // Ensure auction is in flight
        require(
            _getNow() >= auction.startTime && _getNow() <= auction.endTime,
            "bidding outside of the auction window"
        );
        require(
            auction.payToken != address(0),
            "ERC20 method used for FTM auction"
        );

        _placeBid(_nftAddress, _tokenId, _bidAmount);
    }

    function _placeBid(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _bidAmount
    ) internal whenNotPaused {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        if (auction.minBid == auction.reservePrice) {
            require(
                _bidAmount >= auction.reservePrice,
                "bid cannot be lower than reserve price"
            );
        }

        // Ensure bid adheres to outbid increment and threshold
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        uint256 minBidRequired = highestBid.bid + minBidIncrement;

        require(_bidAmount >= minBidRequired, "failed to outbid highest bidder");

        if (auction.payToken != address(0)) {
            IERC20 payToken = IERC20(auction.payToken);
            require(
                payToken.transferFrom(_msgSender(), address(this), _bidAmount),
                "insufficient balance or not approved"
            );
        }

        // Refund existing top bidder if found
        if (highestBid.bidder != address(0)) {
            _refundHighestBidder(
                _nftAddress,
                _tokenId,
                highestBid.bidder,
                highestBid.bid
            );
        }

        // assign top bidder and bid time
        highestBid.bidder = payable(_msgSender());
        highestBid.bid = _bidAmount;
        highestBid.lastBidTime = _getNow();

        emit BidPlaced(_nftAddress, _tokenId, _msgSender(), _bidAmount);
    }

    /**
     @notice Allows the hightest bidder to withdraw the bid (after 12 hours post auction's end) 
     @dev Only callable by the existing top bidder
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function withdrawBid(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
        whenNotPaused
    {
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];

        // Ensure highest bidder is the caller
        require(
            highestBid.bidder == _msgSender(),
            "you are not the highest bidder"
        );

        uint256 _endTime = auctions[_nftAddress][_tokenId].endTime;

        require(
            _getNow() > _endTime && (_getNow() - _endTime >= 43200),
            "can withdraw only after 12 hours (after auction ended)"
        );

        uint256 previousBid = highestBid.bid;

        // Clean up the existing top bid
        delete highestBids[_nftAddress][_tokenId];

        // Refund the top bidder
        _refundHighestBidder(_nftAddress, _tokenId, payable(_msgSender()), previousBid);

        emit BidWithdrawn(_nftAddress, _tokenId, _msgSender(), previousBid);
    }

    //////////
    // Admin /
    //////////

    /**
     @notice Closes a finished auction and rewards the highest bidder
     @dev Only admin or smart contract
     @dev Auction can only be resulted if there has been a bidder and reserve met.
     @dev If there have been no bids, the auction needs to be cancelled instead using `cancelAuction()`
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the item being auctioned
     */
    function resultAuction(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        // Check the auction to see if it can be resulted
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                _msgSender() == auction.owner,
            "sender must be item owner"
        );

        // Check the auction real
        require(auction.endTime > 0, "no auction exists");

        // Check the auction has ended
        require(_getNow() > auction.endTime, "auction not ended");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        // Get info on who the highest bidder is
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        address winner = highestBid.bidder;
        uint256 winningBid = highestBid.bid;

        // Ensure there is a winner
        require(winner != address(0), "no open bids");
        require(
            winningBid >= auction.reservePrice,
            "highest bid is below reservePrice"
        );

        // Ensure this contract is approved to move the token
        require(
            IERC721(_nftAddress).isApprovedForAll(_msgSender(), address(this)),
            "auction not approved"
        );

        // Result the auction
        auction.resulted = true;

        // Clean up the highest bid
        delete highestBids[_nftAddress][_tokenId];

        uint256 payAmount;

        if (winningBid > auction.reservePrice) {
            // Work out total above the reserve
            uint256 aboveReservePrice = winningBid - auction.reservePrice;

            // Work out platform fee from above reserve amount
            uint256 platformFeeAboveReserve = aboveReservePrice *platformFee / 1000;

            if (auction.payToken == address(0)) {
                // Send platform fee
                (bool platformTransferSuccess, ) = platformFeeRecipient.call{
                    value: platformFeeAboveReserve
                }("");
                require(platformTransferSuccess, "failed to send platform fee");
            } else {
                IERC20 payToken = IERC20(auction.payToken);
                require(
                    payToken.transfer(
                        platformFeeRecipient,
                        platformFeeAboveReserve
                    ),
                    "failed to send platform fee"
                );
            }

            // Send remaining to designer
            payAmount = winningBid - platformFeeAboveReserve;
        } else {
            payAmount = winningBid;
        }

        IApparelMarketplace marketplace = IApparelMarketplace(
            addressRegistry.marketplace()
        );
        address minter = marketplace.minters(_nftAddress, _tokenId);
        uint16 royalty = marketplace.royalties(_nftAddress, _tokenId);
        if (minter != address(0) && royalty != 0) {
            uint256 royaltyFee = payAmount * royalty / 10000;
            if (auction.payToken == address(0)) {
                (bool royaltyTransferSuccess, ) = payable(minter).call{
                    value: royaltyFee
                }("");
                require(
                    royaltyTransferSuccess,
                    "failed to send the owner their royalties"
                );
            } else {
                IERC20 payToken = IERC20(auction.payToken);
                require(
                    payToken.transfer(minter, royaltyFee),
                    "failed to send the owner their royalties"
                );
            }
            payAmount = payAmount - royaltyFee;
        } else {
            (royalty, , minter) = marketplace.collectionRoyalties(_nftAddress);
            if (minter != address(0) && royalty != 0) {
                uint256 royaltyFee = payAmount * royalty / 10000;
                if (auction.payToken == address(0)) {
                    (bool royaltyTransferSuccess, ) = payable(minter).call{
                        value: royaltyFee
                    }("");
                    require(
                        royaltyTransferSuccess,
                        "failed to send the royalties"
                    );
                } else {
                    IERC20 payToken = IERC20(auction.payToken);
                    require(
                        payToken.transfer(minter, royaltyFee),
                        "failed to send the royalties"
                    );
                }
                payAmount = payAmount - royaltyFee;
            }
        }
        if (payAmount > 0) {
            if (auction.payToken == address(0)) {
                (bool ownerTransferSuccess, ) = auction.owner.call{
                    value: payAmount
                }("");
                require(
                    ownerTransferSuccess,
                    "failed to send the owner the auction balance"
                );
            } else {
                IERC20 payToken = IERC20(auction.payToken);
                require(
                    payToken.transfer(auction.owner, payAmount),
                    "failed to send the owner the auction balance"
                );
            }
        }

        // Transfer the token to the winner
        IERC721(_nftAddress).transferFrom(
            IERC721(_nftAddress).ownerOf(_tokenId),
            winner,
            _tokenId
        );

        emit AuctionResulted(
            _msgSender(),
            _nftAddress,
            _tokenId,
            winner,
            auction.payToken,
            IApparelMarketplace(addressRegistry.marketplace()).getPrice(
                auction.payToken
            ),
            winningBid
        );

        // Remove auction
        delete auctions[_nftAddress][_tokenId];
    }

    /**
     @notice Cancels and inflight and un-resulted auctions, returning the funds to the top bidder if found
     @dev Only item owner
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function cancelAuction(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
    {
        // Check valid and not resulted
        Auction memory auction = auctions[_nftAddress][_tokenId];

        require(
            IERC721(_nftAddress).ownerOf(_tokenId) == _msgSender() &&
                _msgSender() == auction.owner,
            "sender must be owner"
        );
        // Check auction is real
        require(auction.endTime > 0, "no auction exists");
        // Check auction not already resulted
        require(!auction.resulted, "auction already resulted");

        _cancelAuction(_nftAddress, _tokenId);
    }

    /**
     @notice Toggling the pause flag
     @dev Only admin
     */
    function toggleIsPaused() external onlyOwner {
        isPaused = !isPaused;
        emit PauseToggled(isPaused);
    }

    /**
     @notice Update the amount by which bids have to increase, across all auctions
     @dev Only admin
     @param _minBidIncrement New bid step in WEI
     */
    function updateMinBidIncrement(uint256 _minBidIncrement)
        external
        onlyOwner
    {
        minBidIncrement = _minBidIncrement;
        emit UpdateMinBidIncrement(_minBidIncrement);
    }

    /**
     @notice Update the global bid withdrawal lockout time
     @dev Only admin
     @param _bidWithdrawalLockTime New bid withdrawal lock time
     */
    function updateBidWithdrawalLockTime(uint256 _bidWithdrawalLockTime)
        external
        onlyOwner
    {
        bidWithdrawalLockTime = _bidWithdrawalLockTime;
        emit UpdateBidWithdrawalLockTime(_bidWithdrawalLockTime);
    }

    /**
     @notice Update the current reserve price for an auction
     @dev Only admin
     @dev Auction must exist
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _reservePrice New Ether reserve price (WEI value)
     */
    function updateAuctionReservePrice(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _reservePrice
    ) external {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(_msgSender() == auction.owner, "sender must be item owner");

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        require(auction.endTime > 0, "no auction exists");

        auction.reservePrice = _reservePrice;
        emit UpdateAuctionReservePrice(
            _nftAddress,
            _tokenId,
            auction.payToken,
            _reservePrice
        );
    }

    /**
     @notice Update the current start time for an auction
     @dev Only admin
     @dev Auction must exist
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _startTime New start time (unix epoch in seconds)
     */
    function updateAuctionStartTime(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _startTime
    ) external {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(_msgSender() == auction.owner, "sender must be owner");

        require(_startTime > 0, "invalid start time");

        require(auction.startTime + 60 > _getNow(), "auction already started");

        require(
            _startTime + 300 < auction.endTime,
            "start time should be less than end time (by 5 minutes)"
        );

        // Ensure auction not already resulted
        require(!auction.resulted, "auction already resulted");

        require(auction.endTime > 0, "no auction exists");

        auction.startTime = _startTime;
        emit UpdateAuctionStartTime(_nftAddress, _tokenId, _startTime);
    }

    /**
     @notice Update the current end time for an auction
     @dev Only admin
     @dev Auction must exist
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _endTimestamp New end time (unix epoch in seconds)
     */
    function updateAuctionEndTime(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _endTimestamp
    ) external {
        Auction storage auction = auctions[_nftAddress][_tokenId];

        require(_msgSender() == auction.owner, "sender must be owner");

        // Check the auction has not ended
        require(_getNow() < auction.endTime, "auction already ended");

        require(auction.endTime > 0, "no auction exists");
        require(
            auction.startTime < _endTimestamp,
            "end time must be greater than start"
        );
        require(
            _endTimestamp > _getNow() + 300,
            "auction should end after 5 minutes"
        );

        auction.endTime = _endTimestamp;
        emit UpdateAuctionEndTime(_nftAddress, _tokenId, _endTimestamp);
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint256 the platform fee to set
     */
    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _platformFeeRecipient payable address the address to sends the funds to
     */
    function updatePlatformFeeRecipient(address payable _platformFeeRecipient)
        external
        onlyOwner
    {
        require(_platformFeeRecipient != address(0), "zero address");

        platformFeeRecipient = _platformFeeRecipient;
        emit UpdatePlatformFeeRecipient(_platformFeeRecipient);
    }

    /**
     @notice Update ApparelAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = IApparelAddressRegistry(_registry);
    }

    ///////////////
    // Accessors //
    ///////////////

    /**
     @notice Method for getting all info about the auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getAuction(address _nftAddress, uint256 _tokenId)
        external
        view
        returns (
            address _owner,
            address _payToken,
            uint256 _reservePrice,
            uint256 _startTime,
            uint256 _endTime,
            bool _resulted,
            uint256 minBid
        )
    {
        Auction storage auction = auctions[_nftAddress][_tokenId];
        return (
            auction.owner,
            auction.payToken,
            auction.reservePrice,
            auction.startTime,
            auction.endTime,
            auction.resulted,
            auction.minBid
        );
    }

    /**
     @notice Method for getting all info about the highest bidder
     @param _tokenId Token ID of the NFT being auctioned
     */
    function getHighestBidder(address _nftAddress, uint256 _tokenId)
        external
        view
        returns (
            address payable _bidder,
            uint256 _bid,
            uint256 _lastBidTime
        )
    {
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        return (highestBid.bidder, highestBid.bid, highestBid.lastBidTime);
    }

    /////////////////////////
    // Internal and Private /
    /////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    /**
     @notice Private method doing the heavy lifting of creating an auction
     @param _nftAddress ERC 721 Address
     @param _tokenId Token ID of the NFT being auctioned
     @param _payToken Paying token
     @param _reservePrice Item cannot be sold for less than this or minBidIncrement, whichever is higher
     @param _startTimestamp Unix epoch in seconds for the auction start time
     @param _endTimestamp Unix epoch in seconds for the auction end time.
     */
    function _createAuction(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _reservePrice,
        uint256 _startTimestamp,
        bool minBidReserve,
        uint256 _endTimestamp
    ) private {
        // Ensure a token cannot be re-listed if previously successfully sold
        require(
            auctions[_nftAddress][_tokenId].endTime == 0,
            "auction already started"
        );

        // Check end time not before start time and that end is in the future
        require(
            _endTimestamp >= _startTimestamp + 300,
            "end time must be greater than start (by 5 minutes)"
        );

        require(_startTimestamp > _getNow(), "invalid start time");

        uint256 minimumBid = 0;

        if (minBidReserve) {
            minimumBid = _reservePrice;
        }

        // Setup the auction
        auctions[_nftAddress][_tokenId] = Auction({
            owner: _msgSender(),
            payToken: _payToken,
            minBid: minimumBid,
            reservePrice: _reservePrice,
            startTime: _startTimestamp,
            endTime: _endTimestamp,
            resulted: false
        });

        emit AuctionCreated(_nftAddress, _tokenId, _payToken);
    }

    function _cancelAuction(address _nftAddress, uint256 _tokenId) private {
        // refund existing top bidder if found
        HighestBid storage highestBid = highestBids[_nftAddress][_tokenId];
        if (highestBid.bidder != address(0)) {
            _refundHighestBidder(
                _nftAddress,
                _tokenId,
                highestBid.bidder,
                highestBid.bid
            );

            // Clear up highest bid
            delete highestBids[_nftAddress][_tokenId];
        }

        // Remove auction and top bidder
        delete auctions[_nftAddress][_tokenId];

        emit AuctionCancelled(_nftAddress, _tokenId);
    }

    /**
     @notice Used for sending back escrowed funds from a previous bid
     @param _currentHighestBidder Address of the last highest bidder
     @param _currentHighestBid Ether or Mona amount in WEI that the bidder sent when placing their bid
     */
    function _refundHighestBidder(
        address _nftAddress,
        uint256 _tokenId,
        address payable _currentHighestBidder,
        uint256 _currentHighestBid
    ) private {
        Auction memory auction = auctions[_nftAddress][_tokenId];
        if (auction.payToken == address(0)) {
            // refund previous best (if bid exists)
            (bool successRefund, ) = _currentHighestBidder.call{
                value: _currentHighestBid
            }("");
            require(successRefund, "failed to refund previous bidder");
        } else {
            IERC20 payToken = IERC20(auction.payToken);
            require(
                payToken.transfer(_currentHighestBidder, _currentHighestBid),
                "failed to refund previous bidder"
            );
        }
        emit BidRefunded(
            _nftAddress,
            _tokenId,
            _currentHighestBidder,
            _currentHighestBid
        );
    }

    /**
     * @notice Reclaims ERC20 Compatible tokens for entire balance
     * @dev Only access controls admin
     * @param _tokenContract The address of the token contract
     */
    function reclaimERC20(address _tokenContract) external onlyOwner {
        require(_tokenContract != address(0), "Invalid address");
        IERC20 token = IERC20(_tokenContract);
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(_msgSender(), balance), "Transfer failed");
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC1155/utils/ERC1155HolderUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/utils/ERC721HolderUpgradeable.sol";
import "./interfaces/IUniswapV2Router.sol";

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

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
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

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

    function burn(uint256 amount) external;
}

interface IApparelAuction {
    function auctions(address, uint256)
        external
        view
        returns (
            address,
            address,
            uint256,
            uint256,
            uint256,
            bool
        );
}

interface IApparelAddressRegistry {
    function factory() external view returns (address);

    function tokenRegistry() external view returns (address);

    function priceFeed() external view returns (address);

    function auction() external view returns (address);
}

interface IApparelNFTFactory {
    function exists(address) external view returns (bool);
}

interface IApparelTokenRegistry {
    function enabled(address) external view returns (bool);
}

interface IApparelPriceFeed {
    function wETH() external view returns (address);

    function getPrice(address) external view returns (int256, uint8);
}

contract ApparelMarketplace is OwnableUpgradeable, ReentrancyGuardUpgradeable, ERC1155HolderUpgradeable, ERC721HolderUpgradeable {
    using SafeMath for uint256;
    using AddressUpgradeable for address payable;

    /// @notice Events for the contract
    event ItemListed(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        uint256 pricePerItem,
        uint256 startingTime
    );
    event ItemSold(
        address indexed seller,
        address indexed buyer,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        int256 unitPrice,
        uint256 pricePerItem
    );
    event ItemUpdated(
        address indexed owner,
        address indexed nft,
        uint256 tokenId,
        address payToken,
        uint256 newPrice
    );
    event ItemCanceled(
        address indexed owner,
        address indexed nft,
        uint256 tokenId
    );
    event OfferCreated(
        address indexed creator,
        address indexed nft,
        uint256 tokenId,
        uint256 quantity,
        address payToken,
        uint256 pricePerItem,
        uint256 deadline
    );
    event OfferCanceled(
        address indexed creator,
        address indexed nft,
        uint256 tokenId
    );
    event UpdatePlatformFee(uint16 platformFee);
    event UpdateTreasuryAddress(address payable treasuryAddress);

    /// @notice Structure for listed items
    struct Listing {
        uint256 quantity;
        address payToken;
        uint256 pricePerItem;
        uint256 startingTime;
    }

    /// @notice Structure for offer
    struct Offer {
        IERC20 payToken;
        uint256 quantity;
        uint256 pricePerItem;
        uint256 deadline;
    }

    struct CollectionRoyalty {
        uint16 royalty;
        address creator;
        address feeRecipient;
    }

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    bytes4 private constant INTERFACE_ID_ERC1155 = 0xd9b67a26;

    /// @notice NftAddress -> Token ID -> Minter
    mapping(address => mapping(uint256 => address)) public minters;

    /// @notice NftAddress -> Token ID -> Royalty
    mapping(address => mapping(uint256 => uint16)) public royalties;

    /// @notice NftAddress -> Token ID -> Owner -> Listing item
    mapping(address => mapping(uint256 => mapping(address => Listing)))
        public listings;

    /// @notice NftAddress -> Token ID -> Offerer -> Offer
    mapping(address => mapping(uint256 => mapping(address => Offer)))
        public offers;

    /// @notice Platform fee
    uint16 public platformFee;

    /// @notice Platform fee receipient
    address payable public treasuryWallet;

    /// @notice Peak Address
    address public peakAddress;

    /// @notice Peak Address
    address public proAddress;

    /// @notice Netswap Router Address
    IUniswapV2Router public uniswapV2Router;

    /// @notice NftAddress -> Royalty
    mapping(address => CollectionRoyalty) public collectionRoyalties;

    /// @notice Address registry
    IApparelAddressRegistry public addressRegistry;

    modifier isListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity > 0, "not listed item");
        _;
    }

    modifier notListed(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listing = listings[_nftAddress][_tokenId][_owner];
        require(listing.quantity == 0, "already listed");
        _;
    }

    modifier validListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];

        _validOwner(_nftAddress, _tokenId, address(this), listedItem.quantity);

        require(_getNow() >= listedItem.startingTime, "item not buyable");
        _;
    }

    modifier offerExists(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) {
        Offer memory offer = offers[_nftAddress][_tokenId][_creator];
        require(
            offer.quantity > 0 && offer.deadline > _getNow(),
            "offer not exists or expired"
        );
        _;
    }

    modifier offerNotExists(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) {
        Offer memory offer = offers[_nftAddress][_tokenId][_creator];
        require(
            offer.quantity == 0 || offer.deadline <= _getNow(),
            "offer already created"
        );
        _;
    }

    function initialize(address _treasury, uint16 _platformFee, address _peak, address _pro, address _router) public initializer {
        __Ownable_init_unchained();
        __ReentrancyGuard_init_unchained();
        __ERC1155Holder_init_unchained();
        __ERC721Holder_init_unchained();
        __ApparelMarketplace_init_unchained(payable(_treasury), _platformFee, _peak, _pro, _router);
    }

    function __ApparelMarketplace_init_unchained(address payable _treasury, uint16 _platformFee, address _peak, address _pro, address _router) internal onlyInitializing {
        platformFee = _platformFee;
        treasuryWallet = _treasury;
        peakAddress = _peak;
        proAddress = _pro;
        uniswapV2Router = IUniswapV2Router(_router);
    }

    /// @notice Method for listing NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _quantity token amount to list (needed for ERC-1155 NFTs, set as 1 for ERC-721)
    /// @param _payToken Paying token
    /// @param _pricePerItem sale price for each iteam
    /// @param _startingTime scheduling for a future sale
    function listItem(
        address _nftAddress,
        uint256 _tokenId,
        uint256 _quantity,
        address _payToken,
        uint256 _pricePerItem,
        uint256 _startingTime
    ) external notListed(_nftAddress, _tokenId, _msgSender()) {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _msgSender(), "not owning item");
            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );
            nft.safeTransferFrom(_msgSender(), address(this), _tokenId);
        } else if (
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)
        ) {
            IERC1155 nft = IERC1155(_nftAddress);
            require(
                nft.balanceOf(_msgSender(), _tokenId) >= _quantity,
                "must hold enough nfts"
            );
            require(
                nft.isApprovedForAll(_msgSender(), address(this)),
                "item not approved"
            );
            nft.safeTransferFrom(
                _msgSender(),
                address(this),
                _tokenId,
                _quantity,
                bytes("")
            );
        } else {
            revert("invalid nft address");
        }

        _validPayToken(_payToken);

        listings[_nftAddress][_tokenId][_msgSender()] = Listing(
            _quantity,
            _payToken,
            _pricePerItem,
            _startingTime
        );
        emit ItemListed(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _quantity,
            _payToken,
            _pricePerItem,
            _startingTime
        );
    }

    /// @notice Method for canceling listed NFT
    function cancelListing(address _nftAddress, uint256 _tokenId)
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _msgSender())
    {
        _cancelListing(_nftAddress, _tokenId, _msgSender());
    }

    /// @notice Method for updating listed NFT
    /// @param _nftAddress Address of NFT contract
    /// @param _tokenId Token ID of NFT
    /// @param _payToken payment token
    /// @param _newPrice New sale price for each iteam
    function updateListing(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        uint256 _newPrice
    ) external nonReentrant isListed(_nftAddress, _tokenId, _msgSender()) {
        Listing storage listedItem = listings[_nftAddress][_tokenId][
            _msgSender()
        ];

        _validOwner(_nftAddress, _tokenId, address(this), listedItem.quantity);

        _validPayToken(_payToken);

        listedItem.payToken = _payToken;
        listedItem.pricePerItem = _newPrice;
        emit ItemUpdated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _payToken,
            _newPrice
        );
    }

    function buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        address _owner
    )
        external
        nonReentrant
        isListed(_nftAddress, _tokenId, _owner)
        validListing(_nftAddress, _tokenId, _owner)
    {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];
        require(listedItem.payToken == _payToken, "invalid pay token");

        _buyItem(_nftAddress, _tokenId, _payToken, _owner);
    }

    /// @notice Method for buying listed NFT
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    function _buyItem(
        address _nftAddress,
        uint256 _tokenId,
        address _payToken,
        address _owner
    ) private {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];

        uint256 price = listedItem.pricePerItem.mul(listedItem.quantity);
        uint256 feeAmount = price.mul(platformFee).div(1e3);

        if(address(_payToken) == peakAddress) {
            uint256 burnAmt = feeAmount.div(2);
            uint256 treasuryAmt = feeAmount.sub(burnAmt);
            IERC20(_payToken).transferFrom(
                _msgSender(),
                address(this),
                feeAmount
            );
            IERC20(_payToken).transfer(treasuryWallet, treasuryAmt);
            IERC20(_payToken).burn(burnAmt);
        } else if(address(_payToken) == uniswapV2Router.Metis()) {
            uint256 buybackAmt = feeAmount.div(4);
            uint256 treasuryAmt = feeAmount.sub(buybackAmt);
            IERC20(_payToken).transferFrom(
                _msgSender(),
                address(this),
                feeAmount
            );
            IERC20(_payToken).transfer(treasuryWallet, treasuryAmt);
            // BuyBack PRO Tokens
            swapTokensForTokens(buybackAmt);
            uint256 proAmt = IERC20(proAddress).balanceOf(address(this));
            IERC20(proAddress).transfer(treasuryWallet, proAmt);
        } else {
            IERC20(_payToken).transferFrom(
                _msgSender(),
                treasuryWallet,
                feeAmount
            );
        }

        address minter = minters[_nftAddress][_tokenId];
        uint16 royalty = royalties[_nftAddress][_tokenId];
        if (minter != address(0) && royalty != 0) {
            uint256 royaltyFee = price.sub(feeAmount).mul(royalty).div(10000);

            IERC20(_payToken).transferFrom(
                _msgSender(),
                minter,
                royaltyFee
            );

            feeAmount = feeAmount.add(royaltyFee);
        } else {
            minter = collectionRoyalties[_nftAddress].feeRecipient;
            royalty = collectionRoyalties[_nftAddress].royalty;
            if (minter != address(0) && royalty != 0) {
                uint256 royaltyFee = price.sub(feeAmount).mul(royalty).div(
                    10000
                );

                IERC20(_payToken).transferFrom(
                    _msgSender(),
                    minter,
                    royaltyFee
                );

                feeAmount = feeAmount.add(royaltyFee);
            }
        }

        IERC20(_payToken).transferFrom(
            _msgSender(),
            _owner,
            price.sub(feeAmount)
        );

        // Transfer NFT to buyer
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(_nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                _tokenId
            );
        } else {
            IERC1155(_nftAddress).safeTransferFrom(
                address(this),
                _msgSender(),
                _tokenId,
                listedItem.quantity,
                bytes("")
            );
        }

        emit ItemSold(
            _owner,
            _msgSender(),
            _nftAddress,
            _tokenId,
            listedItem.quantity,
            _payToken,
            getPrice(_payToken),
            price.div(listedItem.quantity)
        );
        delete (listings[_nftAddress][_tokenId][_owner]);
    }

    /// @notice Method for offering item
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _payToken Paying token
    /// @param _quantity Quantity of items
    /// @param _pricePerItem Price per item
    /// @param _deadline Offer expiration
    function createOffer(
        address _nftAddress,
        uint256 _tokenId,
        IERC20 _payToken,
        uint256 _quantity,
        uint256 _pricePerItem,
        uint256 _deadline
    ) external offerNotExists(_nftAddress, _tokenId, _msgSender()) {
        require(
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721) ||
                IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155),
            "invalid nft address"
        );

        IApparelAuction auction = IApparelAuction(addressRegistry.auction());

        (, , , uint256 startTime, , bool resulted) = auction.auctions(
            _nftAddress,
            _tokenId
        );

        require(
            startTime == 0 || resulted == true,
            "cannot place an offer if auction is going on"
        );

        require(_deadline > _getNow(), "invalid expiration");

        _validPayToken(address(_payToken));

        offers[_nftAddress][_tokenId][_msgSender()] = Offer(
            _payToken,
            _quantity,
            _pricePerItem,
            _deadline
        );

        emit OfferCreated(
            _msgSender(),
            _nftAddress,
            _tokenId,
            _quantity,
            address(_payToken),
            _pricePerItem,
            _deadline
        );
    }

    /// @notice Method for canceling the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    function cancelOffer(address _nftAddress, uint256 _tokenId)
        external
        offerExists(_nftAddress, _tokenId, _msgSender())
    {
        delete (offers[_nftAddress][_tokenId][_msgSender()]);
        emit OfferCanceled(_msgSender(), _nftAddress, _tokenId);
    }

    /// @notice Method for accepting the offer
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _creator Offer creator address
    function acceptOffer(
        address _nftAddress,
        uint256 _tokenId,
        address _creator
    ) external nonReentrant offerExists(_nftAddress, _tokenId, _creator) {
        Offer memory offer = offers[_nftAddress][_tokenId][_creator];

        _validOwner(_nftAddress, _tokenId, _msgSender(), offer.quantity);

        uint256 price = offer.pricePerItem.mul(offer.quantity);
        uint256 feeAmount = price.mul(platformFee).div(1e3);
        uint256 royaltyFee;

        if(address(offer.payToken) == peakAddress) {
            uint256 burnAmt = feeAmount.div(2);
            uint256 treasuryAmt = feeAmount.sub(burnAmt);
            IERC20(offer.payToken).transferFrom(
                _creator,
                address(this),
                feeAmount
            );
            IERC20(offer.payToken).transfer(treasuryWallet, treasuryAmt);
            IERC20(offer.payToken).burn(burnAmt);
        } else if(address(offer.payToken) == uniswapV2Router.Metis()) {
            uint256 buybackAmt = feeAmount.div(4);
            uint256 treasuryAmt = feeAmount.sub(buybackAmt);
            IERC20(offer.payToken).transferFrom(
                _creator,
                address(this),
                feeAmount
            );
            IERC20(offer.payToken).transfer(treasuryWallet, treasuryAmt);
            // BuyBack PRO Tokens
            swapTokensForTokens(buybackAmt);
            uint256 proAmt = IERC20(proAddress).balanceOf(address(this));
            IERC20(proAddress).transfer(treasuryWallet, proAmt);
        } else {
            IERC20(offer.payToken).transferFrom(
                _creator,
                treasuryWallet,
                feeAmount
            );
        }

        address minter = minters[_nftAddress][_tokenId];
        uint16 royalty = royalties[_nftAddress][_tokenId];

        if (minter != address(0) && royalty != 0) {
            royaltyFee = price.sub(feeAmount).mul(royalty).div(10000);
            offer.payToken.transferFrom(_creator, minter, royaltyFee);
            feeAmount = feeAmount.add(royaltyFee);
        } else {
            minter = collectionRoyalties[_nftAddress].feeRecipient;
            royalty = collectionRoyalties[_nftAddress].royalty;
            if (minter != address(0) && royalty != 0) {
                royaltyFee = price.sub(feeAmount).mul(royalty).div(10000);
                offer.payToken.transferFrom(_creator, minter, royaltyFee);
                feeAmount = feeAmount.add(royaltyFee);
            }
        }

        offer.payToken.transferFrom(
            _creator,
            _msgSender(),
            price.sub(feeAmount)
        );

        // Transfer NFT to buyer
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721(_nftAddress).safeTransferFrom(
                _msgSender(),
                _creator,
                _tokenId
            );
        } else {
            IERC1155(_nftAddress).safeTransferFrom(
                _msgSender(),
                _creator,
                _tokenId,
                offer.quantity,
                bytes("")
            );
        }

        emit ItemSold(
            _msgSender(),
            _creator,
            _nftAddress,
            _tokenId,
            offer.quantity,
            address(offer.payToken),
            getPrice(address(offer.payToken)),
            offer.pricePerItem
        );

        emit OfferCanceled(_creator, _nftAddress, _tokenId);

        delete (listings[_nftAddress][_tokenId][_msgSender()]);
        delete (offers[_nftAddress][_tokenId][_creator]);
    }

    /// @notice Method for setting royalty
    /// @param _nftAddress NFT contract address
    /// @param _tokenId TokenId
    /// @param _royalty Royalty
    function registerRoyalty(
        address _nftAddress,
        uint256 _tokenId,
        uint16 _royalty
    ) external {
        require(_royalty <= 10000, "invalid royalty");
        require(_isApparelNFT(_nftAddress), "invalid nft address");

        _validOwner(_nftAddress, _tokenId, _msgSender(), 1);

        require(
            minters[_nftAddress][_tokenId] == address(0),
            "royalty already set"
        );
        minters[_nftAddress][_tokenId] = _msgSender();
        royalties[_nftAddress][_tokenId] = _royalty;
    }

    /// @notice Method for setting royalty
    /// @param _nftAddress NFT contract address
    /// @param _royalty Royalty
    function registerCollectionRoyalty(
        address _nftAddress,
        address _creator,
        uint16 _royalty,
        address _feeRecipient
    ) external onlyOwner {
        require(_creator != address(0), "invalid creator address");
        require(_royalty <= 10000, "invalid royalty");
        require(
            _royalty == 0 || _feeRecipient != address(0),
            "invalid fee recipient address"
        );
        require(!_isApparelNFT(_nftAddress), "invalid nft address");

        if (collectionRoyalties[_nftAddress].creator == address(0)) {
            collectionRoyalties[_nftAddress] = CollectionRoyalty(
                _royalty,
                _creator,
                _feeRecipient
            );
        } else {
            CollectionRoyalty storage collectionRoyalty = collectionRoyalties[
                _nftAddress
            ];

            collectionRoyalty.royalty = _royalty;
            collectionRoyalty.feeRecipient = _feeRecipient;
            collectionRoyalty.creator = _creator;
        }
    }

    function _isApparelNFT(address _nftAddress) internal view returns (bool) {
        return
            IApparelNFTFactory(addressRegistry.factory()).exists(_nftAddress);
    }

    /**
     @notice Method for getting price for pay token
     @param _payToken Paying token
     */
    function getPrice(address _payToken) public view returns (int256) {
        int256 unitPrice;
        uint8 decimals;
        IApparelPriceFeed priceFeed = IApparelPriceFeed(
            addressRegistry.priceFeed()
        );

        if (_payToken == address(0)) {
            (unitPrice, decimals) = priceFeed.getPrice(priceFeed.wETH());
        } else {
            (unitPrice, decimals) = priceFeed.getPrice(_payToken);
        }
        if (decimals < 18) {
            unitPrice = unitPrice * (int256(10)**(18 - decimals));
        } else {
            unitPrice = unitPrice / (int256(10)**(decimals - 18));
        }

        return unitPrice;
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint16 the platform fee to set
     */
    function updatePlatformFee(uint16 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _treasury payable address the address to sends the funds to
     */
    function updateTreasuryAddress(address payable _treasury)
        external
        onlyOwner
    {
        treasuryWallet = _treasury;
        emit UpdateTreasuryAddress(_treasury);
    }

    /**
     @notice Update ApparelAddressRegistry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _registry) external onlyOwner {
        addressRegistry = IApparelAddressRegistry(_registry);
    }

    ////////////////////////////
    /// Internal and Private ///
    ////////////////////////////

    function _getNow() internal view virtual returns (uint256) {
        return block.timestamp;
    }

    function _validPayToken(address _payToken) internal view {
        require(
            _payToken == address(0) ||
                (addressRegistry.tokenRegistry() != address(0) &&
                    IApparelTokenRegistry(addressRegistry.tokenRegistry())
                        .enabled(_payToken)),
            "invalid pay token"
        );
    }

    function _validOwner(
        address _nftAddress,
        uint256 _tokenId,
        address _owner,
        uint256 quantity
    ) internal view {
        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            require(nft.ownerOf(_tokenId) == _owner, "not owning item");
        } else if (
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)
        ) {
            IERC1155 nft = IERC1155(_nftAddress);
            require(
                nft.balanceOf(_owner, _tokenId) >= quantity,
                "not owning item"
            );
        } else {
            revert("invalid nft address");
        }
    }

    function _cancelListing(
        address _nftAddress,
        uint256 _tokenId,
        address _owner
    ) private {
        Listing memory listedItem = listings[_nftAddress][_tokenId][_owner];

        _validOwner(_nftAddress, _tokenId, address(this), listedItem.quantity);

        if (IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC721)) {
            IERC721 nft = IERC721(_nftAddress);
            nft.safeTransferFrom(address(this), _owner, _tokenId);
        } else if (
            IERC165(_nftAddress).supportsInterface(INTERFACE_ID_ERC1155)
        ) {
            IERC1155 nft = IERC1155(_nftAddress);
            nft.safeTransferFrom(
                address(this),
                _owner,
                _tokenId,
                listedItem.quantity,
                bytes("")
            );
        }

        delete (listings[_nftAddress][_tokenId][_owner]);
        emit ItemCanceled(_owner, _nftAddress, _tokenId);
    }

    function swapTokensForTokens(uint256 tokenAmount) private {
        address[] memory path = new address[](2);
        path[0] = uniswapV2Router.Metis();
        path[1] = proAddress;

        // IERC20(uniswapV2Router.Metis()).approve(address(uniswapV2Router), tokenAmount);
        // make the swap
        uniswapV2Router.swapExactMetisForTokensSupportingFeeOnTransferTokens{value: tokenAmount}(0, path, address(this), block.timestamp);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./ApparelNFTTradable.sol";

contract ApparelNFTFactory is Ownable {
    /// @dev Events of the contract
    event ContractCreated(address creator, address nft);
    event ContractDisabled(address caller, address nft);

    /// @notice Apparel auction contract address;
    address public auction;

    /// @notice Apparel marketplace contract address;
    address public marketplace;

    /// @notice NFT mint fee
    uint256 public mintFee;

    /// @notice Platform fee for deploying new NFT contract
    uint256 public platformFee;

    /// @notice Platform fee recipient
    address payable public feeRecipient;

    /// @notice NFT Address => Bool
    mapping(address => bool) public exists;

    bytes4 private constant INTERFACE_ID_ERC721 = 0x80ac58cd;
    
    /// @notice Contract constructor
    constructor(
        address _auction,
        address _marketplace,
        uint256 _mintFee,
        address payable _feeRecipient,
        uint256 _platformFee
    ) {
        auction = _auction;
        marketplace = _marketplace;
        mintFee = _mintFee;
        feeRecipient = _feeRecipient;
        platformFee = _platformFee;
    }

     /**
    @notice Update auction contract
    @dev Only admin
    @param _auction address the auction contract address to set
    */
    function updateAuction(address _auction) external onlyOwner {
        auction = _auction;
    }

    /**
    @notice Update marketplace contract
    @dev Only admin
    @param _marketplace address the marketplace contract address to set
    */
    function updateMarketplace(address _marketplace) external onlyOwner {
        marketplace = _marketplace;
    }

    /**
    @notice Update mint fee
    @dev Only admin
    @param _mintFee uint256 the platform fee to set
    */
    function updateMintFee(uint256 _mintFee) external onlyOwner {
        mintFee = _mintFee;
    }

    /**
    @notice Update platform fee
    @dev Only admin
    @param _platformFee uint256 the platform fee to set
    */
    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _feeRecipient payable address the address to sends the funds to
     */
    function updateFeeRecipient(address payable _feeRecipient)
        external
        onlyOwner
    {
        feeRecipient = _feeRecipient;
    }

    /// @notice Method for deploy new ApparelNFTTradable contract
    /// @param _name Name of NFT contract
    /// @param _symbol Symbol of NFT contract
    function createNFTContract(string memory _name, string memory _symbol)
        external
        payable
        returns (address)
    {
        require(msg.value >= platformFee, "Insufficient funds.");
        (bool success,) = feeRecipient.call{value: msg.value}("");
        require(success, "Transfer failed");

        ApparelNFTTradable nft = new ApparelNFTTradable(
            _name,
            _symbol,
            auction,
            marketplace,
            mintFee,
            feeRecipient
        );
        exists[address(nft)] = true;
        nft.transferOwnership(_msgSender());
        emit ContractCreated(_msgSender(), address(nft));
        return address(nft);
    }

    /// @notice Method for registering existing ApparelNFTTradable contract
    /// @param  tokenContractAddress Address of NFT contract
    function registerTokenContract(address tokenContractAddress)
        external
        onlyOwner
    {
        require(!exists[tokenContractAddress], "NFT contract already registered");
        require(IERC165(tokenContractAddress).supportsInterface(INTERFACE_ID_ERC721), "Not an ERC721 contract");
        exists[tokenContractAddress] = true;
        emit ContractCreated(_msgSender(), tokenContractAddress);
    }

    /// @notice Method for disabling existing ApparelNFTTradable contract
    /// @param  tokenContractAddress Address of NFT contract
    function disableTokenContract(address tokenContractAddress)
        external
        onlyOwner
    {
        require(exists[tokenContractAddress], "NFT contract is not registered");
        exists[tokenContractAddress] = false;
        emit ContractDisabled(_msgSender(), tokenContractAddress);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ApparelNFTTradable
 * ApparelNFTTradable - ERC721 contract that whitelists a trading address, and has minting functionality.
 */
contract ApparelNFTTradable is ERC721URIStorage, Ownable {
    /// @dev Events of the contract
    event Minted(
        uint256 tokenId,
        address beneficiary,
        string tokenUri,
        address minter
    );
    event UpdatePlatformFee(
        uint256 platformFee
    );
    event UpdateFeeRecipient(
        address payable feeRecipient
    );
    address auction;
    address marketplace;
    uint256 private _currentTokenId = 0;

    /// @notice Platform fee
    uint256 public platformFee;

    /// @notice Platform fee receipient
    address payable public feeReceipient;

    /// @notice Contract constructor
    constructor(
        string memory _name,
        string memory _symbol,
        address _auction,
        address _marketplace,
        uint256 _platformFee,
        address payable _feeReceipient
    ) ERC721(_name, _symbol) {
        auction = _auction;
        marketplace = _marketplace;
        platformFee = _platformFee;
        feeReceipient = _feeReceipient;
    }

    /**
     @notice Method for updating platform fee
     @dev Only admin
     @param _platformFee uint256 the platform fee to set
     */
    function updatePlatformFee(uint256 _platformFee) external onlyOwner {
        platformFee = _platformFee;
        emit UpdatePlatformFee(_platformFee);
    }

    /**
     @notice Method for updating platform fee address
     @dev Only admin
     @param _feeReceipient payable address the address to sends the funds to
     */
    function updateFeeRecipient(address payable _feeReceipient)
        external
        onlyOwner
    {
        feeReceipient = _feeReceipient;
        emit UpdateFeeRecipient(_feeReceipient);
    }

    /**
     * @dev Mints a token to an address with a tokenURI.
     * @param _to address of the future owner of the token
     */
    function mint(address _to, string calldata _tokenUri) external payable {
        require(msg.value >= platformFee, "Insufficient funds to cover fee.");

        uint256 newTokenId = _getNextTokenId();
        _safeMint(_to, newTokenId);
        _setTokenURI(newTokenId, _tokenUri);
        _incrementTokenId();

        // Send ETH fee to fee recipient
        (bool success,) = feeReceipient.call{value : msg.value}("");
        require(success, "Transfer failed");

        emit Minted(newTokenId, _to, _tokenUri, _msgSender());
    }

    /**
    @notice Burns a DigitalaxGarmentNFT, releasing any composed 1155 tokens held by the token itself
    @dev Only the owner or an approved sender can call this method
    @param _tokenId the token ID to burn
    */
    function burn(uint256 _tokenId) external {
        address operator = _msgSender();
        require(
            ownerOf(_tokenId) == operator || isApproved(_tokenId, operator),
            "Only garment owner or approved"
        );

        // Destroy token mappings
        _burn(_tokenId);
    }

    /**
     * @dev calculates the next token ID based on value of _currentTokenId
     * @return uint256 for the next token ID
     */
    function _getNextTokenId() private view returns (uint256) {
        return _currentTokenId + 1;
    }

    /**
     * @dev increments the value of _currentTokenId
     */
    function _incrementTokenId() private {
        _currentTokenId++;
    }

    /**
     * @dev checks the given token ID is approved either for all or the single token ID
     */
    function isApproved(uint256 _tokenId, address _operator) public view returns (bool) {
        return isApprovedForAll(ownerOf(_tokenId), _operator) || getApproved(_tokenId) == _operator;
    }

    /**
     * Override isApprovedForAll to whitelist Apparel contracts to enable gas-less listings.
     */
    function isApprovedForAll(address owner, address operator)
        override
        public
        view
        returns (bool)
    {
        // Whitelist Apparel marketplace for easy trading.
        if (
            auction == operator || marketplace == operator
        ) {
            return true;
        }

        return super.isApprovedForAll(owner, operator);
    }

    /**
     * Override _isApprovedOrOwner to whitelist Apparel contracts to enable gas-less listings.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) override internal view returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        if (isApprovedForAll(owner, spender)) return true;
        return super._isApprovedOrOwner(spender, tokenId);
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IApparelAddressRegistry {
    function tokenRegistry() external view returns (address);
}

interface IApparelTokenRegistry {
    function enabled(address) external returns (bool);
}

interface IOracle {
    function decimals() external view returns (uint8);

    function latestAnswer() external view returns (int256);
}

contract ApparelPriceFeed is Ownable {
    /// @notice keeps track of oracles for each tokens
    mapping(address => address) public oracles;

    /// @notice apparel address registry contract
    address public addressRegistry;

    /// @notice wrapped ETH contract
    address public wETH;

    constructor(address _addressRegistry, address _wETH) {
        addressRegistry = _addressRegistry;
        wETH = _wETH;
    }

    /**
     @notice Register oracle contract to token
     @dev Only owner can register oracle
     @param _token ERC20 token address
     @param _oracle Oracle address
     */
    function registerOracle(address _token, address _oracle)
        external
        onlyOwner
    {
        IApparelTokenRegistry tokenRegistry = IApparelTokenRegistry(
            IApparelAddressRegistry(addressRegistry).tokenRegistry()
        );
        require(tokenRegistry.enabled(_token), "invalid token");
        require(oracles[_token] == address(0), "oracle already set");

        oracles[_token] = _oracle;
    }

    /**
     @notice Update oracle address for token
     @dev Only owner can update oracle
     @param _token ERC20 token address
     @param _oracle Oracle address
     */
    function updateOracle(address _token, address _oracle) external onlyOwner {
        require(oracles[_token] != address(0), "oracle not set");

        oracles[_token] = _oracle;
    }

    /**
     @notice Get current price for token
     @dev return current price or if oracle is not registered returns 0
     @param _token ERC20 token address
     */
    function getPrice(address _token) external view returns (int256, uint8) {
        if (oracles[_token] == address(0)) {
            return (0, 0);
        }

        IOracle oracle = IOracle(oracles[_token]);
        return (oracle.latestAnswer(), oracle.decimals());
    }

    /**
     @notice Update address registry contract
     @dev Only admin
     */
    function updateAddressRegistry(address _addressRegistry)
        external
        onlyOwner
    {
        addressRegistry = _addressRegistry;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";

contract ApparelTokenRegistry is Ownable {
  /// @dev Events of the contract
  event TokenAdded(address token);
  event TokenRemoved(address token);

  /// @notice ERC20 Address -> Bool
  mapping(address => bool) public enabled;

  /**
  @notice Method for adding payment token
  @dev Only admin
  @param token ERC20 token address
  */
  function add(address token) external onlyOwner {
    require(!enabled[token], "token already added");
    enabled[token] = true;
    emit TokenAdded(token);
  }

  /**
  @notice Method for removing payment token
  @dev Only admin
  @param token ERC20 token address
  */
  function remove(address token) external onlyOwner {
    require(enabled[token], "token not exist");
    enabled[token] = false;
    emit TokenRemoved(token);
  }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IUniswapV2Router {
    function factory() external pure returns (address);
    function Metis() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB, uint liquidity);
    function addLiquidityMetis(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountMetisMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountMetis, uint liquidity);
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityMetis(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMetisMin,
        address to,
        uint deadline
    ) external returns (uint amountToken, uint amountMetis);
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountA, uint amountB);
    function removeLiquidityMetisWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMetisMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountToken, uint amountMetis);
    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline
    ) external returns (uint[] memory amounts);
    function swapExactMetisForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);
    function swapTokensForExactMetis(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapExactTokensForMetis(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
        external
        returns (uint[] memory amounts);
    function swapMetisForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
        external
        payable
        returns (uint[] memory amounts);

    function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external view returns (uint amountOut);
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external view returns (uint amountIn);
    function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);
    function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
    function removeLiquidityMetisSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMetisMin,
        address to,
        uint deadline
    ) external returns (uint amountMetis);
    function removeLiquidityMetisWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountMetisMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) external returns (uint amountMetis);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapExactMetisForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external payable;
    function swapExactTokensForMetisSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline
    ) external;
    function swapMining() external pure returns (address);
}
