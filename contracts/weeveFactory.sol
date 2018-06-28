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
    function initialize(string _name, uint256 _stakePerRegistration, uint256 _stakePerArbiter, uint256 _stakePerValidator, address _owner) external returns (bool);
    function closeRegistry() external returns (bool);
    function getTotalDeviceCount() external returns (uint256 numberOfDevices);
}

// Interface for our marketplaces
interface weeveMarketplace {
    function initialize(string _name, uint256 _commission, address _owner) external returns (bool);
    function closeMarketplace() external returns (bool);
    function getTotalTradeCount() external returns (uint256 numberOfCurrentTrades);
}

// Interface for our voting scheme
interface weeveVoting {  
    function addWeeveContract(address _newContract) external returns (bool success);
    function removeWeeveContract(address _obsoleteContract) external returns (bool success);
}

contract weeveFactory is Owned {
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
    }

    struct Marketplace {
        uint256 id;
        string name;
        address owner;
        address marketplaceAddress;
        uint256 stakedTokens;
        bool active;
    }

    // Array of all registries
    Registry[] public allRegistries;

    // Array of all registries
    Marketplace[] public allMarketplaces;

    // Our ERC20 token
    ERC20 public token;

    // Our voting contract
    weeveVoting public vote;

    // Tokens that need to be staked for each registry (soon to be dynamic)
    uint256 tokensPerRegistryCreation;

    // Tokens that need to be staked for each registry (soon to be dynamic)
    uint256 tokensPerMarketplaceCreation;

    constructor(address _erc20Address, address _votingAddress) public {
        require(_erc20Address != address(0));
        require(_erc20Address != address(0));
        
        // Setting the address of our WEEV token contract
        token = ERC20(_erc20Address);        
        
        // Setting the address of our voting contract
        vote = weeveVoting(_votingAddress);

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
        // Only if the amount of active devices is zero
        require(theRegistry.getTotalDeviceCount() == 0);
        // Calling the closeRegistry function of this registry
        require(theRegistry.closeRegistry());
        // Unstaking the remaining tokens
        require(unstakeTokens(allRegistries[_id].owner, allRegistries[_id].stakedTokens));
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
        allMarketplaces[_id].stakedTokens = 0;
        allMarketplaces[_id].active = false;
        // TODO: Disable Marketplace
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