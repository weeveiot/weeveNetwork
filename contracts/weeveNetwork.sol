pragma solidity ^0.4.24;

import "./libraries/SafeMath.sol";
import "./libraries/Owned.sol";

// Basic ERC20 Interface 
interface ERC20 {
    function totalSupply() external returns (uint);
    function balanceOf(address tokenOwner) external returns (uint256 balance);
    function allowance(address tokenOwner, address spender) external returns (uint256 remaining);
    function transfer(address to, uint256 tokens) external returns (bool success);
    function approve(address spender, uint256 tokens) external returns (bool success);
    function transferFrom(address from, address to, uint256 tokens) external returns (bool success);
}

// Interface for our registries
interface weeveRegistry {
    function initialize(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, address _owner) external returns (bool success);
    function deactivateRegisty() external returns (bool success);
    function closeRegistry() external returns (bool success);
    function getTotalDeviceCount() external returns (uint256 numberOfDevices);
}

// Interface for our marketplaces
interface weeveMarketplace {
    function initialize(string _name, uint256 _commission, address _owner) external returns (bool success);
    function deactivateMarketplace() external returns (bool success);
    function closeMarketplace() external returns (bool success);
    function getTotalTradeCount() external returns (uint256 numberOfCurrentTrades);
}

// Interface for our voting scheme
interface weeveVoting {  
    function addWeeveContract(address _newContract) external returns (bool success);
    function removeWeeveContract(address _obsoleteContract) external returns (bool success);
    function commitVote(uint _voteID, address _address, bytes32 _secretHash, uint _numTokens, uint _prevPollID) external returns (bool success);
    function revealVote(uint _voteID, address _address, uint _voteOption, uint _salt) external returns (bool);
    function startPoll(uint _voteQuorum, uint _commitDuration, uint _revealDuration) external returns (uint pollID);
    function resolveVote(uint _voteID) external returns (bool votePassed);
    function claimReward(uint256 _voteID, uint256 _voteOption, address _address, uint256 _stakedTokens) external returns (uint256 reward);
}

contract weeveNetwork is Owned {
    using SafeMath for uint;

    // The current hash of the valid registry and marketplace code
    // (Will be replaced by an array of hashes soon-ish)
    bytes32 public weeveRegistryHash;
    bytes32 public weeveMarketplaceHash;

    // Mapping from address to uint-array (maps an address to all of its registry id's)
    mapping(address => uint256[]) userRegistries;

    // Mapping from address to uint-array (maps an address to all of its marketplace id's)
    mapping(address => uint256[]) userMarketplaces;

    // Mapping from address to a bool, to check whether this address has already had its share of test-WEEV
    mapping(address => bool) hasWithdrawnTestWEEV;

    struct Registry {
        uint256 id;
        string name;
        address owner;
        address registryAddress;
        uint256 stakedTokens;
        bool active;
        bool challenged;
    }

    struct Marketplace {
        uint256 id;
        string name;
        address owner;
        address marketplaceAddress;
        uint256 stakedTokens;
        bool active;
        bool challenged;
    }

    struct VoteChoice {
        uint256 stakedTokens;
        uint256 voteChoice;
    }
    
    struct Vote {
        uint256 voteID;
        bool isRegistry;
        bool isMarketplace;
        uint256 entityID;
        address challengee;
        address challenger;
        uint256 stakedTokens;
        bool isResolved;
        mapping (address => VoteChoice) voteDetails;
    }

    // Array of all registries
    Registry[] public allRegistries;

    // Array of all registries
    Marketplace[] public allMarketplaces;

    // Our ERC20 token
    ERC20 public token;

    // Address to number of staked tokens per user
    mapping (address => uint) totalStakedTokens;

    // Our voting contract
    weeveVoting public vote;

    // Registry-related votes of this factory
    Vote[] allVotes;

    // Registry-related votes of this factory
    uint256[] registryVotes;

    // Marketplace-related votes of this factory
    uint256[] marketplaceVotes;

    // Tokens that need to be staked for each registry (soon to be dynamic)
    uint256 tokensPerRegistryCreation;

    // Tokens that need to be staked for each registry (soon to be dynamic)
    uint256 tokensPerMarketplaceCreation;

    constructor(address _erc20Address) public {
        require(_erc20Address != address(0));

        // Setting the address of our WEEV token contract
        token = ERC20(_erc20Address);        
        
        // weeve Registry code hash (placeholder)
        weeveRegistryHash = 0x0000000000000000000000000000000000000000000000000000000000000000;

        // weeve Marketplace code hash (placeholder)
        weeveMarketplaceHash = 0x0000000000000000000000000000000000000000000000000000000000000000;

        // Tokens per Registry
        tokensPerRegistryCreation = 1000 * 10**18;

        // Tokens per Marketplace
        tokensPerMarketplaceCreation = 1000 * 10**18;
    }
    
    // Setting a new valid registry code hash as an owner
    function setNewVotingAddress(address _votingContractAddress) public onlyOwner {
        require(_votingContractAddress != address(0));
        // Setting the address of our voting contract
        vote = weeveVoting(_votingContractAddress);
    }

    // Setting a new valid registry code hash as an owner
    function setNewRegistryHash(bytes _contractCode) public onlyOwner {
        weeveRegistryHash = keccak256(_contractCode);
    }

    // Setting a new valid marketplace code hash as an owner
    function setNewMarketplaceHash(bytes _contractCode) public onlyOwner {
        weeveMarketplaceHash = keccak256(_contractCode);
    }
    
    // Setting a new stake for marketplace creation as an owner
    function setNewMarketplaceStake(uint256 _newStakeMarketplace) public onlyOwner {
        tokensPerMarketplaceCreation = _newStakeMarketplace;
    }
    
    // Setting a new stake for registry creation as an owner
    function setNewRegistryStake(uint256 _newStakeRegistry) public onlyOwner {
        tokensPerRegistryCreation = _newStakeRegistry;
    }

    // Creating a new registry
    function createRegistry(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, bytes _contractCode) public hasEnoughTokensAllowed(msg.sender, tokensPerRegistryCreation) returns (address newRegistryAddress) {
        // Hash of the contract code has to be correct (no invalid/untrusted code can be deployed)
        require(weeveRegistryHash == keccak256(_contractCode));

        // Allocating a new registry struct
        Registry memory newRegistry;
        newRegistry.id = allRegistries.length;
        newRegistry.name = _name;
        newRegistry.owner = msg.sender;
        
        // Staking of the tokens
        newRegistry.stakedTokens = stakeTokens(msg.sender, tokensPerRegistryCreation);
        require(newRegistry.stakedTokens >= tokensPerRegistryCreation);

        totalStakedTokens[msg.sender] = totalStakedTokens[msg.sender].add(newRegistry.stakedTokens);

        // Deploying the contract
        newRegistry.registryAddress = deployCode(_contractCode);
        require(newRegistry.registryAddress != address(0));

        // Activating the new registry
        weeveRegistry newWeeveRegistry = weeveRegistry(newRegistry.registryAddress);
        require(newWeeveRegistry.initialize(_name, _stakePerRegistration, _stakePerArbiter, _stakePerValidator, msg.sender));

        // Add the address to the voting contract
        require(vote.addWeeveContract(newRegistry.registryAddress));

        // The new registry is now active
        newRegistry.active = true;

        // Adding the registry to the users registry array
        userRegistries[msg.sender].push(newRegistry.id);

        // Adding the registry to the general registry array
        allRegistries.push(newRegistry);
        
        // Returning the registries address
        return newRegistry.registryAddress;
    }

    // Creating a new marketplace
    function createMarketplace(string _name, uint256 _commission, bytes _contractCode) public hasEnoughTokensAllowed(msg.sender, tokensPerMarketplaceCreation) returns (address newMarketplaceAddress) {
        // Hash of the contract code has to be correct (no invalid/untrusted code can be deployed)
        require(weeveMarketplaceHash == keccak256(_contractCode));

        // Allocating a new marketplace struct
        Marketplace memory newMarketplace;
        newMarketplace.id = allMarketplaces.length;
        newMarketplace.name = _name;
        newMarketplace.owner = msg.sender;
        
        // Staking of the tokens
        newMarketplace.stakedTokens = stakeTokens(msg.sender, tokensPerMarketplaceCreation);
        require(newMarketplace.stakedTokens >= tokensPerMarketplaceCreation);

        totalStakedTokens[msg.sender] = totalStakedTokens[msg.sender].add(newMarketplace.stakedTokens);

        // Deploying the contract
        newMarketplace.marketplaceAddress = deployCode(_contractCode);
        require(newMarketplace.marketplaceAddress != address(0));

        // Activating the new marketplace
        weeveMarketplace newWeeveMarketplace = weeveMarketplace(newMarketplace.marketplaceAddress);
        require(newWeeveMarketplace.initialize(_name, _commission, msg.sender));

        // The new marketplace is now active
        newMarketplace.active = true;

        // Adding the marketplace to the users marketplace array
        userMarketplaces[msg.sender].push(newMarketplace.id);

        // Adding the marketplace to the general marketplace array
        allMarketplaces.push(newMarketplace);
        
        // Returning the marketplaces address
        return newMarketplace.marketplaceAddress;
    }
    
    // Internal function to deploy bytecode to the blockchain
    function deployCode(bytes _contractCode) internal returns (address addr) {
        uint256 asmReturnValue;
        // Inline Assembly in generally considered insecure by most linters, but it's fine in this case
        /* solium-disable-next-line */
        assembly {
            addr := create(0,add(_contractCode,0x20), mload(_contractCode))
            asmReturnValue := gt(extcodesize(addr),0)
        }
        require(asmReturnValue > 0);
    }

    // Closing a registry where no devices are active anymore (only the registry owner is allowed to do this)
    function closeRegistry(uint256 _id) public isOwnerOfRegistry(msg.sender, _id) {
        weeveRegistry theRegistry = weeveRegistry(allRegistries[_id].registryAddress);
        // Calling the closeRegistry function of this registry
        require(theRegistry.closeRegistry());
         // Unstaking the remaining tokens
        require(unstakeTokens(allRegistries[_id].owner, allRegistries[_id].stakedTokens));
        totalStakedTokens[msg.sender] = totalStakedTokens[msg.sender].sub(allRegistries[_id].stakedTokens);
        // Remove the address from the voting contract
        require(vote.removeWeeveContract(allRegistries[_id].registryAddress));
        allRegistries[_id].stakedTokens = 0;
        allRegistries[_id].active = false;
    }

    // Closing a registry where no devices are active anymore (only the registry owner is allowed to do this)
    function closeMarketplace(uint256 _id) public isOwnerOfMarketplace(msg.sender, _id) {
        weeveMarketplace theMarketplace = weeveMarketplace(allMarketplaces[_id].marketplaceAddress);
        // Only if the amount of active devices is zero
        require(theMarketplace.getTotalTradeCount() == 0);
        // Calling the closeMarketplace function of this marketplace
        require(theMarketplace.closeMarketplace());
        // Unstaking the remaining tokens
        require(unstakeTokens(allMarketplaces[_id].owner, allMarketplaces[_id].stakedTokens));
        totalStakedTokens[msg.sender] = totalStakedTokens[msg.sender].sub(allMarketplaces[_id].stakedTokens);
        allMarketplaces[_id].stakedTokens = 0;
        allMarketplaces[_id].active = false;
        // TODO: Disable Marketplace
    }

    // Challenging a registry, resulting in a new vote. Affected registry owner and challenger are 
    // automatically casting their corresponding votes
    function challengeRegistry(uint256 _id, uint256 _durationCommit, uint256 _durationReveal) public returns (uint256 voteID) {
        // Registry owner can't challenge his own registry
        require(msg.sender != allRegistries[_id].owner);
        // Either it's the first registry vote or the current one has to be resolved (only one vote at a time)
        require(registryVotes.length == 0 || allVotes[registryVotes[registryVotes.length-1]].isResolved);
        // Registry has to be unchallenged
        require(!allRegistries[_id].challenged);

        // Create a new vote object
        Vote memory newVote = Vote({
            voteID: vote.startPoll(50, _durationCommit, _durationReveal),
            isRegistry: true,
            isMarketplace: false,
            entityID: _id,
            challengee: allRegistries[_id].owner,
            challenger: msg.sender,
            stakedTokens: 0,
            isResolved: false
        });

        // Push vote object into the general vote array
        allVotes.push(newVote);

        // Pushing the number of the vote into the corresponding array
        uint256 voteNumber = allVotes.length-1;
        registryVotes.push(voteNumber);

        // Marking the registry as challenged
        allRegistries[_id].challenged = true;
        
        // Finalizing the challenge (automatic voting of owner and challenger)
        require(finalizeChallenge(voteNumber, allRegistries[_id].stakedTokens));

        return voteNumber;
    }

    // Challenging a marketplace, resulting in a new vote. Affected marketplace owner and challenger are 
    // automatically casting their corresponding votes
    function challengeMarketplace(uint256 _id, uint256 _durationCommit, uint256 _durationReveal) public returns (uint256 voteID) {
        // Marketplace owner can't challenge his own marketplace
        require(msg.sender != allMarketplaces[_id].owner);
        // Either it's the first marketplace vote or the current one has to be resolved (only one vote at a time)
        require(marketplaceVotes.length == 0 || allVotes[marketplaceVotes[marketplaceVotes.length-1]].isResolved);
        // Marketplace has to be unchallenged
        require(!allMarketplaces[_id].challenged);

        // Create a new vote object
        Vote memory newVote = Vote({
            voteID: vote.startPoll(50, _durationCommit, _durationReveal),
            isRegistry: false,
            isMarketplace: true,
            entityID: _id,
            challengee: allMarketplaces[_id].owner,
            challenger: msg.sender,
            stakedTokens: 0,
            isResolved: false
        });

        // Push vote object into the general vote array
        allVotes.push(newVote);

        // Pushing the number of the vote into the corresponding array
        uint256 voteNumber = allVotes.length-1;
        marketplaceVotes.push(voteNumber);

        // Marking the marketplace as challenged
        allMarketplaces[_id].challenged = true;
        
        // Finalizing the challenge (automatic voting of owner and challenger)
        require(finalizeChallenge(voteNumber, allMarketplaces[_id].stakedTokens));

        return voteNumber;
    }

    // Finalizing a new challenge, which is basically the automatic voting of the owner and the challenger
    function finalizeChallenge(uint256 _voteNumber, uint256 _numberOfTokens) internal returns (bool success) {
        // Vote selections of the challenger and the challengee
        uint256 challengerChoice = 1;
        uint256 challengeeChoice = 0;
        uint256 salt = 0;

        // Automatic vote of the challenger
        require(vote.commitVote(allVotes[_voteNumber].voteID, allVotes[_voteNumber].challenger, keccak256(abi.encodePacked(challengerChoice, salt)), _numberOfTokens, 0), "Failed to commit the vote.");        
        token.transferFrom(allVotes[_voteNumber].challenger, address(this), _numberOfTokens);
        allVotes[_voteNumber].stakedTokens = allVotes[_voteNumber].stakedTokens.add(_numberOfTokens);
        allVotes[_voteNumber].voteDetails[allVotes[_voteNumber].challenger].stakedTokens = _numberOfTokens;

        // Automatic vote of the challengee
        require(vote.commitVote(allVotes[_voteNumber].voteID, allVotes[_voteNumber].challengee, keccak256(abi.encodePacked(challengeeChoice, salt)), _numberOfTokens, 0), "Failed to commit the vote."); 
        allVotes[_voteNumber].stakedTokens = allVotes[_voteNumber].stakedTokens.add(_numberOfTokens);
        allVotes[_voteNumber].voteDetails[allVotes[_voteNumber].challengee].stakedTokens = _numberOfTokens;
        
        return true;
    }

    // Vote on a challenge
    function voteOnChallenge(uint256 _voteNumber, uint256 _numberOfTokens, bytes32 _voteHash) public {
        // Transfer the amount of tokens of this vote to this contract
        token.transferFrom(msg.sender, address(this), _numberOfTokens);
        allVotes[_voteNumber].stakedTokens = allVotes[_voteNumber].stakedTokens.add(_numberOfTokens);
        allVotes[_voteNumber].voteDetails[msg.sender].stakedTokens = _numberOfTokens;

        // Commiting the vote through the voting-contract
        require(vote.commitVote(allVotes[_voteNumber].voteID, msg.sender, _voteHash, _numberOfTokens, 0), "Failed to commit the vote.");
    }

    // Reveal a vote on a challenge
    function revealVote(uint256 _voteNumber, uint256 _voteOption, uint256 _voteSalt) public {
        // Revealing the vote through the voting-contract
        require(vote.revealVote(allVotes[_voteNumber].voteID, msg.sender, _voteOption, _voteSalt));
        allVotes[_voteNumber].voteDetails[msg.sender].voteChoice = _voteOption;
    }

    // Resolve a vote after the reveal-phase is over
    function resolveChallenge(uint256 _voteNumber) public returns (bool votePassed) {
        // Getting the vote object
        Vote storage currentVote = allVotes[_voteNumber];
        // Resolving the vote through the voting-contract
        votePassed = vote.resolveVote(currentVote.voteID);
        // Marking the vote as resolved
        currentVote.isResolved = true;

        if(votePassed) {
            if(currentVote.isRegistry) {
                // If the vote passed and the entity was a registry, its staked tokens will be added to the tokens of this vote
                currentVote.stakedTokens = currentVote.stakedTokens.add(allRegistries[currentVote.entityID].stakedTokens);
                totalStakedTokens[currentVote.challengee] = totalStakedTokens[currentVote.challengee].sub(allRegistries[currentVote.entityID].stakedTokens);
                allRegistries[currentVote.entityID].stakedTokens = 0;
                allRegistries[currentVote.entityID].active = false;
                weeveRegistry theRegistry = weeveRegistry(allRegistries[currentVote.entityID].registryAddress);
                // Deactivation of the registry
                require(theRegistry.deactivateRegisty());
            } else {
                // If the vote passed and the entity was a marketplace, its staked tokens will be added to the tokens of this vote
                currentVote.stakedTokens = currentVote.stakedTokens.add(allMarketplaces[currentVote.entityID].stakedTokens);
                totalStakedTokens[currentVote.challengee] = totalStakedTokens[currentVote.challengee].sub(allMarketplaces[currentVote.entityID].stakedTokens);
                allMarketplaces[currentVote.entityID].stakedTokens = 0;
                allMarketplaces[currentVote.entityID].active = false;
                weeveMarketplace theMarketplace = weeveMarketplace(allMarketplaces[currentVote.entityID].marketplaceAddress);
                // Deactivation of the marketplace
                require(theMarketplace.deactivateMarketplace());
            }
        } else {
            // If the vote didn't pass the challenged-flag will be reset
            if(currentVote.isRegistry) {
                allRegistries[currentVote.entityID].challenged = false;
            } else {
                allMarketplaces[currentVote.entityID].challenged = false;
            }
        }
        return votePassed;
    }

    // Claim the reward of a finished vote
    function claimRewardOfVote(uint256 _voteNumber) public {
        // If the vote is not already resolved it will be done here automatically
        if(!allVotes[_voteNumber].isResolved) {
            require(resolveChallenge(_voteNumber));
        }
        // Only participants of the vote are able to call this function
        require(allVotes[_voteNumber].voteDetails[msg.sender].stakedTokens > 0);
        
        // Getting the calculated reward of this vote from the voting-contract
        uint256 reward = vote.claimReward(allVotes[_voteNumber].voteID, allVotes[_voteNumber].voteDetails[msg.sender].voteChoice, msg.sender, allVotes[_voteNumber].voteDetails[msg.sender].stakedTokens);
        // Amount of rewarded tokens have to be at least equal to the amount that has been voted with
        // Means: Only the winning side is able to claim a reward
        require(reward >= allVotes[_voteNumber].voteDetails[msg.sender].stakedTokens);

        address _owner;
        uint256 _stakedTokens;

        // Setting variables in case the claiming person is the owner
        if(allVotes[_voteNumber].isRegistry) {
            _owner = allRegistries[allVotes[_voteNumber].entityID].owner;
            _stakedTokens = allRegistries[allVotes[_voteNumber].entityID].stakedTokens;
        } else {
            _owner = allMarketplaces[allVotes[_voteNumber].entityID].owner;
            _stakedTokens = allMarketplaces[allVotes[_voteNumber].entityID].stakedTokens;
        }

        // Checking whether the claiming person is the owner
        // If that is the case, the stake of the marketplace will not be transferred 
        // (will remain as the stake since the challenge failed)
        if(msg.sender == _owner) {
            token.transfer(msg.sender, reward.sub(_stakedTokens));
        } else {
            token.transfer(msg.sender, reward);
        }
        
        allVotes[_voteNumber].stakedTokens = allVotes[_voteNumber].stakedTokens.sub(reward);
        allVotes[_voteNumber].voteDetails[msg.sender].stakedTokens = 0;
    }
    
    // Stake tokens through our ERC20 contract
    function stakeTokens(address _address, uint256 _numberOfTokens) internal returns (uint256) {
        require(token.transferFrom(_address, address(this), _numberOfTokens));
        return _numberOfTokens;
    }

    // Unstake tokens through our ERC20 contract
    function unstakeTokens(address _address, uint256 _numberOfTokens) internal returns (bool) {
        require(token.balanceOf(address(this)) >= _numberOfTokens);
        require(token.transfer(_address, _numberOfTokens));
        return true;
    }

    // Development function for the test-net to get some Test-Tokens
    function getTestTokens() public {
        require(!hasWithdrawnTestWEEV[msg.sender]);
        token.transferFrom(0x0000000000000000000000000000000000000000, msg.sender, 5000 * 10**18);
        hasWithdrawnTestWEEV[msg.sender] = true;
    }

    // Modifier: Checks whether an address has enough tokens authorized to be withdrawn by the registry
    modifier hasEnoughTokensAllowed(address _address, uint256 _numberOfTokens) {
        require(token.allowance(_address, address(this)) >= _numberOfTokens);
        _;
    }

    // Modifier: Checks whether an address is the owner of a registry
    modifier isOwnerOfRegistry(address _address, uint256 _id) {
        require(allRegistries[_id].owner == _address);
        _;
    }

    // Modifier: Checks whether an address is the owner of a marketplace
    modifier isOwnerOfMarketplace(address _address, uint256 _id) {
        require(allMarketplaces[_id].owner == _address);
        _;
    }
}