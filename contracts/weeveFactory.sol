pragma solidity ^0.4.23;

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
    function initialize(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator) external returns (bool);
    function requestRegistration(string _deviceName, string _deviceID, bytes32[] _deviceMeta) external;
    function approveRegistrationRequest(string _deviceID) external;
    function unregister(string _deviceID) external;
    function emergencyRefund(address _address, uint256 _numberOfTokens) external;
    function getTotalStakeOfAddress(address _address) external returns (uint256 totalStake);
    function getDeviceByID(string _deviceID) external returns (string deviceName, string deviceID, string hashOfDeviceData, address owner, uint256 stakedTokens, string registyState);
    function getDeviceMetainformation1ByID(string _deviceID) external returns (string sensors, string dataType, string manufacturer, string identifier, string description, string product);
    function getDeviceMetainformation2ByID(string _deviceID) external returns (string version, string serial, string cpu, string trustzone, string wifi);
    function getDeviceIDFromArray(address _address, uint256 _devicePositionInArray) external returns (string deviceID);
    function getTotalDeviceCount() external returns (uint256 numberOfDevices);
    function getDeviceCountOfUser(address _address) external returns (uint256 numberOfDevices);
    function getStakePerRegistration() external returns (uint256 stakePerRegistry);
    function setStakePerRegistration(uint256 _numberOfTokens) external;
    function addValidator(address _address) external;
    function removeValidator(address _address) external;
    function addArbiter(address _address) external;
    function removeArbiter(address _address)external;    
    function checkValidatorStatus(address _address) external returns (bool status);
    function checkArbiterStatus(address _address) external returns (bool status);
}

contract weeveFactory is Owned {
    using SafeMath for uint;

    // The current hash of the valid registry code
    // (Will be replaced by an array of hashes soon-ish)
    bytes32 public weeveRegistryHash;

    // Mapping from address to uint-array (maps an address to all of its registry id's)
    mapping(address => uint256[]) userRegistries;

    struct Registry {
        uint256 id;
        string name;
        address owner;
        address registryAddress;
        uint256 stakedTokens;
        bool active;
    }

    // Array of all registries
    Registry[] public allRegistries;

    // Our ERC20 token
    ERC20 public token;

    // Tokens that need to be staked for each registry (soon to be dynamic)
    uint256 tokensPerRegistryCreation;

    constructor(address _erc20Address) public {
        require(_erc20Address != address(0));
        
        // Setting the address of our WEEV token contract
        token = ERC20(_erc20Address);

        // weeve Registry code hash (placeholder)
        weeveRegistryHash = 0x0000000000000000000000000000000000000000000000000000000000000000;

        // Tokens per Registry (soon to by dynamic)
        tokensPerRegistryCreation = 1000;
    }

    // Setting a new valid registry code hash as an owner
    function setNewRegistryHash(bytes _contractCode) public onlyOwner {
        weeveRegistryHash = keccak256(_contractCode);
    }

    // Creating a new registry
    function createRegistry(string _name, bytes _contractCode) public hasEnoughTokensAllowed(msg.sender, tokensPerRegistryCreation) returns (address newRegistryAddress) {
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

        // Deploying the contract
        newRegistry.registryAddress = deployRegistry(_contractCode);
        require(newRegistry.registryAddress != address(0));

        // Activating the new registry
        weeveRegistry newWeeveRegistry = weeveRegistry(newRegistry.registryAddress);
        require(newWeeveRegistry.initialize(_name, 10, 12, 13));

        // The new registry is now active
        newRegistry.active = true;

        // Adding the registry to the users registry array
        userRegistries[msg.sender].push(newRegistry.id);

        // Adding the registry to the general registry array
        allRegistries.push(newRegistry);
        
        // Returning the registries address
        return newRegistry.registryAddress;
    }
    
    // Internal function to deploy bytecode to the blockchain
    function deployRegistry(bytes _contractCode) internal returns (address addr) {
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
        // Only if the amount of active devices is zero
        require(theRegistry.getTotalDeviceCount() == 0);
        // Unstaking the remaining tokens
        require(unstakeTokens(allRegistries[_id].owner, allRegistries[_id].stakedTokens));
        allRegistries[_id].stakedTokens = 0;
        allRegistries[_id].active = false;
        // TODO: Disable Registry
    }

    // Stake tokens through our ERC20 contract
    function stakeTokens(address _address, uint256 _numberOfTokens) internal returns(uint256) {
        require(token.transferFrom(_address, address(this), _numberOfTokens));
        return _numberOfTokens;
    }

    // Unstake tokens through our ERC20 contract
    function unstakeTokens(address _address, uint256 _numberOfTokens) internal returns(bool) {
        require(token.balanceOf(address(this)) >= _numberOfTokens);
        require(token.transfer(_address, _numberOfTokens));
        return true;
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
}