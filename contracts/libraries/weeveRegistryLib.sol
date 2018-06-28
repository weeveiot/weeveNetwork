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
    function commitVote(uint _pollID, address _address, bytes32 _secretHash, uint _numTokens, uint _prevPollID) external returns (bool success);
    function revealVote(uint _pollID, address _address, uint _voteOption, uint _salt) external returns (bool);
    function startPoll(uint _voteQuorum, uint _commitDuration, uint _revealDuration) external returns (uint pollID);
    function pollEnded(uint _pollID) external returns (bool ended);
    function resolveVote(uint _pollID, uint256 _securityDeposit) external returns (bool votePassed);
    function isResolved(uint256 _pollID) external returns (bool resolved);
    function claimReward(uint256 _pollID, uint256 _voteOption, address _address, uint256 _stakedTokens) external returns (uint256 reward);
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
        mapping (address => VoteChoice) voteDetails;
    }
    
    struct RegistryStorage {
        // Name of the registry
        string registryName;
        
        // Address of the weeve Factory
        address weeveFactoryAddress;
    
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
    
    function initialize(RegistryStorage storage myRegistryStorage, string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, address _owner) public returns(bool){
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
    function requestRegistration(RegistryStorage storage myRegistryStorage, string _deviceName, string _deviceID, bytes32[] _deviceMeta, address _sender) public returns(bool){
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
    function validateRegistration(RegistryStorage storage myRegistryStorage, string _deviceID, bytes32[] _deviceMeta) internal returns(bool) {
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
    function approveRegistrationRequest(RegistryStorage storage myRegistryStorage, string _deviceID) public returns(bool) {
        require(myRegistryStorage.devices[_deviceID].stakedTokens == 0);
        require(stakeTokens(myRegistryStorage, myRegistryStorage.devices[_deviceID].deviceOwner, _deviceID, myRegistryStorage.tokenStakePerRegistration));
        myRegistryStorage.devices[_deviceID].state = "accepted";
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.add(1);
        return true;
    }

    // Unregistering your device
    function unregister(RegistryStorage storage myRegistryStorage, address _sender, string _deviceID) public returns(bool) {
        require(keccak256(abi.encodePacked(myRegistryStorage.devices[_deviceID].state)) == keccak256(abi.encodePacked("accepted")));
        require(unstakeTokens(myRegistryStorage, _sender, _deviceID));
        delete myRegistryStorage.devices[_deviceID];
        deleteFromArray(myRegistryStorage, _sender, _deviceID);
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.sub(1);
        return true;
    }
    
    // Challenge a device
    function raiseChallenge(RegistryStorage storage myRegistryStorage, string _deviceID, address _sender, uint256 _durationCommit, uint256 _durationReveal) public returns(uint256) {
        require(myRegistryStorage.votes.length == 0 || myRegistryStorage.vote.isResolved(myRegistryStorage.votes[myRegistryStorage.votes.length-1].voteID));
        Vote memory newVote;
        newVote.voteID = myRegistryStorage.vote.startPoll(50, _durationCommit, _durationReveal);
        newVote.deviceID = _deviceID;
        newVote.challenger = _sender;
        newVote.challengee = myRegistryStorage.devices[_deviceID].deviceOwner;
        newVote.stakedTokens = 0;
        myRegistryStorage.devices[_deviceID].state = "challenged";
        myRegistryStorage.votes.push(newVote);
        uint256 challengerChoice = 1;
        uint256 challengerSalt = 0;
        require(voteOnChallenge(myRegistryStorage, newVote.voteID, newVote.challenger, myRegistryStorage.devices[_deviceID].stakedTokens, keccak256(abi.encodePacked(challengerChoice, challengerSalt))));
        return newVote.voteID;
    }
    
    // Vote on a challenge
    function voteOnChallenge(RegistryStorage storage myRegistryStorage, uint256 _voteID, address _sender, uint256 _numberOfTokens, bytes32 _voteHash) public returns(bool) {
        uint256 currentVoteID = myRegistryStorage.votes.length-1;
        require(myRegistryStorage.votes[currentVoteID].voteID == _voteID, "Not the current vote.");

        myRegistryStorage.token.transferFrom(_sender, address(this), _numberOfTokens);
        myRegistryStorage.votes[currentVoteID].stakedTokens = myRegistryStorage.votes[currentVoteID].stakedTokens.add(_numberOfTokens);
        myRegistryStorage.votes[currentVoteID].voteDetails[_sender].stakedTokens = _numberOfTokens;

        require(myRegistryStorage.vote.commitVote(_voteID, _sender, _voteHash, _numberOfTokens, 0), "Failed to commit the vote.");
        return true;
    }

    // Reveal a vote on a challenge
    function revealVote(RegistryStorage storage myRegistryStorage, uint256 _voteID, address _sender, uint256 _voteOption, uint256 _voteSalt) public returns(bool) {
        uint256 currentVoteID = myRegistryStorage.votes.length-1;
        require(myRegistryStorage.votes[currentVoteID].voteID == _voteID);
        require(myRegistryStorage.vote.revealVote(_voteID, _sender, _voteOption, _voteSalt));
        myRegistryStorage.votes[currentVoteID].voteDetails[_sender].voteChoice = _voteOption;
        return true;
    }
        
    // Resolve a vote after the reveal-phase is over
    function resolveChallenge(RegistryStorage storage myRegistryStorage, uint256 _voteID) public returns(bool) {
        uint256 currentVoteID = myRegistryStorage.votes.length-1;
        Vote storage currentVote = myRegistryStorage.votes[myRegistryStorage.votes.length-1];
        require(myRegistryStorage.votes[currentVoteID].voteID == _voteID);
        bool votePassed = myRegistryStorage.vote.resolveVote(_voteID, myRegistryStorage.devices[currentVote.deviceID].stakedTokens);

        if(votePassed) {
            currentVote.stakedTokens = currentVote.stakedTokens.add(myRegistryStorage.devices[currentVote.deviceID].stakedTokens);
            myRegistryStorage.devices[currentVote.deviceID].state = "rejected";
            myRegistryStorage.totalStakedTokens[currentVote.challengee] = myRegistryStorage.totalStakedTokens[currentVote.challengee].sub(myRegistryStorage.devices[currentVote.deviceID].stakedTokens);
            myRegistryStorage.devices[currentVote.deviceID].stakedTokens = 0;
            myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.sub(1);
        } else {
            myRegistryStorage.devices[currentVote.deviceID].state = "accepted";
        }
        return true;
    }
    
    // Claim the reward of a finished vote
    function claimRewardOfVote(RegistryStorage storage myRegistryStorage, uint256 _voteID, address _sender) public returns(bool) {
        if(!myRegistryStorage.vote.isResolved(_voteID)) {
            require(resolveChallenge(myRegistryStorage, _voteID));
        }
        
        require(myRegistryStorage.votes[i].voteDetails[_sender].stakedTokens > 0);
        bool foundVote = false;
        uint256 i;
        for(i = myRegistryStorage.votes.length-1; i >= 0; i--) {
            if(myRegistryStorage.votes[i].voteID == _voteID) {
                foundVote = true;
                break;
            }
        }
        require(foundVote);
        uint256 reward = myRegistryStorage.vote.claimReward(_voteID, myRegistryStorage.votes[i].voteDetails[_sender].voteChoice, _sender, myRegistryStorage.votes[i].voteDetails[_sender].stakedTokens);
        require(reward >= myRegistryStorage.votes[i].voteDetails[_sender].stakedTokens);
        myRegistryStorage.token.transfer(_sender, reward);
        myRegistryStorage.votes[i].stakedTokens = myRegistryStorage.votes[i].stakedTokens.sub(reward);
        myRegistryStorage.votes[i].voteDetails[_sender].stakedTokens = 0;
        return true;
    }

    // Stake tokens through our ERC20 contract
    function stakeTokens(RegistryStorage storage myRegistryStorage, address _address, string _deviceID, uint256 _numberOfTokens) internal returns(bool) {
        myRegistryStorage.token.transferFrom(_address, address(this), _numberOfTokens);
        myRegistryStorage.devices[_deviceID].stakedTokens = myRegistryStorage.devices[_deviceID].stakedTokens.add(_numberOfTokens);
        myRegistryStorage.totalStakedTokens[_address] = myRegistryStorage.totalStakedTokens[_address].add(_numberOfTokens);
        return true;
    }

    // Unstake tokens through our ERC20 contract
    function unstakeTokens(RegistryStorage storage myRegistryStorage, address _address, string _deviceID) internal returns(bool) {
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