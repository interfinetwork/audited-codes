pragma solidity ^0.8.0;

import "./PumpToken.sol";
import "./PumpTreasury.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import "./vPumpToken.sol";

contract ElectionManager is Ownable, Initializable {
    // View only struct -- used to group data returned by view functions
    struct BuyProposalMetadata {
        address proposer;
        uint256 createdAt;
        uint256 totalVotes;
    }

    // View only struct -- used to group data returned by view functions
    struct SellProposalMetadata {
        bool valid;
        uint256 totalVotes;
        uint256 createdAt;
    }

    struct Election {
        // The first block on which votes for this election can be cast
        uint256 votingStartBlock;
        // The last block on which votes for this election will be accepted, after this calls to vote will revert
        uint256 votingEndBlock;
        // The first block where a winner for the election can be declared. Intentionally different than votingEndBlock
        // in order to prevent flash loan attacks
        uint256 winnerDeclaredBlock;
        // Mapping from proposed taken address to bool indicating if this token has been proposed in this election
        mapping(address => bool) validProposals;
        // Mapping from proposed token address to data about the proposal
        mapping(address => BuyProposal) proposals;
        // Array of proposed token addresses -- useful for iterating over all proposals
        address[] proposedTokens;
        // Bool indicating if the winner has already been declared for this proposal
        bool winnerDeclared;
        // The address of the winning token
        address winner;
        // The amount of the winning token that has been purchased as a result of this election
        uint256 purchasedAmt;
        // The number of buys made for this election. Should never exceed the global maxBuys
        uint8 numBuysMade;
        // The next block on which a buy order can be made for this election
        uint256 nextValidBuyBlock;
        // The number of attempted buys that have failed for this election
        uint8 numFailures;
        // Indicates if sell proposal votes can be cast for this election
        bool sellProposalActive;
        // The total number of sell votes that have been cast for the sell proposal
        uint256 sellProposalTotalVotes;
        // The block number on which this sell proposal was created
        uint256 sellProposalCreatedAt;
        // Mapping from account to the number of sell votes they have cast for this election
        mapping(address => uint256) sellVotes;
    }

    // View only struct -- used to group data returned by view functions
    struct ElectionMetadata {
        uint256 votingStartBlock;
        uint256 votingEndBlock;
        uint256 winnerDeclaredBlock;
        bool winnerDeclared;
        address winner;
        // Buy related Data
        uint8 numBuysMade;
        uint256 nextValidBuyBlock;
        uint8 numFailures;
        // Sell related data
        bool sellProposalActive;
        uint256 sellProposalTotalVotes;
        uint256 sellProposalCreatedAt;
    }

    // Data related to a single buy proposal within an election
    struct BuyProposal {
        // Address of the accounts / contract that proposed the token
        address proposer;
        // The block that the proposal was created
        uint256 createdAt;
        // The total number of votes cast for this proposal
        uint256 totalVotes;
        // Mapping from account to the number of votes they have cast for this proposal
        mapping(address => uint256) votes;
    }

    // The number of blocks between when voting ends and a winner is declared. Prevents flash loan attacks.
    uint256 public winnerDelay;
    // Time between the start of an election and when the winner is declared
    uint256 public electionLength;
    // Address of the token for which a proposal will always be created by default
    address public defaultProposal;
    // The number of buys that will be made for each winning token (assuming the maxBuyFailures is not hit)
    uint256 public maxNumBuys;
    // The number of blocks to wait between each buy is made
    uint256 public buyCooldownBlocks;
    // The number of allowed buy failures after which a sell proposal becomes valid
    uint8 public maxBuyFailures = 2;
    // The number of blocks to wait before the sell proposal quorum requirements begin to decay
    uint256 public sellLockupBlocks;
    // The half life of the sell proposal quorum requirements
    uint256 public sellHalfLifeBlocks;
    // The index of the current election
    uint256 public currElectionIdx;
    // Mapping from election Idx to data about the election
    mapping(uint256 => Election) public elections;
    VPumpToken public vPumpToken;
    // Fee required in order to create a proposal
    uint256 public proposalCreationTax = 0.25 * 10**18;
    PumpTreasury public treasury;
    // The maximum number of allowed proposals per election.
    uint8 maxProposalsPerElection = 100;


    event ProposalCreated(uint16 electionIdx, address tokenAddr);
    event BuyVoteDeposited(uint16 electionIdx, address tokenAddr, uint256 amt);
    event SellVoteDeposited(uint16 electionIdx, address tokenAddr, uint256 amt);
    event BuyVoteWithdrawn(uint16 electionIdx, address tokenAddr, uint256 amt);
    event SellVoteWithdrawn(uint16 electionIdx, address tokenAddr, uint256 amt);
    event WinnerDeclared(uint16 electionIdx, address winner, uint256 numVotes);
    event SellProposalExecuted(uint16 electionIdx);

    // Initialize takes the place of constructor in order to use a proxy pattern to upgrade later
    function initialize(
        VPumpToken _vPumpToken,
        uint256 _startBlock,
        uint256 _winnerDelay,
        uint256 _electionLength,
        address _defaultProposal,
        PumpTreasury _treasury,
        uint256 _maxNumBuys,
        uint256 _buyCooldownBlocks,
        uint256 _sellLockupBlocks,
        uint256 _sellHalfLifeBlocks
    ) public initializer {
        winnerDelay = _winnerDelay;
        electionLength = _electionLength;
        defaultProposal = _defaultProposal;
        vPumpToken = _vPumpToken;
        currElectionIdx = 0;
        treasury = _treasury;
        maxNumBuys = _maxNumBuys;
        buyCooldownBlocks = _buyCooldownBlocks;
        sellLockupBlocks = _sellLockupBlocks;
        sellHalfLifeBlocks = _sellHalfLifeBlocks;

        Election storage firstElection = elections[0];
        firstElection.votingStartBlock = _startBlock;
        firstElection.votingEndBlock = _startBlock + electionLength - winnerDelay;
        firstElection.winnerDeclaredBlock = _startBlock + electionLength;

        firstElection.validProposals[defaultProposal] = true;
        firstElection.proposals[defaultProposal].proposer = address(this);
        firstElection.proposals[defaultProposal].createdAt = block.number;
        firstElection.proposedTokens.push(defaultProposal);

    }

    function createProposal(uint16 _electionIdx, address _tokenAddr)
        public
        payable
    {
        require(
            _electionIdx == currElectionIdx,
            "Must use currentElectionIdx"
        );
        Election storage electionMetadata = elections[currElectionIdx];
        require(
            !electionMetadata.validProposals[_tokenAddr],
            "Proposal already created"
        );
        require(
            msg.value >= proposalCreationTax,
            "BuyProposal creation tax not met"
        );
        require(
            electionMetadata.proposedTokens.length <= maxProposalsPerElection,
            "Proposal limit hit"
        );

        electionMetadata.validProposals[_tokenAddr] = true;
        electionMetadata.proposals[_tokenAddr].proposer = msg.sender;
        electionMetadata.proposals[_tokenAddr].createdAt = block.number;
        electionMetadata.proposedTokens.push(_tokenAddr);

        emit ProposalCreated(_electionIdx, _tokenAddr);
    }

    function vote(uint16 _electionIdx, address _tokenAddr, uint256 _amt) public {
        require(
            vPumpToken.allowance(msg.sender, address(this)) >= _amt,
            "vPUMP transfer not approved"
        );
        require(
            _electionIdx == currElectionIdx,
            "Must use currElectionIdx"
        );
        Election storage electionMetadata = elections[currElectionIdx];
        require(
            block.number <= electionMetadata.votingEndBlock,
            "Voting has already ended"
        );
        require(
            electionMetadata.validProposals[_tokenAddr],
            "Must be valid proposal"
        );
        BuyProposal storage proposal = electionMetadata.proposals[_tokenAddr];
        proposal.votes[msg.sender] += _amt;
        proposal.totalVotes += _amt;
        vPumpToken.transferFrom(msg.sender, address(this), _amt);

        emit BuyVoteDeposited(_electionIdx, _tokenAddr, _amt);
    }

    function withdrawVote(uint16 _electionIdx, address _tokenAddr, uint256 _amt) public {
        Election storage electionMetadata = elections[_electionIdx];
        require(
            electionMetadata.validProposals[_tokenAddr],
            "Must be valid proposal"
        );
        BuyProposal storage proposal = electionMetadata.proposals[_tokenAddr];
        require(
            proposal.votes[msg.sender] >= _amt,
            "More votes than cast"
        );
        proposal.votes[msg.sender] -= _amt;
        proposal.totalVotes -= _amt;
        vPumpToken.transfer(msg.sender, _amt);

        emit BuyVoteWithdrawn(_electionIdx, _tokenAddr, _amt);
    }

    function declareWinner(uint16 _electionIdx) public {
        require(
            _electionIdx == currElectionIdx,
            "Must be currElectionIdx"
        );
        Election storage electionMetadata = elections[currElectionIdx];
        require(
            block.number >= electionMetadata.winnerDeclaredBlock,
            "Voting not finished"
        );

        // If no proposals were made, the default proposal wins
        address winningToken = electionMetadata.proposedTokens[0];
        uint256 winningVotes = electionMetadata.proposals[winningToken].totalVotes;
        // election grows too large this for loop could fully exhaust the maximum per tx gas meaning
        // it would be impossible for a call to getWinner to succeed.
        for (uint256 i = 0; i < electionMetadata.proposedTokens.length; i++) {
            address tokenAddr = electionMetadata.proposedTokens[i];
            BuyProposal storage proposal = electionMetadata.proposals[tokenAddr];
            if (proposal.totalVotes > winningVotes) {
                winningToken = tokenAddr;
                winningVotes = proposal.totalVotes;
            }
        }

        electionMetadata.winnerDeclared = true;
        electionMetadata.winner = winningToken;
        currElectionIdx += 1;
        Election storage nextElection = elections[currElectionIdx];
        nextElection.votingStartBlock = electionMetadata.winnerDeclaredBlock + 1;
        nextElection.votingEndBlock = electionMetadata.winnerDeclaredBlock + electionLength - winnerDelay;
        nextElection.winnerDeclaredBlock = electionMetadata.winnerDeclaredBlock + electionLength;
        // Setup the default proposal
        nextElection.validProposals[defaultProposal] = true;
        nextElection.proposals[defaultProposal].proposer = address(this);
        nextElection.proposals[defaultProposal].createdAt = block.number;
        nextElection.proposedTokens.push(defaultProposal);

        emit WinnerDeclared(_electionIdx, winningToken, winningVotes);
    }

    function voteSell(uint16 _electionIdx, uint256 _amt) public {
        require(
            vPumpToken.allowance(msg.sender, address(this)) >= _amt,
            "vPUMP transfer not approved"
        );
        Election storage electionData = elections[_electionIdx];
        require(electionData.sellProposalActive, "SellProposal not active");

        electionData.sellVotes[msg.sender] += _amt;
        electionData.sellProposalTotalVotes += _amt;
        vPumpToken.transferFrom(msg.sender, address(this), _amt);

        emit SellVoteDeposited(_electionIdx, electionData.winner, _amt);
    }

    function withdrawSellVote(uint16 _electionIdx, uint256 _amt) public {
        Election storage electionData = elections[_electionIdx];
        require(
            electionData.sellVotes[msg.sender] >= _amt,
            "More votes than cast"
        );

        electionData.sellVotes[msg.sender] -= _amt;
        electionData.sellProposalTotalVotes -= _amt;
        vPumpToken.transfer(msg.sender, _amt);

        emit SellVoteWithdrawn(_electionIdx, electionData.winner, _amt);
    }

    function executeBuyProposal(uint16 _electionIdx) public returns (bool) {
        Election storage electionData = elections[_electionIdx];
        require(electionData.winnerDeclared, "Winner not declared");
        require(electionData.numBuysMade < maxNumBuys, "Can't exceed maxNumBuys");
        require(electionData.nextValidBuyBlock <= block.number, "Must wait before executing");
        require(electionData.numFailures < maxBuyFailures, "Max fails exceeded");
        require(!electionData.sellProposalActive, "Sell Proposal already active");

        try treasury.buyProposedToken(electionData.winner) returns (uint256 _purchasedAmt) {
            electionData.purchasedAmt += _purchasedAmt;
            electionData.numBuysMade += 1;
            electionData.nextValidBuyBlock = block.number + buyCooldownBlocks;
            // If we've now made the max number of buys, mark the associatedSellProposal
            // as active and mark the amount of accumulated hilding token
            if (electionData.numBuysMade >= maxNumBuys) {
                electionData.sellProposalActive = true;
                electionData.sellProposalCreatedAt = block.number;
            }
            return true;
        } catch Error(string memory) {
            electionData.numFailures += 1;
            // If we've exceeded the number of allowed failures
            if (electionData.numFailures >= maxBuyFailures) {
                electionData.sellProposalActive = true;
                electionData.sellProposalCreatedAt = block.number;
            }
            return false;
        }

        // This return is never hit and is a hack to appease IDE sol static analyzer
        return true;
    }

    function executeSellProposal(uint16 _electionIdx) public {
        Election storage electionData = elections[_electionIdx];
        require(electionData.sellProposalActive, "SellProposal not active");
        uint256 requiredVotes = _getRequiredSellVPump(electionData.sellProposalCreatedAt);
        require(electionData.sellProposalTotalVotes >= requiredVotes, "Not enough votes to execute");

        treasury.sellProposedToken(electionData.winner, electionData.purchasedAmt);
        // After we've sold, mark the sell proposal as inactive so we don't sell again
        electionData.sellProposalActive = false;
        emit SellProposalExecuted(_electionIdx);
    }

    function getActiveProposals() public view returns (address[] memory) {
        return elections[currElectionIdx].proposedTokens;
    }

    function getProposal(
        uint16 _electionIdx,
        address _tokenAddr
    ) public view returns (BuyProposalMetadata memory) {
        require(
            elections[currElectionIdx].validProposals[_tokenAddr],
            "No valid proposal for args"
        );
        BuyProposal storage proposal = elections[_electionIdx].proposals[_tokenAddr];
        return BuyProposalMetadata({
        proposer: proposal.proposer,
        createdAt: proposal.createdAt,
        totalVotes: proposal.totalVotes
        });
    }

    function getElectionMetadata(
        uint16 _electionIdx
    ) public view returns (ElectionMetadata memory) {
        require(_electionIdx <= currElectionIdx, "Can't query future election");
        Election storage election = elections[_electionIdx];
        return ElectionMetadata({
        votingStartBlock: election.votingStartBlock,
        votingEndBlock: election.votingEndBlock,
        winnerDeclaredBlock: election.winnerDeclaredBlock,
        winnerDeclared: election.winnerDeclared,
        winner: election.winner,
        numBuysMade: election.numBuysMade,
        nextValidBuyBlock: election.nextValidBuyBlock,
        numFailures: election.numFailures,
        sellProposalActive: election.sellProposalActive,
        sellProposalTotalVotes: election.sellProposalTotalVotes,
        sellProposalCreatedAt: election.sellProposalCreatedAt
        });
    }

    function _getRequiredSellVPump(uint256 _startBlock) public view returns (uint256) {
        uint256 outstandingVPump = vPumpToken.totalSupply();
        uint256 elapsedBlocks = block.number - _startBlock;
        if (elapsedBlocks <= sellLockupBlocks) {
            return outstandingVPump;
        }
        uint256 decayPeriodBlocks = elapsedBlocks - sellLockupBlocks;
        return _appxDecay(outstandingVPump, decayPeriodBlocks, sellHalfLifeBlocks);
    }

    function _appxDecay(
        uint256 _startValue,
        uint256 _elapsedTime,
        uint256 _halfLife
    ) internal view returns (uint256) {
        uint256 ret = _startValue >> (_elapsedTime / _halfLife);
        ret -= ret * (_elapsedTime % _halfLife) / _halfLife / 2;
        return ret;
    }
}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8;

import "./lib/SafeMath.sol";
import "./lib/SafeBEP20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "./PumpToken.sol";
import "./vPumpToken.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


contract PoolManager is Ownable, ReentrancyGuard, Initializable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    // Info of each user.
    struct UserInfo {
        uint256 amount;         // How many LP tokens the user has provided.
        uint256 rewardDebt;     // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of PUMP
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accPumpPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accPumpPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. PUMP to distribute per block.
        uint256 lastRewardBlock;  // Last block number that PUMP distribution occurs.
        uint256 accPumpPerShare;   // Accumulated PUMP per share, times 1e12. See below.
    }

    PumpToken public pumpToken;
    VPumpToken public vPumpToken;
    address public devAddr;
    uint256 public pumpPerBlock;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when PUMP mining starts.
    uint256 public startBlock;
    mapping(IBEP20 => bool) public poolExistence;

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event SetFeeAddress(address indexed user, address indexed newAddress);
    event SetDevAddress(address indexed user, address indexed newAddress);
    event UpdateEmissionRate(address indexed user, uint256 goosePerBlock);

    function initialize(
        PumpToken _pumpToken,
        VPumpToken _vPumpToken,
        address _devAddr,
        uint256 _pumpPerBlock,
        uint256 _startBlock
    ) public initializer {
        pumpToken = _pumpToken;
        vPumpToken = _vPumpToken;
        devAddr = _devAddr;
        pumpPerBlock = _pumpPerBlock;
        startBlock = _startBlock;
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // View function to see pending PUMP on frontend.
    function pendingPump(uint256 _pid, address _user) external view returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accPumpPerShare = pool.accPumpPerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 numElapsedBlocks = block.number.sub(pool.lastRewardBlock);
            uint256 pumpReward = numElapsedBlocks.mul(pumpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accPumpPerShare = accPumpPerShare.add(pumpReward.mul(1e12).div(lpSupply));
        }
        uint256 ret = user.amount.mul(accPumpPerShare).div(1e12).sub(user.rewardDebt);
        return ret;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    function add(uint256 _allocPoint, IBEP20 _lpToken, bool _withUpdate) public onlyOwner {
        require(poolExistence[_lpToken] == false, "nonDuplicated: duplicated");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolExistence[_lpToken] = true;
        poolInfo.push(PoolInfo({
            lpToken : _lpToken,
            allocPoint : _allocPoint,
            lastRewardBlock : lastRewardBlock,
            accPumpPerShare : 0
        }));
    }

    // Update the given pool's PUMP allocation point and deposit fee. Can only be called by the owner.
    function set(uint256 _pid, uint256 _allocPoint, bool _withUpdate) public onlyOwner {
        if (_withUpdate) {
            massUpdatePools();
        }
        totalAllocPoint = totalAllocPoint.sub(poolInfo[_pid].allocPoint).add(_allocPoint);
        poolInfo[_pid].allocPoint = _allocPoint;
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0 || pool.allocPoint == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 numElapsedBlocks = block.number.sub(pool.lastRewardBlock);
        uint256 pumpReward = numElapsedBlocks.mul(pumpPerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        pool.accPumpPerShare = pool.accPumpPerShare.add(pumpReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // Deposit LP tokens to PoolManager for PUMP allocation.
    function deposit(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accPumpPerShare).div(1e12).sub(user.rewardDebt);
            if (pending > 0) {
                safePumpTransfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), _amount);
            // mint vPump and send to the depositor. Used for governance
            vPumpToken.mint(msg.sender, _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPumpPerShare).div(1e12);
        emit Deposit(msg.sender, _pid, _amount);
    }

    function withdraw(uint256 _pid, uint256 _amount) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        require(user.amount >= _amount, "withdraw: not good");
        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accPumpPerShare).div(1e12).sub(user.rewardDebt);
        if (pending > 0) {
            safePumpTransfer(msg.sender, pending);
        }
        if (_amount > 0) {
            user.amount = user.amount.sub(_amount);
            pool.lpToken.safeTransfer(address(msg.sender), _amount);
            vPumpToken.burn(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(pool.accPumpPerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, _amount);
    }

    //Pancake has to add hidden dummy pools inorder to alter the emission, make it simple and transparent to all.
    function updateEmissionRate(uint256 _pumpPerBlock) public onlyOwner {
        massUpdatePools();
        pumpPerBlock = _pumpPerBlock;
        emit UpdateEmissionRate(msg.sender, _pumpPerBlock);
    }

    // Update dev address by the previous dev.
    function dev(address _devAddr) public {
        require(msg.sender == devAddr, "dev: wut?");
        devAddr = _devAddr;
        emit SetDevAddress(msg.sender, _devAddr);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) public nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 amount = user.amount;
        user.amount = 0;
        user.rewardDebt = 0;
        pool.lpToken.safeTransfer(address(msg.sender), amount);
        emit EmergencyWithdraw(msg.sender, _pid, amount);
    }

    // Safe pump transfer function, just in case if rounding error causes pool to not have enough PUMP
    function safePumpTransfer(address _to, uint256 _amount) internal {
        uint256 pumpBal = pumpToken.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > pumpBal) {
            transferSuccess = pumpToken.transfer(_to, pumpBal);
        } else {
            transferSuccess = pumpToken.transfer(_to, _amount);
        }
        require(transferSuccess, "transfer failed");
    }

}
// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./lib/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract PumpToken is Ownable, Initializable {
    using SafeMath for uint256;

    string public symbol = "PUMP";
    string public name = "Pump Token";
    uint256 public decimals = 18;
    uint256 public totalSupply = 100 * 10**6 * 10**18;
    address public cannonAddr;
    address public electionManagerAddr;

    // Stores addresses that are excluded from cannonTax
    // This includes any proposal contract & the 0xDEAD wallet
    mapping(address => bool) private _cannonTaxExcluded;
    // Percent of transaction that goes to cannon
    uint256 public cannonTax = 3;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;

    event Transfer(address indexed from, address to, uint256 value);
    event Approval(address owner, address spender, uint256 value);

    function initialize() public initializer {
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    /**
        @notice Approve an address to spend the specified amount of tokens on behalf of msg.sender
        @dev Beware that changing an allowance with this method brings the risk that someone may use both the old
             and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
             race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
             https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        @param _spender The address which will spend the funds.
        @param _value The amount of tokens to be spent.
        @return Success boolean
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
        @notice Transfer tokens from one address to another
        @param _from The address which you want to send tokens from
        @param _to The address which you want to transfer to
        @param _value The amount of tokens to be transferred
        @return Success boolean
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    ) public returns (bool) {
        require(allowed[_from][msg.sender] >= _value, "Insufficient allowance");
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        _transfer(_from, _to, _value);
        return true;
    }

    /**
        @notice Transfer tokens to a specified address
        @param _to The address to transfer to
        @param _value The amount to be transferred
        @return Success boolean
     */
    function transfer(address _to, uint256 _value) public returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
        @notice Set the address of the PumpCannon
        @param _cannonAddr The PumpCannon's address
     */
    function setCannonAddress(address _cannonAddr) public onlyOwner {
        cannonAddr = _cannonAddr;
    }

    /**
        @notice Exclude a specific address from all future cannon taxes
        @param _addrToExclude The address to exclude
     */
    function excludeAddress(address _addrToExclude) public {
        require(
            msg.sender == owner() || msg.sender == electionManagerAddr,
            "Not approved to exclude"
        );
        _cannonTaxExcluded[_addrToExclude] = true;
    }

    /**
        @notice Set the address of the ElectionManager
        @param _electionManagerAddr the ElectionManager's address
     */
    function setElectionManagerAddr(address _electionManagerAddr)
        public
        onlyOwner
    {
        electionManagerAddr = _electionManagerAddr;
    }

    /**
        @notice Getter to check the current balance of an address
        @param _owner Address to query the balance of
        @return Token balance
     */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    /**
        @notice Getter to check the amount of tokens that an owner allowed to a spender
        @param _owner The address which owns the funds
        @param _spender The address which will spend the funds
        @return The amount of tokens still available for the spender
     */
    function allowance(address _owner, address _spender)
        public
        view
        returns (uint256)
    {
        return allowed[_owner][_spender];
    }

    /** shared logic for transfer and transferFrom */
    function _transfer(
        address _from,
        address _to,
        uint256 _value
    ) internal {
        require(balances[_from] >= _value, "Insufficient balance");
        (uint256 _valueLessTax, uint256 tax) = _calculateTransactionTax(
            _from,
            _to,
            _value
        );

        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_valueLessTax);
        emit Transfer(_from, _to, _valueLessTax);

        if (tax > 0) {
            balances[cannonAddr] = balances[cannonAddr] + tax;
            emit Transfer(_from, cannonAddr, tax);
        }
    }

    function _calculateTransactionTax(
        address _from,
        address _to,
        uint256 _value
    ) internal returns (uint256, uint256) {
        // Excluded addresses are excluded regardless of if they are sending
        // or receiving PUMP. This is to prevent the act of voting from costing
        // the voter PUMP.
        if (_cannonTaxExcluded[_from] || _cannonTaxExcluded[_to]) {
            return (_value, 0);
        }
        uint256 taxAmount = _value.mul(cannonTax).div(10**2);
        return (_value - taxAmount, taxAmount);
    }
}
pragma solidity ^0.8.0;
pragma abicoder v2;

// SPDX-License-Identifier: MIT

import "./ElectionManager.sol";
import "./PumpToken.sol";
import "./lib/SafeBEP20.sol";
import "@pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancake-swap-periphery/contracts/interfaces/IPancakeRouter02.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";

contract PumpTreasury is Ownable, Initializable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    PumpToken public pumpToken;
    IPancakeRouter02 public pancakeRouter;
    IBEP20 public wBNB;
    address public electionMangerAddr;

    event TreasurySwap(address _caller, uint256 _amount);
    event BuyProposedToken(address _tokenAddress, uint256 _wBNBAmt);
    event SellAndStake(address _tokenSold, uint256 _pumpStaked, uint256 _bnbStaked);

    modifier onlyElectionManager() {
        require(electionMangerAddr == msg.sender, "Caller is not ElectionManager");
        _;
    }

    function initialize(
        PumpToken _pumpToken,
        address _wBNBAddr,
        address _pancakeRouterAddr
    ) public initializer {
        pumpToken = _pumpToken;
        pancakeRouter = IPancakeRouter02(_pancakeRouterAddr);
        wBNB = IBEP20(_wBNBAddr);
    }

    function setElectionManagerAddress(address _addr) public onlyOwner {
        electionMangerAddr = _addr;
    }

    function swapPumpForBNB(uint256 _amount) public {
        emit TreasurySwap(msg.sender, _amount);
        _performSwap(address(pumpToken), address(wBNB), _amount);
    }

    function buyProposedToken(address _tokenAddr) public onlyElectionManager returns (uint256) {
        // Each buy uses 1% of the available treasury
        uint256 buySize = wBNB.balanceOf(address(this)) / 100;

        uint256 startingAmt = IBEP20(_tokenAddr).balanceOf(address(this));
        _performSwap(address(wBNB), _tokenAddr, buySize);
        uint256 endingAmt = IBEP20(_tokenAddr).balanceOf(address(this));
        emit BuyProposedToken(_tokenAddr, buySize);

        return endingAmt - startingAmt;
    }

    function sellProposedToken(address _tokenAddr, uint256 _amt) public onlyElectionManager {
        // First sell the position and record how much BNB we receive for it
        uint256 initialBalance = address(this).balance;
        _performSwap(_tokenAddr, address(wBNB), _amt);
        uint256 newBalance = address(this).balance;
        uint256 receivedBNB = newBalance - initialBalance;

        // Now, use half the BNB to buy PUMP -- also recording how much PUMP we receive
        uint256 initialPump = pumpToken.balanceOf(address(this));
        _performSwap(address(wBNB), address(pumpToken), receivedBNB / 2);
        uint256 newPump = pumpToken.balanceOf(address(this));
        uint256 receivedPump = newPump - initialPump;

        // Now stake the received PUMP against the remaining BNB
        _addPumpLiquidity(receivedPump, receivedBNB / 2);
        emit SellAndStake(_tokenAddr, receivedPump, receivedBNB / 2);
    }

    function _addPumpLiquidity(uint256 _pumpAmount, uint256 _bnbAmount) internal {
        // add the liquidity
        pancakeRouter.addLiquidityETH{value: _bnbAmount}(
            address(pumpToken),
            _pumpAmount,
            0, // slippage is unavoidable
            0, // slippage is unavoidable
            address(this),
            block.timestamp
        );
    }


    function _performSwap(
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal {
        IBEP20(tokenIn).approve(address(pancakeRouter), amount);
        address[] memory path = new address[](2);
        path[0] = tokenIn;
        path[1] = tokenOut;
        pancakeRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(
            amount, // amountIn
            0, // amountOutMin -- slippage here is unavoidable, no use adding min
            path, // path
            address(this), // to
            block.timestamp // deadline
        );
    }
}
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./lib/SafeMath.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/utils/Initializable.sol";


contract VPumpToken is Ownable, Initializable {
    using SafeMath for uint256;

    string public symbol = "VPUMP";
    string public name = "Voting Pump";
    uint256 public decimals = 18;
    uint256 public totalSupply = 0;
    address public canMintBurn;
    address public electionManager;


    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowed;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

   modifier onlyCanMintBurn {
      require(msg.sender == canMintBurn, "Must have mintBurn role");
      _;
   }

   function initialize() public initializer {
        canMintBurn = msg.sender;
        balances[msg.sender] = totalSupply;
        emit Transfer(address(0), msg.sender, totalSupply);
    }

    function setCanMintBurn(address _canMintBurn) public onlyOwner {
        canMintBurn = _canMintBurn;
    }

    function setElectionManagerAddress(address _electionManager) public onlyOwner {
        electionManager = _electionManager;
    }

    /**
        @notice Approve an address to spend the specified amount of tokens on behalf of msg.sender
        @dev Beware that changing an allowance with this method brings the risk that someone may use both the old
             and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
             race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
             https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
        @param _spender The address which will spend the funds.
        @param _value The amount of tokens to be spent.
        @return Success boolean
     */
    function approve(address _spender, uint256 _value) public returns (bool) {
        allowed[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }

    /**
        @notice Transfer tokens to a specified address
        @param _to The address to transfer to
        @param _value The amount to be transferred
        @return Success boolean
     */
    function transfer(address _to, uint256 _value) public returns (bool) {
        _transfer(msg.sender, _to, _value);
        return true;
    }

    /**
        @notice Transfer tokens from one address to another
        @param _from The address which you want to send tokens from
        @param _to The address which you want to transfer to
        @param _value The amount of tokens to be transferred
        @return Success boolean
     */
    function transferFrom(
        address _from,
        address _to,
        uint256 _value
    )
        public
        returns (bool)
    {
        require(allowed[_from][msg.sender] >= _value, "Insufficient allowance");
        allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
        _transfer(_from, _to, _value);
        return true;
    }

    function mint(address _to, uint256 _value) public onlyCanMintBurn returns (bool) {
        totalSupply = totalSupply.add(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(address(0), _to, _value);
        return true;
    }

    function burn(address _from, uint256 _value) public onlyCanMintBurn returns(bool) {
        require(balances[_from] >= _value, "Insufficient balance");
        totalSupply = totalSupply.sub(_value);
        balances[_from] = balances[_from].sub(_value);
        emit Transfer(_from, address(0), _value);
        return true;
    }

    /**
        @notice Getter to check the current balance of an address
        @param _owner Address to query the balance of
        @return Token balance
     */
    function balanceOf(address _owner) public view returns (uint256) {
        return balances[_owner];
    }

    /**
        @notice Getter to check the amount of tokens that an owner allowed to a spender
        @param _owner The address which owns the funds
        @param _spender The address which will spend the funds
        @return The amount of tokens still available for the spender
     */
    function allowance(
        address _owner,
        address _spender
    )
    public
    view
    returns (uint256)
    {
        return allowed[_owner][_spender];
    }

    /** shared logic for transfer and transferFrom */
    // Note: _vPump is deliberately non-transferable unless it is to or from the electionManager contract
    // this is to avoid secondary markets from popping up
    function _transfer(address _from, address _to, uint256 _value) internal {
        require(balances[_from] >= _value, "Insufficient balance");
        require(_from == electionManager || _to == electionManager, "Only transfer electionManager");
        balances[_from] = balances[_from].sub(_value);
        balances[_to] = balances[_to].add(_value);
        emit Transfer(_from, _to, _value);
    }
}

