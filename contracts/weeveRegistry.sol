pragma solidity ^0.4.23;

import "./libraries/weeveRegistryLib.sol";
import "./libraries/Owned.sol";

// An exemplary weeve Registry contract
contract myRegistry is Owned {    
    using SafeMath for uint;

    // General storage for the Registry
    weeveRegistry.RegistryStorage public myRegistryStorage;

    // Address of the weeve Factory
    address public weeveFactoryAddress = 0x0000000000000000000000000000000000000000;

    // Address of the WEEV token
    address public weeveTokenAddress = 0x0000000000000000000000000000000000000000;

    // Name of the registry
    string public registryName;

    // Constructor (fired once upon creation)
    constructor() public {
        // Initialle the registry is not active
        myRegistryStorage.registryIsActive = false;

        // Allocate an empty device to be able to delete devices by replacing them
        weeveRegistry.Device memory emptyDevice;
        myRegistryStorage.devices["empty"] = emptyDevice;
    }

    function initialize(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator) public returns(bool){
        require(msg.sender == weeveFactoryAddress);
        // Setting the name of the registry
        registryName = _name;

        // Values for staking, just for testing purposes (not final)
        myRegistryStorage.tokenStakePerRegistration = _stakePerRegistration;
        myRegistryStorage.tokenStakePerArbiter = _stakePerArbiter;
        myRegistryStorage.tokenStakePerValidator = _stakePerValidator;

        // Number of all active devices
        myRegistryStorage.activeDevices = 0;

        // Activation of the registry
        myRegistryStorage.registryIsActive = true;

        // Setting the address of the WEEV erc20 token
        myRegistryStorage.token = ERC20(weeveTokenAddress);
        
        return true;
    }
       
    // Request access to the registry
    function requestRegistration(string _deviceName, string _deviceID, bytes32[] _deviceMeta) public registryIsActive deviceIDNotUsed(_deviceID) hasEnoughTokensAllowed(msg.sender, myRegistryStorage.tokenStakePerRegistration) {
        require(weeveRegistry.requestRegistration(myRegistryStorage, _deviceName, _deviceID, _deviceMeta, msg.sender));
    }

    // Simulating the approval from a validator (through oraclize)    
    function approveRegistrationRequest(string _deviceID) public registryIsActive isValidator(msg.sender) deviceExists(_deviceID) hasEnoughTokensAllowed(myRegistryStorage.devices[_deviceID].deviceOwner, myRegistryStorage.tokenStakePerRegistration) {
        require(weeveRegistry.approveRegistrationRequest(myRegistryStorage, _deviceID));      
    }
    
    // Unregistering your device
    function unregister(string _deviceID) public registryIsActive isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) {
        require(weeveRegistry.unregister(myRegistryStorage, msg.sender, _deviceID));
    }

    // In case of programming errors or other bugs the owner is able to refund staked tokens to it's owner
    // This will be removed once the contract is proven to work correctly
    // TODO: Remove stake on a per-device-basis and deactivate the device accordingly
    function emergencyRefund(address _address, uint256 _numberOfTokens) public onlyOwner {
        require(myRegistryStorage.totalStakedTokens[_address] > 0 && myRegistryStorage.totalStakedTokens[_address] >= _numberOfTokens);
        myRegistryStorage.token.transfer(_address, _numberOfTokens);
    }

    // Returns the total staked tokens of an address
    function getTotalStakeOfAddress(address _address) public view returns (uint256 totalStake){
        require(_address == msg.sender || msg.sender == owner);
        return myRegistryStorage.totalStakedTokens[_address];
    }
   
    // Returns the basic information of a device by its ID
    function getDeviceByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string deviceName, string deviceID, string hashOfDeviceData, address owner, uint256 stakedTokens, string registyState) {
        return (myRegistryStorage.devices[_deviceID].deviceName, myRegistryStorage.devices[_deviceID].deviceID, myRegistryStorage.devices[_deviceID].hashOfDeviceData, myRegistryStorage.devices[_deviceID].deviceOwner, myRegistryStorage.devices[_deviceID].stakedTokens, myRegistryStorage.devices[_deviceID].state);
    }

    // Returns the first part of the metainformation of a device by its ID
    function getDeviceMetainformation1ByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string sensors, string dataType, string manufacturer, string identifier, string description, string product) {
        return (myRegistryStorage.devices[_deviceID].metainformation.sensors, myRegistryStorage.devices[_deviceID].metainformation.dataType, myRegistryStorage.devices[_deviceID].metainformation.manufacturer, myRegistryStorage.devices[_deviceID].metainformation.identifier, myRegistryStorage.devices[_deviceID].metainformation.description, myRegistryStorage.devices[_deviceID].metainformation.product);
    }

    // Returns the second part of the metainformation of a device by its ID
    function getDeviceMetainformation2ByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string version, string serial, string cpu, string trustzone, string wifi) {
        return (myRegistryStorage.devices[_deviceID].metainformation.version, myRegistryStorage.devices[_deviceID].metainformation.serial, myRegistryStorage.devices[_deviceID].metainformation.cpu, myRegistryStorage.devices[_deviceID].metainformation.trustzone, myRegistryStorage.devices[_deviceID].metainformation.wifi);
    }

    // Returns the basic information of a device through the list of devices for an account
    function getDeviceIDFromUserArray(address _address, uint256 _devicePositionInArray) public view deviceExistsInUserArray(_address, _devicePositionInArray) returns (string deviceID) {
        return myRegistryStorage.devicesOfUser[_address][_devicePositionInArray];
    }

    // Returns amount of devices that an address has in this registry
    function getTotalDeviceCount() public view returns (uint256 numberOfDevices) {
        return myRegistryStorage.activeDevices;
    }

    // Returns amount of devices that an address has in this registry
    function getDeviceCountOfUser(address _address) public view returns (uint256 numberOfDevices) {
        return myRegistryStorage.devicesOfUser[_address].length;
    }

    // Returns the amount of tokens to be staked for a registry
    function getStakePerRegistration() public view returns (uint256 stakePerRegistry){
        return myRegistryStorage.tokenStakePerRegistration;
    }

    // Sets the amount of tokens to be staked for a registry
    function setStakePerRegistration(uint256 _numberOfTokens) public onlyOwner {
        myRegistryStorage.tokenStakePerRegistration = _numberOfTokens;
    }

    function addValidator(address _address) public registryIsActive onlyOwner() {
        myRegistryStorage.validators[_address].validatorAddress = _address;
    }

    function removeValidator(address _address) public registryIsActive onlyOwner {
        delete myRegistryStorage.validators[_address];
    }

    function addArbiter(address _address) public registryIsActive onlyOwner {
        myRegistryStorage.arbiters[_address].arbiterAddress = _address;
    }

    function removeArbiter(address _address) public registryIsActive onlyOwner {
        delete myRegistryStorage.arbiters[_address];
    }
    
    function checkValidatorStatus(address _address) public view returns (bool status) {
        if(myRegistryStorage.validators[_address].validatorAddress == _address) {
            return true;
        } else {
            return false;
        }
    }

    function checkArbiterStatus(address _address) public view returns (bool status) {
        if(myRegistryStorage.arbiters[_address].arbiterAddress == _address) {
            return true;
        } else {
            return false;
        }
    }
    
    // Modifier: Checks whether an address has enough tokens authorized to be withdrawn by the registry
    modifier hasEnoughTokensAllowed(address _address, uint256 _numberOfTokens) {
        require(myRegistryStorage.token.allowance(_address, address(this)) >= _numberOfTokens);
        _;
    }
    
    // Modifier: Checks whether an address is the owner of a device id
    modifier isOwnerOfDevice(address _address, string _deviceID){
        require(myRegistryStorage.devices[_deviceID].deviceOwner == _address);
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

    // Modifier: Temporary helper function
    modifier deviceExistsInUserArray(address _address, uint256 _devicePositionInArray) {
        require(myRegistryStorage.devicesOfUser[_address].length > _devicePositionInArray);
        _;
    }

    // Modifier: Checks whether this registry is activated
    modifier registryIsActive() {
        require(myRegistryStorage.registryIsActive);
        _;
    }
}