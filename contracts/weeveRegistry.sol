pragma solidity ^0.4.21;

// Math operations with safety checks that throw on error
// Source: OpenZeppelin Framework
library SafeMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        assert(c >= a);
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        assert(b <= a);
        return a - b;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        if (a == 0) {
            return 0;
        }
        c = a * b;
        assert(c / a == b);
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // assert(b > 0); // Solidity automatically throws when dividing by 0
        // uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold
        return a / b;
    }
}

// The Owned contract has an owner address, and provides basic authorization control functions
// Source: OpenZeppelin Framework
contract Owned {
    address public owner;
    address public newOwner;

    event OwnershipTransferred(address indexed _from, address indexed _to);

    function Owned() public {
        owner = msg.sender;
    }

    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    function transferOwnership(address _newOwner) public onlyOwner {
        require(_newOwner != address(0));
        newOwner = _newOwner;
    }
    function acceptOwnership() public {
        require(msg.sender == newOwner);
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
        newOwner = address(0);
    }
}

// Basic ERC20 Interface 
contract ERC20 {
    function totalSupply() public constant returns (uint);
    function balanceOf(address tokenOwner) public constant returns (uint balance);
    function allowance(address tokenOwner, address spender) public constant returns (uint remaining);
    function transfer(address to, uint tokens) public returns (bool success);
    function approve(address spender, uint tokens) public returns (bool success);
    function transferFrom(address from, address to, uint tokens) public returns (bool success);

    event Transfer(address indexed from, address indexed to, uint tokens);
    event Approval(address indexed tokenOwner, address indexed spender, uint tokens);
}

// An exemplary weeve Registry contract
contract weeveRegistry is Owned {
    
    using SafeMath for uint;

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

    struct Device {
        string deviceName;
        string deviceID;
        string hashOfDeviceData;
        address deviceOwner; 
        uint stakedTokens;
        string state;
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
        uint stakedTokens;
    }

    struct Arbiter {
        address arbiterAddress;
        uint stakedTokens;
    }
    
    // Count of Tokens that need to be staked
    // (Not final, just values for testing purposes)
    uint tokenStakePerRegistry = 10;
    uint tokenStakePerValidator = 100;
    uint tokenStakePerArbiter = 100;
    
    // Access to our ERC20 WEEV token
    ERC20 public token;

    // Initialisation-Function (fired once upon creation)
    function weeveRegistry() public {
        // Allocate an empty device to be able to delete 
        // devices by replacing them
        Device memory emptyDevice;
        devices["empty"] = emptyDevice;
    }
    
    // Set the Address of our ERC20-Token
    // (This will be replaced with a constructor function soon)
    function setERC20Address(address _address) public onlyOwner {
        token = ERC20(_address);
    }
    
    // Request access to the registry
    function requestRegistry(string _deviceName, string _deviceID, bytes32[] _deviceMeta) public deviceIDNotUsed(_deviceID) hasEnoughTokensAllowed(msg.sender, tokenStakePerRegistry) {
        // Allocate new device
        Device memory newDevice;
        newDevice.deviceName = _deviceName;
        newDevice.deviceID = _deviceID;
        newDevice.deviceOwner = msg.sender;
        newDevice.stakedTokens = 0;
        Metainformation memory metainformation;
        newDevice.metainformation = metainformation;
        // Add device to mapping
        devices[_deviceID] = newDevice;
        devicesOfUser[msg.sender].push(_deviceID);
        
        // If enough values are given, the information will be checked directly in this contract
        if(_deviceMeta.length == 11) {
            devices[_deviceID].metainformation = validateRegistry(_deviceMeta);
            if(stakeTokens(msg.sender, _deviceID, tokenStakePerRegistry)) {
                devices[_deviceID].state = "accepted";
            } else {
                devices[_deviceID].state = "unproven";
            }
        // If only a hash (e.g. IPFS) is given, the request will be manually validated
        } else if(_deviceMeta.length == 1) {
            devices[_deviceID].hashOfDeviceData = bytes32ToString(_deviceMeta[0]);
            devices[_deviceID].state = "unproven";
        } else {
            revert();  
        } 
    }
    
    // Validate a registry-request with enough values
    function validateRegistry(bytes32[] _deviceMeta) internal pure returns (Metainformation validMetainformation) {
        Metainformation memory metainformation;
        metainformation.sensors = bytes32ToString(_deviceMeta[0]);
        metainformation.dataType = bytes32ToString(_deviceMeta[1]);
        metainformation.manufacturer = bytes32ToString(_deviceMeta[2]);
        metainformation.identifier = bytes32ToString(_deviceMeta[3]);
        metainformation.description = bytes32ToString(_deviceMeta[4]);
        metainformation.product = bytes32ToString(_deviceMeta[5]);
        metainformation.version = bytes32ToString(_deviceMeta[6]);
        metainformation.serial = bytes32ToString(_deviceMeta[7]);
        metainformation.cpu = bytes32ToString(_deviceMeta[8]);
        metainformation.trustzone = bytes32ToString(_deviceMeta[9]);
        metainformation.wifi = bytes32ToString(_deviceMeta[10]);
        return metainformation;
    }

    // Simulating the approval from a validator (through oraclize)    
    function approveRegistry (string _deviceID) public isValidator(msg.sender) deviceExists(_deviceID) hasEnoughTokensAllowed(devices[_deviceID].deviceOwner, tokenStakePerRegistry) {
        require(devices[_deviceID].stakedTokens == 0);
        if(stakeTokens(devices[_deviceID].deviceOwner, _deviceID, tokenStakePerRegistry)) {
            devices[_deviceID].state = "accepted";
        }
    }
    
    // Unregistering your device
    function unregister (string _deviceID) public isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) {
        unstakeTokens(msg.sender, _deviceID);
        devices[_deviceID] = devices["empty"];
        deleteFromArray(_deviceID);
    }
    
    // Helper function: deleting a device from a users array
    function deleteFromArray(string _value) internal {
        require(devicesOfUser[msg.sender].length > 0);
        for(uint i = 0; i < devicesOfUser[msg.sender].length; i++) {
            if(keccak256(devicesOfUser[msg.sender][i]) == keccak256(_value)) {
                if(i != devicesOfUser[msg.sender].length-1) {
                    devicesOfUser[msg.sender][i] = devicesOfUser[msg.sender][devicesOfUser[msg.sender].length-1];
                }
                delete devicesOfUser[msg.sender][devicesOfUser[msg.sender].length-1];
                devicesOfUser[msg.sender].length--;
                break;
            }
        }
    }

    // Stake tokens through our ERC20 contract
    function stakeTokens(address _address, string _deviceID, uint _numberOfTokens) internal returns(bool) {
        token.transferFrom(_address, address(this), _numberOfTokens);
        devices[_deviceID].stakedTokens = devices[_deviceID].stakedTokens.add(_numberOfTokens);
        totalStakedTokens[_address] = totalStakedTokens[_address].add(_numberOfTokens);
        return true;
    }
    
    // Unstake tokens through our ERC20 contract
    function unstakeTokens(address _address, string _deviceID) internal {
        if(devices[_deviceID].stakedTokens > 0) {
            if(token.transfer(_address, devices[_deviceID].stakedTokens)) {
                totalStakedTokens[_address] = totalStakedTokens[_address].sub(devices[_deviceID].stakedTokens);
                devices[_deviceID].stakedTokens = devices[_deviceID].stakedTokens.sub(devices[_deviceID].stakedTokens); 
            } 
        }
    }

    // In case of programming errors or other bugs the owner is able to refund staked tokens to it's owner
    // This will be removed once the contract is proven to work corecctly
    function emergencyRefund(address _address, uint _numberOfTokens) public onlyOwner {
        require(totalStakedTokens[_address] > 0 && totalStakedTokens[_address] >= _numberOfTokens);
        token.transfer(_address, _numberOfTokens);
    }

    // Returns the total staked tokens of an address
    function getTotalStake(address _address) public view returns (uint256 totalStake){
        require(_address == msg.sender || msg.sender == owner);
        return totalStakedTokens[_address];
    }

    // Returns the allowance of tokens of an address (just for testing-purposes)
    function tokenGetAllowance(address _address) public view returns (uint allowance) {
        return token.allowance(_address, address(this));
    }
    
    // Returns the basic information of a device by its ID
    function getDeviceByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string deviceName, string deviceID, string hashOfDeviceData, address owner, uint stakedTokens, string registyState) {
        return (devices[_deviceID].deviceName, devices[_deviceID].deviceID, devices[_deviceID].hashOfDeviceData, devices[_deviceID].deviceOwner, devices[_deviceID].stakedTokens, devices[_deviceID].state);
    }

    // Returns the first part of the metainformation of a device by its ID
    function getDeviceMetainformation1ByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string sensors, string dataType, string manufacturer, string identifier, string description, string product) {
        return (devices[_deviceID].metainformation.sensors, devices[_deviceID].metainformation.dataType, devices[_deviceID].metainformation.manufacturer, devices[_deviceID].metainformation.identifier, devices[_deviceID].metainformation.description, devices[_deviceID].metainformation.product);
    }

    // Returns the second part of the metainformation of a device by its ID
    function getDeviceMetainformation2ByID(string _deviceID) public view isOwnerOfDevice(msg.sender, _deviceID) deviceExists(_deviceID) returns (string version, string serial, string cpu, string trustzone, string wifi) {
        return (devices[_deviceID].metainformation.version, devices[_deviceID].metainformation.serial, devices[_deviceID].metainformation.cpu, devices[_deviceID].metainformation.trustzone, devices[_deviceID].metainformation.wifi);
    }

    // Returns the basic information of a device through the list of devices for an account
    function getDeviceIDFromArray(address _address, uint _devicePositionInArray) public view deviceExistsInArray(_address, _devicePositionInArray) returns (string deviceID) {
        return devicesOfUser[_address][_devicePositionInArray];
    }

    // Returns amount of devices that an address has in this registry
    function getDeviceCountOfUser(address _address) public view returns (uint numberOfDevices) {
        return devicesOfUser[_address].length;
    }

    // Returns the amount of tokens to be staked for a registry
    function getStakePerRegistry() public view returns (uint stakePerRegistry){
        return tokenStakePerRegistry;
    }

    // Sets the amount of tokens to be staked for a registry
    function setStakePerRegistry(uint _numberOfTokens) public onlyOwner {
        tokenStakePerRegistry = _numberOfTokens;
    }

    function addValidator(address _address) public onlyOwner {
        validators[_address].validatorAddress = _address;
    }

    function removeValidator(address _address) public onlyOwner {
        delete validators[_address];
    }

    function addArbiter(address _address) public onlyOwner {
        arbiters[_address].arbiterAddress = _address;
    }

    function removeArbiter(address _address) public onlyOwner {
        delete arbiters[_address];
    }
    
    function checkValidatorStatus(address _address) public view returns (bool status) {
        if(validators[_address].validatorAddress == _address) {
            return true;
        } else {
            return false;
        }
    }

    function checkArbiterStatus(address _address) public view returns (bool status) {
        if(arbiters[_address].arbiterAddress == _address) {
            return true;
        } else {
            return false;
        }
    }
    
    // Modifier: Checks whether an address has enough tokens authorized to be withdrawn by the registry
    modifier hasEnoughTokensAllowed(address _address, uint _numberOfTokens) {
        require(token.allowance(_address, address(this)) >= _numberOfTokens);
        _;
    }
    
    // Modifier: Checks whether an address is the owner of a device id
    modifier isOwnerOfDevice(address _address, string _deviceID){
        require(devices[_deviceID].deviceOwner == _address);
        _;
    }

    // Modifier: Checks whether an address is a validator
    modifier isValidator(address _address) {
        require(validators[_address].validatorAddress == _address);
        _;
    }

    // Modifier: Checks whether an address is an arbiter
    modifier isArbiter(address _address) {
        require(arbiters[_address].arbiterAddress == _address);
        _;
    }
    
    // Modifier: Checks if a device id exists
    modifier deviceExists(string _deviceID) {
        require(bytes(devices[_deviceID].deviceID).length > 0);
        _;
    }
    
    // Modifier: Checks if a device id is still free
    modifier deviceIDNotUsed(string _deviceID) {
        require(bytes(devices[_deviceID].deviceID).length == 0);
        _;
    }

    // Modifier: Temporary helper function
    modifier deviceExistsInArray(address _address, uint _devicePositionInArray) {
        require(devicesOfUser[_address].length > _devicePositionInArray);
        _;
    }
    
    // Helper function: converting bytes32 to a string
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