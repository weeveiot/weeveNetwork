pragma solidity ^0.4.24;

import "./SafeMath.sol";

/// Basic ERC20 Interface 
interface ERC20 {
    function totalSupply() external returns (uint);
    function balanceOf(address tokenOwner) external returns (uint balance);
    function allowance(address tokenOwner, address spender) external returns (uint remaining);
    function transfer(address to, uint tokens) external returns (bool success);
    function approve(address spender, uint tokens) external returns (bool success);
    function transferFrom(address from, address to, uint tokens) external returns (bool success);
}

library weeveMarketplace {
    using SafeMath for uint;

    struct Trade {
        string tradeID;
        address seller;
        uint256 price;        
        uint256 amount; 
        bool paid;
    }

    struct Validator {
        address validatorAddress;
        uint256 stakedTokens;
    }

    struct Arbiter {
        address arbiterAddress;
        uint256 stakedTokens;
    }
    
    struct MarketplaceStorage {
        // DeviceID maps to Device-Struct
        mapping (string => Trade) trades;

        // Address maps to array of strings
        mapping (address => string[]) sellsOfUser;

        // Address maps to array of strings
        mapping (address => string[]) buysOfUser;

        // Address to Validator-Struct
        mapping (address => Validator) validators;

        // Address to Arbiter-Struct
        mapping (address => Arbiter) arbiters;

        // Number of all active trades
        uint256 currentTrades;

        // Current activation state of the marketplace itself
        bool marketplaceIsActive;

        // Commission of each trade that will be deducted in percent
        uint256 commission;

        // Currently acrued commission of this marketplace
        uint256 commissionBalance;

        // Owner of this marketplace
        address marketplaceOwner;

        // Access to our token
        ERC20 token;
    }

    // Posting a new trade offer to the marketplace by ID, price and amount
    function sell(MarketplaceStorage storage myMarketplaceStorage, string _tradeID, uint256 _price, uint256 _amount) public returns (bool) {
        // Price and amount both need to be larger than zero
        require(_price > 0 && _amount > 0);

         // Allocate new trade
        weeveMarketplace.Trade memory newTrade;

        // Setting basic values of this trade
        newTrade.tradeID = _tradeID;
        newTrade.seller = msg.sender;
        newTrade.price = _price;
        newTrade.amount = _amount;

        // Adding this trade to the general trade mapping
        myMarketplaceStorage.trades[_tradeID] = newTrade;

        // Pushing this trade into the users sell-array
        myMarketplaceStorage.sellsOfUser[msg.sender].push(_tradeID);

        // Increasing the number of currently active trades by one
        myMarketplaceStorage.currentTrades = myMarketplaceStorage.currentTrades.add(1);

        return true;
    }

    // Accepting a trade offer from the marketplace by ID
    function buy(MarketplaceStorage storage myMarketplaceStorage, string _tradeID) public returns (bool) {
        // Sending the price of the trade to the markteplace
        require(myMarketplaceStorage.token.transferFrom(msg.sender, address(this), myMarketplaceStorage.trades[_tradeID].price));

        // Paying the seller of this trade (price minus commission)
        require(paySeller(myMarketplaceStorage, myMarketplaceStorage.trades[_tradeID].seller, myMarketplaceStorage.trades[_tradeID].price));

        // Adding this trade to the buys of the user
        myMarketplaceStorage.buysOfUser[msg.sender].push(_tradeID);

        // Marking this trade as paid
        myMarketplaceStorage.trades[_tradeID].paid = true;

        // Decreasing the number of currently active trades by oen
        myMarketplaceStorage.currentTrades = myMarketplaceStorage.currentTrades.sub(0);

        return true;
    }

    // Internal: paying the seller of a trade (with deduction of the commission)
    function paySeller(MarketplaceStorage storage myMarketplaceStorage, address _sellerAddress, uint256 _amountOfTokens) internal returns (bool) {
        // Calculating the commission on tokens
        uint256 deductedCommission = _amountOfTokens.mul(myMarketplaceStorage.commission).div(100);

        // Calculating the amount that will be paid to the seller
        uint256 payOut = _amountOfTokens.sub(deductedCommission);

        // Transfering the pay-out tokens to the seller
        require(myMarketplaceStorage.token.transfer(_sellerAddress, payOut));

        // Adding the commission to the commission-balance of this marketplace
        myMarketplaceStorage.commissionBalance = myMarketplaceStorage.commissionBalance.add(deductedCommission);

        return true;
    }
}