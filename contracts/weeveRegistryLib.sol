pragma solidity ^0.4.23;

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

library weeveRegistry {
    using SafeMath for uint;

    struct Device {
        string deviceName;
        string deviceID;        
        address deviceOwner; 
        uint256 stakedTokens;
        string state;
        string hashOfDeviceData;
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
    
    struct RegistryStorage {
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

        // Address to number of staked tokens per use
        mapping (address => uint) totalStakedTokens;

        // Count of Tokens that need to be staked
        uint256 tokenStakePerRegistration;
        uint256 tokenStakePerValidator;
        uint256 tokenStakePerArbiter;

        // Number of all active devices
        uint256 activeDevices;

        // Current activation state of the registry itself
        bool registryIsActive;

        // Access to our token
        ERC20 token;
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
            myRegistryStorage.devices[_deviceID].hashOfDeviceData = bytes32ToString(_deviceMeta[0]);
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
    function approveRegistrationRequest(RegistryStorage storage myRegistryStorage, string _deviceID) public returns(bool){
        require(myRegistryStorage.devices[_deviceID].stakedTokens == 0);
        require(stakeTokens(myRegistryStorage, myRegistryStorage.devices[_deviceID].deviceOwner, _deviceID, myRegistryStorage.tokenStakePerRegistration));
        myRegistryStorage.devices[_deviceID].state = "accepted";
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.add(1);
        return true;
    }

    // Unregistering your device
    function unregister(RegistryStorage storage myRegistryStorage, address _sender, string _deviceID) public returns(bool){
        require(unstakeTokens(myRegistryStorage, _sender, _deviceID));
        myRegistryStorage.devices[_deviceID] = myRegistryStorage.devices["empty"];
        deleteFromArray(myRegistryStorage, _sender, _deviceID);
        myRegistryStorage.activeDevices = myRegistryStorage.activeDevices.sub(1);
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
            if(keccak256(myRegistryStorage.devicesOfUser[_address][i]) == keccak256(_value)) {
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