pragma solidity ^0.4.23;

import "./weeveRegistryLib.sol";
import "./Owned.sol";

// An exemplary weeve Registry contract
contract myWeeveRegistry is Owned {    
    using SafeMath for uint;

    // General storage for the Registry
    weeveRegistry.RegistryStorage public myRegistryStorage;

    // Constructor (fired once upon creation)
    constructor(address _erc20Address) public {
        // Values for staking, just for testing purposes (not final)
        myRegistryStorage.tokenStakePerRegistry = 10;
        myRegistryStorage.tokenStakePerArbiter = 100;
        myRegistryStorage.tokenStakePerValidator = 100;

        // Setting the address of the erc20 token
        require(_erc20Address != address(0));
        myRegistryStorage.token = ERC20(_erc20Address);

        // Allocate an empty device to be able to delete 
        // devices by replacing them
        weeveRegistry.Device memory emptyDevice;
        myRegistryStorage.devices["empty"] = emptyDevice;
    }
       
    // Request access to the registry
    function requestRegistry(string _deviceName, string _deviceID, bytes32[] _deviceMeta) public deviceIDNotUsed(_deviceID) hasEnoughTokensAllowed(msg.sender, myRegistryStorage.tokenStakePerRegistry) {
        require(weeveRegistry.requestRegistry(myRegistryStorage, _deviceName, _deviceID, _deviceMeta, msg.sender));
    }

    // Simulating the approval from a validator (through oraclize)    
    function approveRegistry (string _deviceID) public isValidator(msg.sender) deviceExists(_deviceID) hasEnoughTokensAllowed(myRegistryStorage.devices[_deviceID].deviceOwner, myRegistryStorage.tokenStakePerRegistry) {
        require(weeveRegistry.approveRegistry(myRegistryStorage, _deviceID));      
    }
    
    // Unregistering your device
    function unregister (string _deviceID) public isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) {
        require(weeveRegistry.unregister(myRegistryStorage, msg.sender, _deviceID));
    }

    // In case of programming errors or other bugs the owner is able to refund staked tokens to it's owner
    // This will be removed once the contract is proven to work corecctly
    function emergencyRefund(address _address, uint _numberOfTokens) public onlyOwner {
        require(myRegistryStorage.totalStakedTokens[_address] > 0 && myRegistryStorage.totalStakedTokens[_address] >= _numberOfTokens);
        myRegistryStorage.token.transfer(_address, _numberOfTokens);
    }

    // Returns the total staked tokens of an address
    function getTotalStake(address _address) public view returns (uint256 totalStake){
        require(_address == msg.sender || msg.sender == owner);
        return myRegistryStorage.totalStakedTokens[_address];
    }

    // Returns the allowance of tokens of an address (just for testing-purposes)
    // (Possible warnings because of "view" declaration can be ignored.)
    function tokenGetAllowance(address _address) public view returns (uint allowance) {
        return myRegistryStorage.token.allowance(_address, address(this));
    }
    
    // Returns the basic information of a device by its ID
    function getDeviceByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string deviceName, string deviceID, string hashOfDeviceData, address owner, uint stakedTokens, string registyState) {
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
    function getDeviceIDFromArray(address _address, uint _devicePositionInArray) public view deviceExistsInArray(_address, _devicePositionInArray) returns (string deviceID) {
        return myRegistryStorage.devicesOfUser[_address][_devicePositionInArray];
    }

    // Returns amount of devices that an address has in this registry
    function getDeviceCountOfUser(address _address) public view returns (uint numberOfDevices) {
        return myRegistryStorage.devicesOfUser[_address].length;
    }

    // Returns the amount of tokens to be staked for a registry
    function getStakePerRegistry() public view returns (uint stakePerRegistry){
        return myRegistryStorage.tokenStakePerRegistry;
    }

    // Sets the amount of tokens to be staked for a registry
    function setStakePerRegistry(uint _numberOfTokens) public onlyOwner {
        myRegistryStorage.tokenStakePerRegistry = _numberOfTokens;
    }

    function addValidator(address _address) public onlyOwner {
        myRegistryStorage.validators[_address].validatorAddress = _address;
    }

    function removeValidator(address _address) public onlyOwner {
        delete myRegistryStorage.validators[_address];
    }

    function addArbiter(address _address) public onlyOwner {
        myRegistryStorage.arbiters[_address].arbiterAddress = _address;
    }

    function removeArbiter(address _address) public onlyOwner {
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
    modifier hasEnoughTokensAllowed(address _address, uint _numberOfTokens) {
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
    modifier deviceExistsInArray(address _address, uint _devicePositionInArray) {
        require(myRegistryStorage.devicesOfUser[_address].length > _devicePositionInArray);
        _;
    }
}