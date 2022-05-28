// SPDX-License-Identifier: BlueOak-1.0.0
// pragma should be as specific as possible to allow easier validation.
pragma solidity = 0.8.6;

// ETHSwap creates a contract to be deployed on an ethereum network. After
// deployed, it keeps a map of swaps that facilitates atomic swapping of
// ethereum with other crypto currencies that support time locks.
//
// It accomplishes this by holding funds sent to this contract until certain
// conditions are met. An initiator sends an amount of funds along with byte
// code that tells the contract to insert a swap struct into the public map. At
// this point the funds belong to the contract, and cannot be accessed by
// anyone else, not even the contract's deployer. The initiator sets a
// participant, a secret hash, and a refund blocktime. The participant can
// redeem at any time after the initiation transaction is mined if they have
// the secret that hashes to the secret hash. Otherwise, anyone can refund
// funds any time after the locktime.
//
// This contract has no limits on gas used for any transactions.
//
// This contract cannot be used by other contracts or by a third party mediating
// the swap or multisig wallets.
//
// This code should be verifiable as resulting in a certain on-chain contract
// by compiling with the correct version of solidity and comparing the
// resulting byte code to the data in the original transaction.
contract ETHSwap {
    // State is a type that hold's a contract's state. Empty is the uninitiated
    // or null value.
    enum State { Empty, Filled, Redeemed, Refunded }

    // Swap holds information related to one side of a single swap. The order of
    // the struct fields is important to efficiently pack the struct into as few
    // 256-bit slots as possible to reduce gas cost. In particular, the 160-bit
    // address can pack with the 8-bit State.
    struct Swap {
        bytes32 secret;
        uint256 value;
        uint initBlockNumber;
        uint refundBlockTimestamp;
        address initiator;
        address participant;
        State state;
    }

    // swaps is a map of swap secret hashes to swaps. It can be read by anyone
    // for free.
    mapping(bytes32 => Swap) public swaps;

    // constructor is empty. This contract has no connection to the original
    // sender after deployed. It can only be interacted with by users
    // initiating, redeeming, and refunding swaps.
    constructor() {}

    // isRefundable checks that a swap can be refunded. The requirements are
    // the state is Filled, and the block timestamp be after the swap's stored
    // refundBlockTimestamp.
    function isRefundable(bytes32 secretHash) public view returns (bool) {
        Swap storage swapToCheck = swaps[secretHash];
        return swapToCheck.state == State.Filled &&
               block.timestamp >= swapToCheck.refundBlockTimestamp;
    }

    // senderIsOrigin ensures that this contract cannot be used by other
    // contracts, which reduces possible attack vectors.
    modifier senderIsOrigin() {
        require(tx.origin == msg.sender, "sender != origin");
        _;
    }

    // swap returns a single swap from the swaps map.
    function swap(bytes32 secretHash)
        public view returns(Swap memory)
    {
        return swaps[secretHash];
    }

    struct Initiation {
        uint refundTimestamp;
        bytes32 secretHash;
        address participant;
        uint value;
    }

    // initiate initiates an array of swaps. It checks that all of the
    // swaps have a non zero redemptionTimestamp and value, and that none of
    // the secret hashes have ever been used previously. The function also makes
    // sure that msg.value is equal to the sum of the values of all the swaps.
    // Once initiated, each swap's state is set to Filled. The msg.value is now
    // in the custody of the contract and can only be retrieved through redeem
    // or refund.
    function initiate(Initiation[] calldata initiations)
        public
        payable
        senderIsOrigin()
    {
        uint initVal = 0;
        for (uint i = 0; i < initiations.length; i++) {
            Initiation calldata initiation = initiations[i];
            Swap storage swapToUpdate = swaps[initiation.secretHash];

            require(initiation.value > 0, "0 val");
            require(initiation.refundTimestamp > 0, "0 refundTimestamp");
            require(swapToUpdate.state == State.Empty, "dup swap");

            swapToUpdate.initBlockNumber = block.number;
            swapToUpdate.refundBlockTimestamp = initiation.refundTimestamp;
            swapToUpdate.initiator = msg.sender;
            swapToUpdate.participant = initiation.participant;
            swapToUpdate.value = initiation.value;
            swapToUpdate.state = State.Filled;

            initVal += initiation.value;
        }

        require(initVal == msg.value, "bad val");
    }

    struct Redemption {
        bytes32 secret;
        bytes32 secretHash;
    }

    // isRedeemable returns whether or not a swap identified by secretHash
    // can be redeemed using secret.
    function isRedeemable(bytes32 secretHash, bytes32 secret)
        public
        view
        returns (bool)
    {
        return swaps[secretHash].state == State.Filled &&
               swaps[secretHash].participant == msg.sender &&
               sha256(abi.encodePacked(secret)) == secretHash;
    }

    // redeem redeems a contract. It checks that the sender is not a contract,
    // and that the secret hash hashes to secretHash. msg.value is tranfered
    // from the contract to the sender.
    //
    // It is important to note that this uses call.value which comes with no
    // restrictions on gas used. This has the potential to open the contract up
    // to a reentry attack. A reentry attack inserts extra code in call.value
    // that executes before the function returns. This is why it is very
    // important to check the state of the contract first, and change the state
    // before proceeding to send. That way, the nested attacking function will
    // throw upon trying to call redeem a second time. Currently, reentry is also
    // not possible because contracts cannot use this contract.
    function redeem(Redemption[] calldata redemptions)
        public
        senderIsOrigin()
    {
        uint amountToRedeem = 0;
        for (uint i = 0; i < redemptions.length; i++) {
            Redemption calldata redemption = redemptions[i];
            Swap storage swapToRedeem = swaps[redemption.secretHash];

            require(swapToRedeem.state == State.Filled, "bad state");
            require(swapToRedeem.participant == msg.sender, "bad participant");
            require(sha256(abi.encodePacked(redemption.secret)) == redemption.secretHash,
                "bad secret");

            swapToRedeem.state = State.Redeemed;
            swapToRedeem.secret = redemption.secret;
            amountToRedeem += swapToRedeem.value;
        }

        (bool ok, ) = payable(msg.sender).call{value: amountToRedeem}("");
        require(ok == true, "transfer failed");
    }

    // refund refunds a contract. It checks that the sender is not a contract,
    // and that the refund time has passed. msg.value is transferred from the
    // contract to the initiator.
    //
    // It is important to note that this also uses call.value which comes with no
    // restrictions on gas used. See redeem for more info.
    function refund(bytes32 secretHash)
        public
        senderIsOrigin()
    {
        require(isRefundable(secretHash), "not refundable");
        Swap storage swapToRefund = swaps[secretHash];
        swapToRefund.state = State.Refunded;
        (bool ok, ) = payable(swapToRefund.initiator).call{value: swapToRefund.value}("");
        require(ok == true, "transfer failed");
    }
}

// SPDX-License-Identifier: BlueOak-1.0.0
// pragma should be as specific as possible to allow easier validation.
pragma solidity = 0.8.6;

// ETHSwap creates a contract to be deployed on an ethereum network. After
// deployed, it keeps a record of the state of a contract and enables
// redemption and refund of the contract when conditions are met.
//
// ETHSwap accomplishes this by holding funds sent to ETHSwap until certain
// conditions are met. An initiator sends a tx with the Contract(s) to fund and
// the requisite value to transfer to ETHSwap. At
// this point the funds belong to the contract, and cannot be accessed by
// anyone else, not even the contract's deployer. The swap Contract specifies
// the conditions necessary for refund and redeem.
//
// ETHSwap has no limits on gas used for any transactions.
//
// ETHSwap cannot be used by other contracts or by a third party mediating
// the swap or multisig wallets.
//
// This code should be verifiable as resulting in a certain on-chain contract
// by compiling with the correct version of solidity and comparing the
// resulting byte code to the data in the original transaction.
contract ETHSwap {
    // State is a type that hold's a contract's state. Empty is the uninitiated
    // or null value.
    enum State { Empty, Filled, Redeemed, Refunded }

    bytes32 constant RefundRecord = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF;

    // swaps is a map of contract hashes to the "swap record". The swap record
    // has the following interpretation.
    //   if (record == bytes32(0x00)): contract is uninitiated
    //   else if (uint256(record) < block.number && sha256(record) != contract.secretHash):
    //      contract is initiated and redeemable by the participant with the secret.
    //   else if (sha256(record) == contract.secretHash): contract has been redeemed
    //   else if (record == RefundRecord): contract has been refunded
    //   else: invalid record. Should be impossible by construction
    mapping(bytes32 => bytes32) public swaps;

    // Contract is the information necessary for initialization and redemption
    // or refund. The Contract itself is not stored on-chain. Instead, a key
    // unique to the Contract is generated from the Contract data and keys
    // the swap record.
    struct Contract {
        bytes32 secretHash;
        address initiator;
        uint64 refundTimestamp;
        address participant;
        uint64 value;
    }

    // contractKey generates a key hash which commits to the contract data. The
    // generated hash is used as a key in the swaps map.
    function contractKey(Contract calldata c) public pure returns (bytes32) {
        return sha256(abi.encodePacked(c.secretHash, c.initiator, c.participant, c.value, c.refundTimestamp));
    }

    // Redemption is the information necessary to redeem a Contract. Since we
    // don't store the Contract itself, it must be provided as part of the
    // redemption.
    struct Redemption {
        Contract c;
        bytes32 secret;
    }

    function secretValidates(bytes32 secret, bytes32 secretHash) public pure returns (bool) {
        return sha256(abi.encodePacked(secret)) == secretHash;
    }

    // constructor is empty. This contract has no connection to the original
    // sender after deployed. It can only be interacted with by users
    // initiating, redeeming, and refunding swaps.
    constructor() {}

    // senderIsOrigin ensures that this contract cannot be used by other
    // contracts, which reduces possible attack vectors.
    modifier senderIsOrigin() {
        require(tx.origin == msg.sender, "sender != origin");
        _;
    }

    // retrieveRecord retrieves the current swap record for the contract.
    function retrieveRecord(Contract calldata c)
        private view returns (bytes32, bytes32, uint256)
    {
        bytes32 k = contractKey(c);
        bytes32 record = swaps[k];
        return (k, record, uint256(record));
    }

    // state returns the current state of the swap.
    function state(Contract calldata c)
        public view returns(State)
    {
        (, bytes32 record, uint256 blockNum) = retrieveRecord(c);

        if (blockNum == 0) {
            return State.Empty;
        }
        if (record == RefundRecord) {
            return State.Refunded;
        }
        if (secretValidates(record, c.secretHash)) {
            return State.Redeemed;
        }
        return State.Filled;
    }

    // initiate initiates an array of Contracts.
    function initiate(Contract[] calldata contracts)
        public
        payable
        senderIsOrigin()
    {
        uint initVal = 0;
        for (uint i = 0; i < contracts.length; i++) {
            Contract calldata c = contracts[i];

            require(c.value > 0, "0 val");
            require(c.refundTimestamp > 0, "0 refundTimestamp");

            bytes32 k = contractKey(c);
            bytes32 record = swaps[k];
            require(record == bytes32(0), "swap not empty");

            record = bytes32(block.number);
            require(!secretValidates(record, c.secretHash), "hash collision");

            swaps[k] = record;

            initVal += c.value * 1 gwei;
        }

        require(initVal == msg.value, "bad val");
    }

    // isRedeemable returns whether or not a swap identified by secretHash
    // can be redeemed using secret.
    function isRedeemable(Contract calldata c)
        public
        view
        returns (bool)
    {
        (, bytes32 record, uint256 blockNum) = retrieveRecord(c);
        return blockNum != 0 && blockNum <= block.number && !secretValidates(record, c.secretHash);
    }

    // redeem redeems a Contract. It checks that the sender is not a contract,
    // and that the secret hash hashes to secretHash. msg.value is tranfered
    // from ETHSwap to the sender.
    //
    // To prevent reentry attack, it is very important to check the state of the
    // contract first, and change the state before proceeding to send. That way,
    // the nested attacking function will throw upon trying to call redeem a
    // second time. Currently, reentry is also not possible because contracts
    // cannot use this contract.
    function redeem(Redemption[] calldata redemptions)
        public
        senderIsOrigin()
    {
        uint amountToRedeem = 0;
        for (uint i = 0; i < redemptions.length; i++) {
            Redemption calldata r = redemptions[i];

            require(r.c.participant == msg.sender, "not authed");

            (bytes32 k, bytes32 record, uint256 blockNum) = retrieveRecord(r.c);

            // To be redeemable, the record needs to represent a valid block
            // number.
            require(blockNum > 0 && blockNum < block.number, "unfilled swap");

            // Can't already be redeemed.
            require(!secretValidates(record, r.c.secretHash), "already redeemed");

            // Are they presenting the correct secret?
            require(secretValidates(r.secret, r.c.secretHash), "invalid secret");

            swaps[k] = r.secret;
            amountToRedeem += r.c.value * 1 gwei;
        }

        (bool ok, ) = payable(msg.sender).call{value: amountToRedeem}("");
        require(ok == true, "transfer failed");
    }

    // refund refunds a Contract. It checks that the sender is not a contract
    // and that the refund time has passed. msg.value is transfered from the
    // contract to the sender = Contract.participant.
    //
    // It is important to note that this also uses call.value which comes with
    // no restrictions on gas used. See redeem for more info.
    function refund(Contract calldata c)
        public
        senderIsOrigin()
    {
        // Is this contract even in a refundable state?
        require(c.initiator == msg.sender, "sender not initiator");
        require(block.timestamp >= c.refundTimestamp, "locktime not expired");

        // Retrieve the record.
        (bytes32 k, bytes32 record, uint256 blockNum) = retrieveRecord(c);

        // Is this swap initialized?
        require(blockNum > 0 && blockNum < block.number, "swap not active");

        // Is it already redeemed?
        require(!secretValidates(record, c.secretHash), "swap already redeemed");

        // Is it already refunded?
        require(record != RefundRecord, "swap already refunded");

        swaps[k] = RefundRecord;

        (bool ok, ) = payable(msg.sender).call{value: c.value * 1 gwei}("");
        require(ok == true, "transfer failed");
    }
}

// SPDX-License-Identifier: BlueOak-1.0.0
// pragma should be as specific as possible to allow easier validation.
pragma solidity = 0.8.6;

// ETHSwap creates a contract to be deployed on an ethereum network. In
// order to save on gas fees, a separate ERC20Swap contract is deployed
// for each ERC20 token. After deployed, it keeps a map of swaps that
// facilitates atomic swapping of ERC20 tokens with other crypto currencies
// that support time locks. 
//
// It accomplishes this by holding tokens acquired during a swap initiation
// until conditions are met. Prior to initiating a swap, the initiator must
// approve the ERC20Swap contract to be able to spend the initiator's tokens.
// When calling initiate, the necessary tokens for swaps are transferred to
// the swap contract. At this point the funds belong to the contract, and
// cannot be accessed by anyone else, not even the contract's deployer. The
// initiator sets a secret hash, a blocktime the funds will be accessible should
// they not be redeemed, and a participant who can redeem before or after the
// locktime. The participant can redeem at any time after the initiation
// transaction is mined if they have the secret that hashes to the secret hash.
// Otherwise, the initiator can refund funds any time after the locktime.
//
// This contract has no limits on gas used for any transactions.
//
// This contract cannot be used by other contracts or by a third party mediating
// the swap or multisig wallets.
contract ERC20Swap {
    bytes4 private constant TRANSFER_FROM_SELECTOR = bytes4(keccak256("transferFrom(address,address,uint256)"));
    bytes4 private constant TRANSFER_SELECTOR = bytes4(keccak256("transfer(address,uint256)"));
    
    address public immutable token_address;

    // State is a type that hold's a contract's state. Empty is the uninitiated
    // or null value.
    enum State { Empty, Filled, Redeemed, Refunded }

    // Swap holds information related to one side of a single swap. The order of
    // the struct fields is important to efficiently pack the struct into as few
    // 256-bit slots as possible to reduce gas cost. In particular, the 160-bit
    // address can pack with the 8-bit State.
    struct Swap {
        bytes32 secret;
        uint256 value;
        uint initBlockNumber;
        uint refundBlockTimestamp;
        address initiator;
        address participant;
        State state;
    }

    // swaps is a map of swap secret hashes to swaps. It can be read by anyone
    // for free.
    mapping(bytes32 => Swap) public swaps;

    constructor(address token) {
        token_address = token;
    }

    // senderIsOrigin ensures that this contract cannot be used by other
    // contracts, which reduces possible attack vectors.
    modifier senderIsOrigin() {
        require(tx.origin == msg.sender, "sender != origin");
        _;
    }

    // swap returns a single swap from the swaps map.
    function swap(bytes32 secretHash)
        public view returns(Swap memory)
    {
        return swaps[secretHash];
    }

    // Initiation is used to specify the information needed to initiatite a swap.
    struct Initiation {
        uint refundTimestamp;
        bytes32 secretHash;
        address participant;
        uint value;
    }

    // initiate initiates an array of swaps. It checks that all of the swaps
    // have a non zero redemptionTimestamp and value, and that none of the
    // secret hashes have ever been used previously. Once initiated, each
    // swap's state is set to Filled. The tokens equal to the sum of each
    // swap's value are now in the custody of the contract and can only be
    // retrieved through redeem or refund.
    function initiate(Initiation[] calldata initiations)
        public
        senderIsOrigin()
    {
        uint initVal = 0;
        for (uint i = 0; i < initiations.length; i++) {
            Initiation calldata initiation = initiations[i];
            Swap storage swapToUpdate = swaps[initiation.secretHash];

            require(initiation.value > 0, "0 val");
            require(initiation.refundTimestamp > 0, "0 refundTimestamp");
            require(swapToUpdate.state == State.Empty, "dup secret hash");

            swapToUpdate.initBlockNumber = block.number;
            swapToUpdate.refundBlockTimestamp = initiation.refundTimestamp;
            swapToUpdate.initiator = msg.sender;
            swapToUpdate.participant = initiation.participant;
            swapToUpdate.value = initiation.value;
            swapToUpdate.state = State.Filled;

            initVal += initiation.value;
        }

        bool success;
        bytes memory data;
        (success, data) = token_address.call(abi.encodeWithSelector(TRANSFER_FROM_SELECTOR, msg.sender, address(this), initVal));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'transfer from failed');
    }

    // Redemption is used to specify the information needed to redeem a swap.
    struct Redemption {
        bytes32 secret;
        bytes32 secretHash;
    }

    // isRedeemable returns whether or not a swap identified by secretHash
    // can be redeemed using secret.
    function isRedeemable(bytes32 secretHash, bytes32 secret)
        public
        view
        returns (bool)
    {
        Swap storage swapToRedeem = swaps[secretHash];
        return swapToRedeem.state == State.Filled &&
               swapToRedeem.participant == msg.sender &&
               sha256(abi.encodePacked(secret)) == secretHash;
    }

    // redeem redeems an array of swaps contract. It checks that the sender is
    // not a contract, and that the secret hash hashes to secretHash. The ERC20
    // tokens are tranfered from the contract to the sender.
    function redeem(Redemption[] calldata redemptions)
        public
        senderIsOrigin()
    {
        uint amountToRedeem = 0;
        for (uint i = 0; i < redemptions.length; i++) {
            Redemption calldata redemption = redemptions[i];
            Swap storage swapToRedeem = swaps[redemption.secretHash];

            require(swapToRedeem.state == State.Filled, "bad state");
            require(swapToRedeem.participant == msg.sender, "bad participant");
            require(sha256(abi.encodePacked(redemption.secret)) == redemption.secretHash,
                "bad secret");

            swapToRedeem.state = State.Redeemed;
            swapToRedeem.secret = redemption.secret;
            amountToRedeem += swapToRedeem.value;
        }

        bool success;
        bytes memory data;
        (success, data) = token_address.call(abi.encodeWithSelector(TRANSFER_SELECTOR, msg.sender, amountToRedeem));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'transfer failed');
    }


    // isRefundable checks that a swap can be refunded. The requirements are
    // the initiator is msg.sender, the state is Filled, and the block
    // timestamp be after the swap's stored refundBlockTimestamp.
    function isRefundable(bytes32 secretHash) public view returns (bool) {
        Swap storage swapToCheck = swaps[secretHash];
        return swapToCheck.state == State.Filled &&
               swapToCheck.initiator == msg.sender &&
               block.timestamp >= swapToCheck.refundBlockTimestamp;
    }

    // refund refunds a contract. It checks that the sender is not a contract,
    // and that the refund time has passed. An amount of ERC20 tokens equal to
    // swap.value is tranfered from the contract to the sender.
    function refund(bytes32 secretHash)
        public
        senderIsOrigin()
    {
        require(isRefundable(secretHash), "not refundable");
        Swap storage swapToRefund = swaps[secretHash];
        swapToRefund.state = State.Refunded;

        bool success;
        bytes memory data;
        (success, data) = token_address.call(abi.encodeWithSelector(TRANSFER_SELECTOR, msg.sender, swapToRefund.value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'transfer failed');
    }
}