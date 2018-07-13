pragma solidity ^0.4.24;

import "./SafeMath.sol";

// Basic ERC20 Interface 
interface ERC20 {
    function totalSupply() external returns (uint);
    function balanceOf(address tokenOwner) external returns (uint balance);
    function allowance(address tokenOwner, address spender) external returns (uint remaining);
    function transfer(address to, uint tokens) external returns (bool success);
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);
}

interface VotingContract {
    function commitVote(uint _voteID, address _address, bytes32 _secretHash, uint _numTokens, uint _prevPollID) external returns (bool success);
    function revealVote(uint _voteID, address _address, uint _voteOption, uint _salt) external returns (bool);
    function startPoll(uint _voteQuorum, uint _commitDuration, uint _revealDuration) external returns (uint pollID);
    function resolveVote(uint _voteID) external returns (bool votePassed);
    function claimReward(uint256 _voteID, uint256 _voteOption, address _address, uint256 _stakedTokens) external returns (uint256 reward);
}

library weeveRegistry {
    using SafeMath for uint;

    struct Device {
        string deviceName;
        string deviceID;
        address deviceOwner;
        uint256 stakedTokens;
        string state;
        bytes32 hashOfDeviceData;
        Metainformation metainformation;
    }
    
    struct Metainformation {
        string sensors;
        string dataType;
        string manufacturer;
        string identifier;
        string description;
        string product;
        string version;
        string serial;
        string cpu;
        string trustzone;
        string wifi;
    }

    struct Validator {
        address validatorAddress;
        uint256 stakedTokens;
    }

    struct Arbiter {
        address arbiterAddress;
        uint256 stakedTokens;
    }
    
    struct VoteChoice {
        uint256 stakedTokens;
        uint256 voteChoice;
    }
    
    struct Vote {
        uint256 voteID;
        address challengee;
        address challenger;
        string deviceID;
        uint256 stakedTokens;
        bool isResolved;
        mapping (address => VoteChoice) voteDetails;
    }
    
    struct RegistryStorage {
        // Name of the registry
        string registryName;
        
        // Address of the weeve Factory
        address weeveNetworkAddress;
    
        // Address of the WEEV token
        address weeveTokenAddress;
        
        // Address of the Voting contract
        address weeveVotingAddress;
    
        // DeviceID maps to Device-Struct
        mapping (string => Device) devices;

        // Address maps to array of strings
        mapping (address => string[]) devicesOfUser;

        // Address maps to number of Tokens
        mapping (address => uint) tokenBalance;

        // Address to Validator-Struct
        mapping (address => Validator) validators;

        // Address to Arbiter-Struct
        mapping (address => Arbiter) arbiters;

        // Address to number of staked tokens per user
        mapping (address => uint) totalStakedTokens;

        // Count of Tokens that need to be staked
        uint256 tokenStakePerRegistration;
        uint256 tokenStakePerValidator;
        uint256 tokenStakePerArbiter;

        // Number of all active devices
        uint256 activeDevices;

        // Current activation state of the registry itself
        bool registryIsActive;

        // Owner of the registry
        address registryOwner;

        // Access to our token
        ERC20 token;
        
        // Access to our voting contract
        VotingContract vote;
        
        // Votes of this registry
        Vote[] votes;
    }
    
    function initialize(RegistryStorage storage myRegistryStorage, string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, address _owner) public returns (bool success){
        // Setting the name of the registry
        myRegistryStorage.registryName = _name;

        // Setting the owner of the marketplace
        require(_owner != address(0));
        myRegistryStorage.registryOwner = _owner;

        // Values for staking
        myRegistryStorage.tokenStakePerRegistration = _stakePerRegistration;
        myRegistryStorage.tokenStakePerArbiter = _stakePerArbiter;
        myRegistryStorage.tokenStakePerValidator = _stakePerValidator;

        // Number of all active devices
        myRegistryStorage.activeDevices = 0;

        // Activation of the registry
        myRegistryStorage.registryIsActive = true;

        // Setting the address of the WEEV erc20 token
        myRegistryStorage.token = ERC20(myRegistryStorage.weeveTokenAddress);
        
        // Setting the address of the Weeve Voting Contract
        myRegistryStorage.vote = VotingContract(myRegistryStorage.weeveVotingAddress);
        
        return true;
    }

    // Request access to the registry
    function requestRegistration(RegistryStorage storage myRegistryStorage, string _deviceName, string _deviceID, bytes32[] _deviceMeta, address _sender) public returns (bool success){
        // Allocate new device
        Device memory newDevice;
        Metainformation memory newMetainformation;
        newDevice.metainformation = newMetainformation;
        
        // Add new device to mapping
        myRegistryStorage.devices[_deviceID] = newDevice;

        // Adding device id to the array of devices of a specific user
        myRegistryStorage.devicesOfUser[msg.sender].push(_deviceID);

        // Setting basic values
        myRegistryStorage.devices[_deviceID].deviceName = _deviceName;
        myRegistryStorage.devices[_deviceID].deviceID = _deviceID;
        myRegistryStorage.devices[_deviceID].deviceOwner = _sender;
        myRegistryStorage.devices[_deviceID].stakedTokens = 0;

        // If enough values are given, the information will be checked directly in this contract
        if(_deviceMeta.length == 11) {
            require(validateRegistration(myRegistryStorage, _deviceID, _deviceMeta));
            if(stakeTokens(myRegistryStorage, _sender, _deviceID, myRegistryStorage.tokenStakePerRegistration)) {
                myRegistryStorage.devices[_deviceID].state = "accepted";
                myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.add(1);
            } else {
                myRegistryStorage.devices[_deviceID].state = "unproven";
            }            
        // If only a hash (e.g. IPFS) is given, the request will be validated manually
        } else if(_deviceMeta.length == 1) {
            myRegistryStorage.devices[_deviceID].hashOfDeviceData = _deviceMeta[0];
            myRegistryStorage.devices[_deviceID].state = "unproven";
        } else {
            revert();  
        }
        return true;
    }
    
    // Validate a registry-request with enough values (currently just setting instead of checking)
    function validateRegistration(RegistryStorage storage myRegistryStorage, string _deviceID, bytes32[] _deviceMeta) internal returns (bool success) {
        myRegistryStorage.devices[_deviceID].metainformation.sensors = bytes32ToString(_deviceMeta[0]);
        myRegistryStorage.devices[_deviceID].metainformation.dataType = bytes32ToString(_deviceMeta[1]);
        myRegistryStorage.devices[_deviceID].metainformation.manufacturer = bytes32ToString(_deviceMeta[2]);
        myRegistryStorage.devices[_deviceID].metainformation.identifier = bytes32ToString(_deviceMeta[3]);
        myRegistryStorage.devices[_deviceID].metainformation.description = bytes32ToString(_deviceMeta[4]);
        myRegistryStorage.devices[_deviceID].metainformation.product = bytes32ToString(_deviceMeta[5]);
        myRegistryStorage.devices[_deviceID].metainformation.version = bytes32ToString(_deviceMeta[6]);
        myRegistryStorage.devices[_deviceID].metainformation.serial = bytes32ToString(_deviceMeta[7]);
        myRegistryStorage.devices[_deviceID].metainformation.cpu = bytes32ToString(_deviceMeta[8]);
        myRegistryStorage.devices[_deviceID].metainformation.trustzone = bytes32ToString(_deviceMeta[9]);
        myRegistryStorage.devices[_deviceID].metainformation.wifi = bytes32ToString(_deviceMeta[10]);
        return true;
    }

    // Simulating the approval from a validator (through oraclize)    
    function approveRegistrationRequest(RegistryStorage storage myRegistryStorage, string _deviceID) public returns (bool success) {
        require(myRegistryStorage.devices[_deviceID].stakedTokens == 0);
        require(stakeTokens(myRegistryStorage, myRegistryStorage.devices[_deviceID].deviceOwner, _deviceID, myRegistryStorage.tokenStakePerRegistration));
        myRegistryStorage.devices[_deviceID].state = "accepted";
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.add(1);
        return true;
    }

    // Unregistering your device
    function unregister(RegistryStorage storage myRegistryStorage, address _sender, string _deviceID) public returns (bool) {
        require(keccak256(abi.encodePacked(myRegistryStorage.devices[_deviceID].state)) == keccak256(abi.encodePacked("accepted")));
        require(unstakeTokens(myRegistryStorage, _sender, _deviceID));
        delete myRegistryStorage.devices[_deviceID];
        deleteFromArray(myRegistryStorage, _sender, _deviceID);
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.sub(1);
        return true;
    }
    
    // Challenge a device
    function raiseChallenge(RegistryStorage storage myRegistryStorage, string _deviceID, address _sender, uint256 _durationCommit, uint256 _durationReveal) public returns (uint256 voteNumber) {
        // Either it's the first device challenge or the current one has to be resolved (only one vote at a time)
        require(myRegistryStorage.votes.length == 0 || myRegistryStorage.votes[myRegistryStorage.votes.length-1].isResolved);

        // Create a new vote object
        Vote memory newVote = Vote({
            voteID: myRegistryStorage.vote.startPoll(50, _durationCommit, _durationReveal),
            deviceID: _deviceID,
            challenger: _sender,
            challengee: myRegistryStorage.devices[_deviceID].deviceOwner,
            stakedTokens: 0,
            isResolved: false
        });

        // Push vote object into the general vote array
        myRegistryStorage.votes.push(newVote);

        // Marking the device as challenged
        myRegistryStorage.devices[_deviceID].state = "challenged";
        
        // Automatic voting of the owner and the challenger
        uint256 challengerChoice = 1;
        uint256 challengeeChoice = 0;
        uint256 salt = 0;
        uint256 numberOfTokens = myRegistryStorage.devices[_deviceID].stakedTokens;

        // Automatic vote of the challenger
        require(myRegistryStorage.vote.commitVote(newVote.voteID, newVote.challenger, keccak256(abi.encodePacked(challengerChoice, salt)), numberOfTokens, 0), "Failed to commit the vote.");        
        myRegistryStorage.token.transferFrom(newVote.challenger, address(this), numberOfTokens);
        myRegistryStorage.votes[myRegistryStorage.votes.length-1].stakedTokens = myRegistryStorage.votes[myRegistryStorage.votes.length-1].stakedTokens.add(numberOfTokens);
        myRegistryStorage.votes[myRegistryStorage.votes.length-1].voteDetails[newVote.challenger].stakedTokens = numberOfTokens;

        // Automatic vote of the challengee
        require(myRegistryStorage.vote.commitVote(newVote.voteID, newVote.challengee, keccak256(abi.encodePacked(challengeeChoice, salt)), numberOfTokens, 0), "Failed to commit the vote."); 
        myRegistryStorage.votes[myRegistryStorage.votes.length-1].stakedTokens = myRegistryStorage.votes[myRegistryStorage.votes.length-1].stakedTokens.add(numberOfTokens);
        myRegistryStorage.votes[myRegistryStorage.votes.length-1].voteDetails[newVote.challengee].stakedTokens = numberOfTokens;

        return myRegistryStorage.votes.length-1;
    }

    // Vote on a challenge
    function voteOnChallenge(RegistryStorage storage myRegistryStorage, uint256 _voteNumber, address _sender, uint256 _numberOfTokens, bytes32 _voteHash) public returns (bool success) {
        // Transfer the amount of tokens of this vote to this contract
        myRegistryStorage.token.transferFrom(_sender, address(this), _numberOfTokens);
        myRegistryStorage.votes[_voteNumber].stakedTokens = myRegistryStorage.votes[_voteNumber].stakedTokens.add(_numberOfTokens);
        myRegistryStorage.votes[_voteNumber].voteDetails[_sender].stakedTokens = _numberOfTokens;

        // Commiting the vote through the voting-contract
        require(myRegistryStorage.vote.commitVote(myRegistryStorage.votes[_voteNumber].voteID, _sender, _voteHash, _numberOfTokens, 0), "Failed to commit the vote.");
        return true;
    }

    // Reveal a vote on a challenge
    function revealVote(RegistryStorage storage myRegistryStorage, uint256 _voteNumber, address _sender, uint256 _voteOption, uint256 _voteSalt) public returns (bool success) {
        // Revealing the vote through the voting-contract
        require(myRegistryStorage.vote.revealVote(myRegistryStorage.votes[_voteNumber].voteID, _sender, _voteOption, _voteSalt));
        myRegistryStorage.votes[_voteNumber].voteDetails[_sender].voteChoice = _voteOption;
        return true;
    }

    // Resolve a vote after the reveal-phase is over
    function resolveChallenge(RegistryStorage storage myRegistryStorage, uint256 _voteNumber) public returns (bool votePassed) {
        // Getting the vote object
        Vote storage currentVote = myRegistryStorage.votes[_voteNumber];
        // Resolving the vote through the voting-contract      
        votePassed = myRegistryStorage.vote.resolveVote(currentVote.voteID);
        // Marking the vote as resolved
        currentVote.isResolved = true;

        if(votePassed) {
            // If the vote passed add the staked tokens of the device to the tokens of this vote
            currentVote.stakedTokens = currentVote.stakedTokens.add(myRegistryStorage.devices[currentVote.deviceID].stakedTokens);
            // Removing the device from this registry
            myRegistryStorage.devices[currentVote.deviceID].state = "rejected";
            myRegistryStorage.totalStakedTokens[currentVote.challengee] = myRegistryStorage.totalStakedTokens[currentVote.challengee].sub(myRegistryStorage.devices[currentVote.deviceID].stakedTokens);
            myRegistryStorage.devices[currentVote.deviceID].stakedTokens = 0;
            myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.sub(1);
        } else {
            // If the vote didn't pass the challenged-flag will be reset
            myRegistryStorage.devices[currentVote.deviceID].state = "accepted";
        }
        return votePassed;
    }

    // Claim the reward of a finished vote
    function claimRewardOfVote(RegistryStorage storage myRegistryStorage, uint256 _voteNumber, address _sender) public returns (bool success) {
        // If the vote is not already resolved it will be done here automatically
        if(!myRegistryStorage.votes[_voteNumber].isResolved) {
            require(resolveChallenge(myRegistryStorage, _voteNumber));
        }
        // Only participants of the vote are able to call this function
        require(myRegistryStorage.votes[_voteNumber].voteDetails[_sender].stakedTokens > 0);

        // Getting the calculated reward of this vote from the voting-contract
        uint256 reward = myRegistryStorage.vote.claimReward(myRegistryStorage.votes[_voteNumber].voteID, myRegistryStorage.votes[_voteNumber].voteDetails[_sender].voteChoice, _sender, myRegistryStorage.votes[_voteNumber].voteDetails[_sender].stakedTokens);
        // Amount of rewarded tokens have to be at least equal to the amount that has been voted with
        // Means: Only the winning side is able to claim a reward
        require(reward >= myRegistryStorage.votes[_voteNumber].voteDetails[_sender].stakedTokens);

        // Checking whether the claiming person is the owner
        // If that is the case, the stake of the device will not be transferred 
        // (will remain as the stake since the challenge failed)
        if(_sender == myRegistryStorage.devices[myRegistryStorage.votes[_voteNumber].deviceID].deviceOwner) {
            myRegistryStorage.token.transfer(_sender, reward.sub(myRegistryStorage.devices[myRegistryStorage.votes[_voteNumber].deviceID].stakedTokens));
        } else {
            myRegistryStorage.token.transfer(_sender, reward);
        }
        
        myRegistryStorage.votes[_voteNumber].stakedTokens = myRegistryStorage.votes[_voteNumber].stakedTokens.sub(reward);
        myRegistryStorage.votes[_voteNumber].voteDetails[_sender].stakedTokens = 0;
        return true;
    }

    // Stake tokens through our ERC20 contract
    function stakeTokens(RegistryStorage storage myRegistryStorage, address _address, string _deviceID, uint256 _numberOfTokens) internal returns (bool success) {
        myRegistryStorage.token.transferFrom(_address, address(this), _numberOfTokens);
        myRegistryStorage.devices[_deviceID].stakedTokens = myRegistryStorage.devices[_deviceID].stakedTokens.add(_numberOfTokens);
        myRegistryStorage.totalStakedTokens[_address] = myRegistryStorage.totalStakedTokens[_address].add(_numberOfTokens);
        return true;
    }

    // Unstake tokens through our ERC20 contract
    function unstakeTokens(RegistryStorage storage myRegistryStorage, address _address, string _deviceID) internal returns (bool success) {
        require(myRegistryStorage.devices[_deviceID].stakedTokens > 0);
        require(myRegistryStorage.token.transfer(_address, myRegistryStorage.devices[_deviceID].stakedTokens));
        myRegistryStorage.totalStakedTokens[_address] = myRegistryStorage.totalStakedTokens[_address].sub(myRegistryStorage.devices[_deviceID].stakedTokens);
        myRegistryStorage.devices[_deviceID].stakedTokens = myRegistryStorage.devices[_deviceID].stakedTokens.sub(myRegistryStorage.devices[_deviceID].stakedTokens);
        return true;
    }

    // Helper function: deleting a device from a users array
    function deleteFromArray(RegistryStorage storage myRegistryStorage, address _address, string _value) internal {
        require(myRegistryStorage.devicesOfUser[_address].length > 0);
        for(uint i = 0; i < myRegistryStorage.devicesOfUser[_address].length; i++) {
            if(keccak256(abi.encodePacked(myRegistryStorage.devicesOfUser[_address][i])) == keccak256(abi.encodePacked(_value))) {
                if(i != myRegistryStorage.devicesOfUser[_address].length-1) {
                    myRegistryStorage.devicesOfUser[_address][i] = myRegistryStorage.devicesOfUser[_address][myRegistryStorage.devicesOfUser[_address].length-1];
                }
                delete myRegistryStorage.devicesOfUser[_address][myRegistryStorage.devicesOfUser[_address].length-1];
                myRegistryStorage.devicesOfUser[_address].length--;
                break;
            }
        }
    }

    // Helper function: converting bytes32 to string
    function bytes32ToString(bytes32 x) internal pure returns (string) {
        bytes memory bytesString = new bytes(32);
        uint charCount = 0;
        for (uint j = 0; j < 32; j++) {
            byte char = byte(bytes32(uint(x) * 2 ** (8 * j)));
            if (char != 0) {
                bytesString[charCount] = char;
                charCount++;
            }
        }
        bytes memory bytesStringTrimmed = new bytes(charCount);
        for (j = 0; j < charCount; j++) {
            bytesStringTrimmed[j] = bytesString[j];
        }
        return string(bytesStringTrimmed);
    }
}