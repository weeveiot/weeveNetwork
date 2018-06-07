pragma solidity ^0.4.24;

import "./libraries/weeveMarketplaceLib.sol";

// An exemplary weeve marketplace contract
contract myMarketplace {    
    using SafeMath for uint;

    // General storage for the marketplace
    weeveMarketplace.MarketplaceStorage public myMarketplaceStorage;

    // Address of the weeve Factory
    address public weeveFactoryAddress = 0x0000000000000000000000000000000000000000;

    // Address of the WEEV token
    address public weeveTokenAddress = 0x0000000000000000000000000000000000000000;

    // Name of the marketplace
    string public marketplaceName;

    // Constructor (fired once upon creation)
    constructor() public {
        // Initially the marketplace is not active
        myMarketplaceStorage.marketplaceIsActive = false;
    }

    function initialize(string _name, uint256 _commission, address _owner) public returns(bool){
        // Only the weeve factory is able to initialise a marketplace
        require(msg.sender == weeveFactoryAddress);

        // Setting the name of the marketplace
        marketplaceName = _name;

        // Setting the owner of the marketplace
        require(_owner != address(0));
        myMarketplaceStorage.marketplaceOwner = _owner;

        // Number of all active devices
        myMarketplaceStorage.currentTrades = 0;

        // Activation of the marketplace
        myMarketplaceStorage.marketplaceIsActive = true;

        // Setting a commission percentage for each trade
        require(_commission >= 0 && _commission < 100);
        myMarketplaceStorage.commission = _commission;

        // Initializing the the balance of the currently collected commission
        myMarketplaceStorage.commissionBalance = 0;

        // Activation of the marketplace
        myMarketplaceStorage.marketplaceIsActive = true;

        // Setting the address of the WEEV erc20 token
        myMarketplaceStorage.token = ERC20(weeveTokenAddress);
        
        return true;
    }

    function closeMarketplace() public returns (bool) {
        // Only the weeve factory is able to initialise a registry
        require(msg.sender == weeveFactoryAddress);
        require(myMarketplaceStorage.currentTrades == 0);
        myMarketplaceStorage.marketplaceIsActive = false;
        return true;
    }

    // Posting a new trade offer to the marketplace by ID, price and amount
    function sell(string _tradeID, uint256 _price, uint256 _amount) public marketplaceIsActive {
        require(weeveMarketplace.sell(myMarketplaceStorage, _tradeID, _price, _amount));
    }

    // Accepting a trade offer from the marketplace by ID
    function buy(string _tradeID) public marketplaceIsActive {
        require(weeveMarketplace.buy(myMarketplaceStorage, _tradeID));
    }

    // Withdrawing the acrued commission from the marketplace as the owner
    function withdrawCommission(address _recipientAddress, uint256 _amountOfTokens) public marketplaceIsActive onlyMarketplaceOwner {
        // Number of tokens that will be withdrawn must be smaller or equal to the balance of the commission
        require(_amountOfTokens <= myMarketplaceStorage.commissionBalance);

        // Transfering the tokens to the recipient
        require(myMarketplaceStorage.token.transfer(_recipientAddress, _amountOfTokens));

        // Updating the commission balance
        myMarketplaceStorage.commissionBalance = myMarketplaceStorage.commissionBalance.sub(_amountOfTokens);
    }

    // Returns the trade information
    function getTrade(string _tradeID) public view returns(string tradeID, address seller, uint256 price, uint256 amount, bool paid) {
        return(myMarketplaceStorage.trades[_tradeID].tradeID, myMarketplaceStorage.trades[_tradeID].seller, myMarketplaceStorage.trades[_tradeID].price, myMarketplaceStorage.trades[_tradeID].amount, myMarketplaceStorage.trades[_tradeID].paid);
    }

    // Returns amount of devices that an address has in this marketplace
    function getTotalTradeCount() public view returns (uint256 numberOfCurrentTrades) {
        return myMarketplaceStorage.currentTrades;
    }

    // Changeing the commission of this marketplace as the owner
    function changeCommission(uint256 _commission) public marketplaceIsActive onlyMarketplaceOwner {
        require(_commission >= 0 && _commission < 100);
        myMarketplaceStorage.commission = _commission;
    }

    function addValidator(address _address) public marketplaceIsActive onlyMarketplaceOwner {
        myMarketplaceStorage.validators[_address].validatorAddress = _address;
    }

    function removeValidator(address _address) public marketplaceIsActive onlyMarketplaceOwner {
        delete myMarketplaceStorage.validators[_address];
    }

    function addArbiter(address _address) public marketplaceIsActive onlyMarketplaceOwner {
        myMarketplaceStorage.arbiters[_address].arbiterAddress = _address;
    }

    function removeArbiter(address _address) public marketplaceIsActive onlyMarketplaceOwner {
        delete myMarketplaceStorage.arbiters[_address];
    }
    
    function checkValidatorStatus(address _address) public view returns (bool status) {
        if(myMarketplaceStorage.validators[_address].validatorAddress == _address) {
            return true;
        } else {
            return false;
        }
    }

    function checkArbiterStatus(address _address) public view returns (bool status) {
        if(myMarketplaceStorage.arbiters[_address].arbiterAddress == _address) {
            return true;
        } else {
            return false;
        }
    }

    // Modifier: Checks whether the caller is the owner of this registry
    modifier onlyMarketplaceOwner {
        require(msg.sender == myMarketplaceStorage.marketplaceOwner);
        _;
    }

    // Modifier: Checks whether an address is a validator
    modifier isValidator(address _address) {
        require(myMarketplaceStorage.validators[_address].validatorAddress == _address);
        _;
    }

    // Modifier: Checks whether an address is an arbiter
    modifier isArbiter(address _address) {
        require(myMarketplaceStorage.arbiters[_address].arbiterAddress == _address);
        _;
    }

    // Modifier: Checks whether this marketplace is activated
    modifier marketplaceIsActive() {
        require(myMarketplaceStorage.marketplaceIsActive);
        _;
    }
}