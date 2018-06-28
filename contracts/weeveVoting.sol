pragma solidity ^0.4.24;

import "./libraries/DLL.sol";
import "./libraries/AttributeStore.sol";
import "./libraries/SafeMath.sol";

// Modified version of the PLCR voting scheme by Mike Goldin (ConsenSys)
// https://github.com/ConsenSys/PLCRVoting

contract weeveVoting {

    using AttributeStore for AttributeStore.Data;
    using DLL for DLL.Data;
    using SafeMath for uint;

    struct Poll {
        address initiatingContract;
        uint256 commitEndDate;
        uint256 revealEndDate;
        uint256 voteQuorum;	    /// number of votes required for a proposal to pass
        uint256 votesFor;		    /// tally of votes supporting proposal
        uint256 votesAgainst;      /// tally of votes countering proposal
        uint256 votesUnrevealed;
        uint256 endTokensFor;
        uint256 endTokensAgainst;
        bool isResolved;
        mapping(address => bool) didCommit;  /// indicates whether an address committed a vote for this poll
        mapping(address => bool) didReveal;   /// indicates whether an address revealed a vote for this poll
    }

    // address of the weeve Factory
    address public weeveFactoryAddress = 0x0000000000000000000000000000000000000000;
    
    // maps the addresses of contracts that are allowed to call this contracts functions
    mapping (address => bool) weeveContracts;

    // nonce of the current poll
    uint256 constant public INITIAL_POLL_NONCE = 0;
    uint256 public pollNonce;

    // maps pollID to Poll struct
    mapping(uint256 => Poll) public pollMap; 

    // maps users addresses to their doubly-linked list of pollIDs
    mapping(address => DLL.Data) dllMap;

    // attribute store fot the users vote hashes and number of tTokens per vote
    AttributeStore.Data store;

    constructor() public {
        pollNonce = INITIAL_POLL_NONCE;
    }

    // Adding a new contracts address that will be allowed to use this contract    
    function addWeeveContract(address _newContract) public {
        require(msg.sender == weeveFactoryAddress);
        weeveContracts[_newContract] = true;
    }
    
    // Removing a contracts address that won't be allowed to use this contract anymore
    function removeWeeveContract(address _obsoleteContract) public {
        require(msg.sender == weeveFactoryAddress);
        weeveContracts[_obsoleteContract] = false;
    }

    // Unlocks tokens locked in unrevealed vote where poll has ended
    //function rescueTokens(uint256 _pollID) public {
    //    require(isExpired(pollMap[_pollID].revealEndDate));
    //    require(dllMap[msg.sender].contains(_pollID));
    //
    //    dllMap[msg.sender].remove(_pollID);
    //}

    // Unlocks tokens locked in unrevealed votes where polls have ended
    //function rescueTokensInMultiplePolls(uint[] _pollIDs) public {
    //    // loop through arrays, rescuing tokens from all
    //    for (uint256 i = 0; i < _pollIDs.length; i++) {
    //        rescueTokens(_pollIDs[i]);
    //    }
    //}

    // Commits vote using hash of choice and secret salt to conceal vote until reveal
    function commitVote(uint256 _pollID, address _address, bytes32 _secretHash, uint256 _numTokens, uint256 _prevPollID) public calledByWeeveContract(msg.sender) returns (bool) {
        require(_pollID != 0);
        require(commitPeriodActive(_pollID));
        require(!didCommit(_address, _pollID));

        // Can't vote with zero tokens
        require(_numTokens > 0);

        // prevent user from committing a secretHash of 0
        require(_secretHash != 0);

        // Check if _prevPollID exists in the user's DLL or if _prevPollID is 0
        require(_prevPollID == 0 || dllMap[_address].contains(_prevPollID));
        uint256 nextPollID = dllMap[_address].getNext(_prevPollID);

        // edge case: in-place update
        if (nextPollID == _pollID) {
            nextPollID = dllMap[_address].getNext(_pollID);
        }

        require(validPosition(_prevPollID, nextPollID, _address, _numTokens));
        dllMap[_address].insert(_prevPollID, _pollID, nextPollID);

        bytes32 UUID = attrUUID(_address, _pollID);

        store.setAttribute(UUID, "numTokens", _numTokens);
        store.setAttribute(UUID, "commitHash", uint(_secretHash));

        pollMap[_pollID].didCommit[_address] = true;

        // Adding the number of tokens to the count of unrevealed tokens
        pollMap[_pollID].votesUnrevealed = pollMap[_pollID].votesUnrevealed.add(_numTokens);
        
        return true;
    }

    // Commits votes using hashes of choices and secret salts to conceal votes until reveal
    function commitVotes(uint[] _pollIDs, address _address, bytes32[] _secretHashes, uint[] _numsTokens, uint[] _prevPollIDs) external calledByWeeveContract(msg.sender) returns(bool) {
        // make sure the array lengths are all the same
        require(_pollIDs.length == _secretHashes.length);
        require(_pollIDs.length == _numsTokens.length);
        require(_pollIDs.length == _prevPollIDs.length);

        // loop through arrays, committing each individual vote values
        for (uint i = 0; i < _pollIDs.length; i++) {
            require(commitVote(_pollIDs[i], _address, _secretHashes[i], _numsTokens[i], _prevPollIDs[i]));
        }

        return true;
    }

    // Compares previous and next poll's committed tokens for sorting purposes
    function validPosition(uint256 _prevID, uint256 _nextID, address _voter, uint256 _numTokens) public view returns (bool valid) {
        bool prevValid = (_numTokens >= getNumTokens(_voter, _prevID));
        // if next is zero node, _numTokens does not need to be greater
        bool nextValid = (_numTokens <= getNumTokens(_voter, _nextID) || _nextID == 0);
        return prevValid && nextValid;
    }

    // Reveals vote with choice and secret salt used in generating commitHash to attribute committed tokens
    function revealVote(uint256 _pollID, address _address, uint256 _voteOption, uint256 _salt) public calledByWeeveContract(msg.sender) returns(bool) {
        // Make sure the reveal period is active
        require(revealPeriodActive(_pollID));
        require(pollMap[_pollID].didCommit[_address]);
        require(!pollMap[_pollID].didReveal[_address]);

        // compare resultant hash from inputs to original commitHash
        require(keccak256(abi.encodePacked(_voteOption, _salt)) == getCommitHash(_address, _pollID));

        uint256 numTokens = getNumTokens(_address, _pollID);

        // remove the users tokens from the unrevealed tokens
        pollMap[_pollID].votesUnrevealed = pollMap[_pollID].votesUnrevealed.sub(numTokens);
        
        // add the tokens to the according counter
        if (_voteOption == 1) {
            pollMap[_pollID].votesFor = pollMap[_pollID].votesFor.add(numTokens);
        } else {
            pollMap[_pollID].votesAgainst = pollMap[_pollID].votesAgainst.add(numTokens);
        }

        // remove the node referring to this vote upon reveal
        dllMap[_address].remove(_pollID);
        pollMap[_pollID].didReveal[_address] = true;

        return true;
    }

    // Reveals multiple votes with choices and secret salts used in generating commitHashes to attribute committed tokens
    function revealVotes(uint[] _pollIDs, address _address, uint[] _voteOptions, uint[] _salts) external calledByWeeveContract(msg.sender) returns(bool) {
        // make sure the array lengths are all the same
        require(_pollIDs.length == _voteOptions.length);
        require(_pollIDs.length == _salts.length);

        // loop through arrays, revealing each individual vote values
        for (uint i = 0; i < _pollIDs.length; i++) {
            require(revealVote(_pollIDs[i], _address, _voteOptions[i], _salts[i]));
        }
        
        return true;
    }

    // Resolves a vote: calculated the endToken count for the payout of participants
    function resolveVote(uint256 _pollID, uint256 _securityDeposit) external calledByWeeveContract(msg.sender) returns(bool votePassed) {
        require(pollEnded(_pollID));

        // Adds the tokens of the ones who did not vote according what was the right decision to the ones who did not reveal their vote in time
        // Also adds the security deposit of the challenged entitiy if the vote passed
        if(isPassed(_pollID)) {
            pollMap[_pollID].endTokensFor = pollMap[_pollID].votesFor;
            pollMap[_pollID].endTokensAgainst = pollMap[_pollID].votesAgainst.add(pollMap[_pollID].votesUnrevealed).add(_securityDeposit);
        } else {
            pollMap[_pollID].endTokensAgainst = pollMap[_pollID].votesAgainst;
            pollMap[_pollID].endTokensFor = pollMap[_pollID].votesFor.add(pollMap[_pollID].votesUnrevealed);
        }

        pollMap[_pollID].isResolved = true;
        
        return isPassed(_pollID);
    }
    
    // Allowing users who voted according to what the right decision was to claim their "reward" after the vote ended
    function claimReward(uint256 _pollID, uint256 _voteOption, address _address, uint256 _stakedTokens) public view calledByWeeveContract(msg.sender) returns(uint256 reward) {
        // vote needs to be resolved and only users who revealed their vote
        require(pollMap[_pollID].isResolved);
        require(didReveal(_address, _pollID));

        uint256 rightOption = isPassed(_pollID) ? 1 : 0;
        
        // only users who voted for the winning option 
        require(_voteOption == rightOption);

        // calculcate the reward (their tokens plus their share of the tokens of the losing side)
        reward = _stakedTokens;
        if(isPassed(_pollID) && pollMap[_pollID].endTokensAgainst > 0) {
            reward = reward.add((reward.mul(pollMap[_pollID].endTokensAgainst)).div(pollMap[_pollID].endTokensFor));
        } else if(!isPassed(_pollID) && pollMap[_pollID].endTokensFor > 0) {
            reward = reward.add((reward.mul(pollMap[_pollID].endTokensFor)).div(pollMap[_pollID].endTokensAgainst));
        }

        return reward;
    }
    
    // returns the number of tokens that a voter has used in a specific vote
    function getNumPassingTokens(address _voter, uint256 _pollID, uint256 _salt) public view returns (uint256 correctVotes) {
        require(pollEnded(_pollID));
        require(pollMap[_pollID].didReveal[_voter]);

        uint256 winningChoice = isPassed(_pollID) ? 1 : 0;
        bytes32 winnerHash = keccak256(abi.encodePacked(winningChoice, _salt));
        bytes32 commitHash = getCommitHash(_voter, _pollID);

        require(winnerHash == commitHash);

        return getNumTokens(_voter, _pollID);
    }

    // Initiates a vote with canonical configured parameters
    function startPoll(uint256 _voteQuorum, uint256 _commitDuration, uint256 _revealDuration) public calledByWeeveContract(msg.sender) returns (uint256 pollID) {
        pollNonce = pollNonce.add(1);

        uint256 commitEndDate = block.timestamp.add(_commitDuration);
        uint256 revealEndDate = commitEndDate.add(_revealDuration);

        pollMap[pollNonce] = Poll({
            initiatingContract: msg.sender,
            voteQuorum: _voteQuorum,
            commitEndDate: commitEndDate,
            revealEndDate: revealEndDate,
            votesFor: 0,
            votesAgainst: 0,
            votesUnrevealed: 0,
            endTokensFor: 0,
            endTokensAgainst: 0,
            isResolved: false
        });
        
        return pollNonce;
    }

    // Determines if vote has passed
    function isPassed(uint256 _pollID) public view returns (bool passed) {
        require(pollEnded(_pollID));

        Poll memory poll = pollMap[_pollID];
        return (100 * poll.votesFor) > (poll.voteQuorum * (poll.votesFor + poll.votesAgainst));
    }
    
    // Determines if a vote is resolved
    function isResolved(uint256 _pollID) public view returns (bool resolved) {
        return pollMap[_pollID].isResolved;
    }

    // Voting-Helper functions

    // Returns the total number of tokens that voted for the winnig option
    function getTotalNumberOfTokensForWinningOption(uint256 _pollID) public view returns (uint256 numTokens) {
        require(pollEnded(_pollID));

        if (isPassed(_pollID))
            return pollMap[_pollID].votesFor;
        else
            return pollMap[_pollID].votesAgainst;
    }

    // Determines if vote is over
    function pollEnded(uint256 _pollID) public view returns (bool ended) {
        require(pollExists(_pollID));

        return isExpired(pollMap[_pollID].revealEndDate);
    }

    // Checks if an expiration date has been reached
    function isExpired(uint256 _terminationDate) public view returns (bool expired) {
        return (block.timestamp > _terminationDate);
    }

    // Checks if the commit period is still active for the specified vote
    function commitPeriodActive(uint256 _pollID) public view returns (bool active) {
        require(pollExists(_pollID));

        return !isExpired(pollMap[_pollID].commitEndDate);
    }

    // Checks if the reveal period is still active for the specified vote
    function revealPeriodActive(uint256 _pollID) public view returns (bool active) {
        require(pollExists(_pollID));

        return !isExpired(pollMap[_pollID].revealEndDate) && !commitPeriodActive(_pollID);
    }

    // Checks if user has committed for specified vote
    function didCommit(address _voter, uint256 _pollID) public view returns (bool committed) {
        require(pollExists(_pollID));

        return pollMap[_pollID].didCommit[_voter];
    }

    // Checks if user has revealed for specified vote
    function didReveal(address _voter, uint256 _pollID) public view returns (bool revealed) {
        require(pollExists(_pollID));

        return pollMap[_pollID].didReveal[_voter];
    }

    // Checks if a vote exists
    function pollExists(uint256 _pollID) public view returns (bool exists) {
        return (_pollID != 0 && _pollID <= pollNonce);
    }

    // Doubly-linked list helpers

    // Gets the bytes32 commitHash property of target vote
    function getCommitHash(address _voter, uint256 _pollID) public view returns (bytes32 commitHash) {
        return bytes32(store.getAttribute(attrUUID(_voter, _pollID), "commitHash"));
    }

    // Wrapper for getAttribute with attrName="numTokens"
    function getNumTokens(address _voter, uint256 _pollID) public view returns (uint256 numTokens) {
        return store.getAttribute(attrUUID(_voter, _pollID), "numTokens");
    }

    // Gets top element of sorted poll-linked-list
    function getLastNode(address _voter) public view returns (uint256 pollID) {
        return dllMap[_voter].getPrev(0);
    }

    // Gets the numTokens property of getLastNode
    function getLockedTokens(address _voter) public view returns (uint256 numTokens) {
        return getNumTokens(_voter, getLastNode(_voter));
    }

    // Takes the last node in the user's DLL and iterates backwards through the list searching
    // for a node with a value less than or equal to the provided _numTokens value. When such a node
    // is found, if the provided _pollID matches the found nodeID, this operation is an in-place
    // update. In that case, return the previous node of the node being updated. Otherwise return the
    // first node that was found with a value less than or equal to the provided _numTokens.
    function getInsertPointForNumTokens(address _voter, uint256 _numTokens, uint256 _pollID) public view returns (uint256 prevNode) {
        // Get the last node in the list and the number of tokens in that node
        uint256 nodeID = getLastNode(_voter);
        uint256 tokensInNode = getNumTokens(_voter, nodeID);

        // Iterate backwards through the list until reaching the root node
        while(nodeID != 0) {
            // Get the number of tokens in the current node
            tokensInNode = getNumTokens(_voter, nodeID);
            if(tokensInNode <= _numTokens) { // We found the insert point!
                if(nodeID == _pollID) {
                    // This is an in-place update. Return the prev node of the node being updated
                    nodeID = dllMap[_voter].getPrev(nodeID);
                }
                // Return the insert point
                return nodeID; 
            }
            // We did not find the insert point. Continue iterating backwards through the list
            nodeID = dllMap[_voter].getPrev(nodeID);
        }

        // The list is empty, or a smaller value than anything else in the list is being inserted
        return nodeID;
    }

    // General helper functions

    // Generates an identifier which associates a user and a vote together
    function attrUUID(address _user, uint256 _pollID) public pure returns (bytes32 UUID) {
        return keccak256(abi.encodePacked(_user, _pollID));
    }
    
    // Modifier: function can only be called by a listed weeve contract
    modifier calledByWeeveContract (address _address) {
        require(weeveContracts[_address] == true);
        _;
    }
}