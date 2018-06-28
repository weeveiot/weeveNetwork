pragma solidity ^0.4.24;

import "./libraries/weeveRegistryLib.sol";

// An exemplary weeve Registry contract
contract myRegistry {    
    using SafeMath for uint;
    
    event deviceRegistration(string indexed deviceID, address indexed owner);
    event deviceAccepted(string indexed deviceID, address indexed owner);
    event deviceUnregistered(string indexed deviceID, address indexed owner);
    event challengeRaised(uint indexed voteID, string indexed deviceID);
    event votedOnChallenge(uint indexed voteID, address indexed voter, bool vote, uint256 numberOfTokens);
    event challengeResolved(uint indexed voteID, string indexed deviceID, bool votePassed, uint256 numberOfTokensFor, uint256 numberOfTokensAgainst);

    // General storage for the Registry
    weeveRegistry.RegistryStorage public myRegistryStorage;
    
    // Constructor (fired once upon creation)
    constructor() public {
        // Initially the registry is not active
        myRegistryStorage.registryIsActive = false;
        
        // Address of the weeve Factory
        myRegistryStorage.weeveFactoryAddress = 0x0000000000000000000000000000000000000000;
    
        // Address of the WEEV token
        myRegistryStorage.weeveTokenAddress = 0x0000000000000000000000000000000000000000;
        
        // Address of the Voting contract
        myRegistryStorage.weeveVotingAddress = 0x0000000000000000000000000000000000000000;
    }

    function initialize(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, address _owner) public onlyWeeveFactory returns(bool){
        require(weeveRegistry.initialize(myRegistryStorage, _name, _stakePerRegistration, _stakePerArbiter, _stakePerValidator, _owner));
        return true;
    }
    
    function setVotingAddress(address _address) public onlyRegistryOwner {
        myRegistryStorage.weeveVotingAddress = _address;
        myRegistryStorage.vote = VotingContract(_address);
    }

    function closeRegistry() public onlyWeeveFactory returns(bool) {
        // Only the weeve factory is able to initialise a registry
        require(myRegistryStorage.activeDevices == 0);
        myRegistryStorage.registryIsActive = false;
        return true;
    }
       
    // Request access to the registry
    function requestRegistration(string _deviceName, string _deviceID, bytes32[] _deviceMeta) public registryIsActive deviceIDNotUsed(_deviceID) hasEnoughTokensAllowed(msg.sender, myRegistryStorage.tokenStakePerRegistration) {
        require(weeveRegistry.requestRegistration(myRegistryStorage, _deviceName, _deviceID, _deviceMeta, msg.sender));
        emit deviceRegistration(_deviceID, msg.sender);
        if(myRegistryStorage.devices[_deviceID].stakedTokens > 0) {
            emit deviceAccepted(_deviceID, msg.sender);
        }
    }

    // Simulating the approval from a validator (through oraclize)    
    function approveRegistrationRequest(string _deviceID) public registryIsActive isValidator(msg.sender) deviceExists(_deviceID) hasEnoughTokensAllowed(myRegistryStorage.devices[_deviceID].deviceOwner, myRegistryStorage.tokenStakePerRegistration) {
        require(weeveRegistry.approveRegistrationRequest(myRegistryStorage, _deviceID));
        emit deviceAccepted(_deviceID, myRegistryStorage.devices[_deviceID].deviceOwner);
    }
    
    // Unregistering your device
    function unregister(string _deviceID) public registryIsActive isOwnerOfDevice(_deviceID) deviceExists(_deviceID) {
        require(weeveRegistry.unregister(myRegistryStorage, msg.sender, _deviceID));
        emit deviceUnregistered(_deviceID, msg.sender);
    }
    
    // Challenge a device
    function raiseChallenge(string _deviceID, uint256 _commitDuration, uint256 _revealDuration) public registryIsActive deviceExists(_deviceID) {
        uint256 voteID = weeveRegistry.raiseChallenge(myRegistryStorage, _deviceID, msg.sender, _commitDuration, _revealDuration);
        require(voteID > 0);
        emit challengeRaised(voteID, _deviceID);
    }
        
    // Vote on a Challenge
    function voteOnChallenge(uint256 _voteID, uint256 _numberOfTokens, bytes32 _voteHash) public registryIsActive hasEnoughTokensAllowed(msg.sender, _numberOfTokens) {
        require(weeveRegistry.voteOnChallenge(myRegistryStorage, _voteID, msg.sender, _numberOfTokens, _voteHash));
    }

    // Reveal a vote on a challenge
    function revealVote(uint256 _voteID, uint256 _voteOption, uint256 _voteSalt) public {
        require(weeveRegistry.revealVote(myRegistryStorage, _voteID, msg.sender, _voteOption, _voteSalt));
        //bool voteOption = (_voteOption != 0);
        //emit votedOnChallenge(_voteID, msg.sender, voteOption, myRegistryStorage.votes[_voteID].voteDetails[msg.sender].stakedTokens);
    }
    
    // Resolve a vote after the reveal-phase is over
    function resolveChallenge(uint256 _voteID) public returns(bool) {
        require(weeveRegistry.resolveChallenge(myRegistryStorage, _voteID));
        //emit challengeResolved(_voteID, myRegistryStorage.votes[_voteID].deviceID, myRegistryStorage.votes[_voteID].votePassed, myRegistryStorage.votes[_voteID].votesFor, myRegistryStorage.votes[_voteID].votesAgainst);
    }
    
    // Claim reward of a vote
    function claimRewardOfVote(uint256 _voteID) public {
        require(weeveRegistry.claimRewardOfVote(myRegistryStorage, _voteID, msg.sender));
    }

    // In case of programming errors or other bugs the owner is able to refund staked tokens to it's owner
    // This will be removed once the contract is proven to work correctly
    function emergencyRefund(address _address) public onlyRegistryOwner {
        require(myRegistryStorage.totalStakedTokens[_address] > 0);
        myRegistryStorage.token.transfer(_address, myRegistryStorage.totalStakedTokens[_address]);
    }

    // Returns the total staked tokens of an address
    function getTotalStakeOfAddress(address _address) public view returns (uint256 totalStake){
        require(_address == msg.sender || msg.sender == myRegistryStorage.registryOwner);
        return myRegistryStorage.totalStakedTokens[_address];
    }
   
    // Returns the basic information of a device by its ID
    function getDeviceByID(string _deviceID) public view isOwnerOfDevice(_deviceID) deviceExists(_deviceID) returns (string deviceName, string deviceID, bytes32 hashOfDeviceData, address owner, uint256 stakedTokens, string registyState) {
        return (myRegistryStorage.devices[_deviceID].deviceName, myRegistryStorage.devices[_deviceID].deviceID, myRegistryStorage.devices[_deviceID].hashOfDeviceData, myRegistryStorage.devices[_deviceID].deviceOwner, myRegistryStorage.devices[_deviceID].stakedTokens, myRegistryStorage.devices[_deviceID].state);
    }

    // Returns the first part of the metainformation of a device by its ID
    function getDeviceMetainformation1ByID(string _deviceID) public view isOwnerOfDevice(_deviceID) deviceExists(_deviceID) returns (string sensors, string dataType, string manufacturer, string identifier, string description, string product) {
        return (myRegistryStorage.devices[_deviceID].metainformation.sensors, myRegistryStorage.devices[_deviceID].metainformation.dataType, myRegistryStorage.devices[_deviceID].metainformation.manufacturer, myRegistryStorage.devices[_deviceID].metainformation.identifier, myRegistryStorage.devices[_deviceID].metainformation.description, myRegistryStorage.devices[_deviceID].metainformation.product);
    }

    // Returns the second part of the metainformation of a device by its ID
    function getDeviceMetainformation2ByID(string _deviceID) public view isOwnerOfDevice(_deviceID) deviceExists(_deviceID) returns (string version, string serial, string cpu, string trustzone, string wifi) {
        return (myRegistryStorage.devices[_deviceID].metainformation.version, myRegistryStorage.devices[_deviceID].metainformation.serial, myRegistryStorage.devices[_deviceID].metainformation.cpu, myRegistryStorage.devices[_deviceID].metainformation.trustzone, myRegistryStorage.devices[_deviceID].metainformation.wifi);
    }

    // Returns the basic information of a device through the list of devices for an account
    function getDeviceIDFromUserArray(address _address, uint256 _devicePositionInArray) public view returns (string deviceID) {
        return myRegistryStorage.devicesOfUser[_address][_devicePositionInArray];
    }

    // Returns amount of devices that an address has in this registry
    function getDeviceCountOfUser(address _address) public view returns (uint256 numberOfDevices) {
        return myRegistryStorage.devicesOfUser[_address].length;
    }

    // Sets the amount of tokens to be staked for a registry
    function setStakePerRegistration(uint256 _numberOfTokens) public onlyRegistryOwner {
        myRegistryStorage.tokenStakePerRegistration = _numberOfTokens;
    }

    function addValidator(address _address) public registryIsActive onlyRegistryOwner {
        myRegistryStorage.validators[_address].validatorAddress = _address;
    }

    function removeValidator(address _address) public registryIsActive onlyRegistryOwner {
        delete myRegistryStorage.validators[_address];
    }

    function addArbiter(address _address) public registryIsActive onlyRegistryOwner {
        myRegistryStorage.arbiters[_address].arbiterAddress = _address;
    }

    function removeArbiter(address _address) public registryIsActive onlyRegistryOwner {
        delete myRegistryStorage.arbiters[_address];
    }
    
    function checkValidatorStatus(address _address) public view returns (bool status) {
        return myRegistryStorage.validators[_address].validatorAddress == _address;
    }

    function checkArbiterStatus(address _address) public view returns (bool status) {
        return myRegistryStorage.arbiters[_address].arbiterAddress == _address;
    }
    
    // Modifier: Checks whether the caller is the owner of this registry
    modifier onlyRegistryOwner {
        require(msg.sender == myRegistryStorage.registryOwner);
        _;
    }
    
    // Modifier: Checks whether the caller is an official weeve factory contract
    modifier onlyWeeveFactory {
        require(msg.sender == myRegistryStorage.weeveFactoryAddress);
        _;
    }
    
    // Modifier: Checks whether an address has enough tokens authorized to be withdrawn by the registry
    modifier hasEnoughTokensAllowed(address _address, uint256 _numberOfTokens) {
        require(myRegistryStorage.token.allowance(_address, address(this)) >= _numberOfTokens);
        _;
    }
    
    // Modifier: Checks whether an address is the owner of a device id
    modifier isOwnerOfDevice(string _deviceID) {
        require(myRegistryStorage.devices[_deviceID].deviceOwner == msg.sender);
        _;
    }

    // Modifier: Checks whether an address is a validator
    modifier isValidator(address _address) {
        require(myRegistryStorage.validators[_address].validatorAddress == _address);
        _;
    }

    // Modifier: Checks whether an address is an arbiter
    modifier isArbiter(address _address) {
        require(myRegistryStorage.arbiters[_address].arbiterAddress == _address);
        _;
    }
    
    // Modifier: Checks if a device id exists
    modifier deviceExists(string _deviceID) {
        require(bytes(myRegistryStorage.devices[_deviceID].deviceID).length > 0);
        _;
    }
    
    // Modifier: Checks if a device id is still free
    modifier deviceIDNotUsed(string _deviceID) {
        require(bytes(myRegistryStorage.devices[_deviceID].deviceID).length == 0);
        _;
    }

    // Modifier: Checks whether this registry is activated
    modifier registryIsActive() {
        require(myRegistryStorage.registryIsActive);
        _;
    }
}