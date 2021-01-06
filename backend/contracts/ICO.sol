pragma solidity ^0.6.3;

import "./StateMachine.sol";
import "./Access.sol";
import "@openzeppelin/contracts/token/ERC20//IERC20.sol";

contract ICO is StateMachine {
    
    IERC20 public ERC20token;
    uint private totalTokensSold;
    address private founder;
    
    uint private coinOfferingTimeStarted;
    uint private investingDuration;

    uint private pricePerToken;
    uint private minNumberOfTokens;
    
    mapping(address => uint) private investments;
    mapping(address => uint) private receivableTokens;


    constructor(address tokenAddress, uint _fundingDuration, uint _pricePerToken, uint _minNumberOfTokens) public { 
        founder = msg.sender;

        ERC20token = IERC20(tokenAddress);
        ERC20token.totalSupply();

        investingDuration = _fundingDuration;
        pricePerToken = _pricePerToken;
        minNumberOfTokens = _minNumberOfTokens;


        registerState("Investing", this.investing.selector, investing_distribution,this.distribution.selector);
        registerState("Investing", this.investing.selector, investing_refunding ,this.refunding.selector);
        registerState("Distribution", this.distribution.selector);
        registerState("Refunding", this.refunding.selector);

        coinOfferingTimeStarted = block.timestamp;
    }

    // Public Callable Functions
    function invest() state(this.investing.selector) payable external returns(uint) {
        uint sellableTokens = ERC20token.balanceOf(address(this));
        uint requestableTokens = msg.value / pricePerToken;

        require(sellableTokens > 0 && sellableTokens >= requestableTokens);
        
        investments[msg.sender] += msg.value;
        totalTokensSold += requestableTokens;

        receivableTokens[msg.sender] += requestableTokens; 

        next();

        return sellableTokens;
    }

    function requestToken() state(this.distribution.selector) external {
        uint amount = receivableTokens[msg.sender];
        ERC20token.transfer(msg.sender, amount);
    }

    function requestRefund() state(this.refunding.selector) external {
        uint refund = investments[msg.sender];
        investments[msg.sender] = 0;
        msg.sender.transfer(refund);
    }

    //State::INVESTING
    function investing() stateTransition(0) external {}

    // Condition
    function timeoutANDInvestmentReached() internal view returns(bool) {
        return block.timestamp >= coinOfferingTimeStarted + investingDuration && totalTokensSold >= minNumberOfTokens * pricePerToken;
    }
    function timeoutANDInvestmentNotReached() internal view returns(bool) {
        return block.timestamp >= coinOfferingTimeStarted + investingDuration && totalTokensSold < minNumberOfTokens * pricePerToken;
    }
    
    // Transaction
    function investing_distribution() condition(timeoutANDInvestmentReached) internal {
        uint balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(founder, balance - totalTokensSold);
    }

    function investing_refunding() condition(timeoutANDInvestmentNotReached) internal {
        uint balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(founder, balance);
    }

    //State::DISTRIBUTION
    function distribution() stateTransition(0) external {}

    //State::REFUNDING
    function refunding() stateTransition(0) external {}
}

