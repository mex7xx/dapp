pragma solidity ^0.6.3;

import "./StateMachine.sol";
import "@openzeppelin/contracts/token/ERC20//IERC20.sol";

contract ICO is StateMachine {
    
    IERC20 public ERC20token;
    address public founder;
    uint private totalTokensSold;
    
    uint private coinOfferingTimeStarted;
    uint private investingDuration;

    uint private pricePerToken;
    uint private minNumberOfTokens;
    
    mapping(address => uint) private investments;
    mapping(address => uint) private receivableTokens;


    constructor(address tokenAddress, uint _fundingDuration, uint _pricePerToken, uint _minNumberOfTokens) StateMachine() public { 
        founder = msg.sender;
        ERC20token = IERC20(tokenAddress);

        require(_minNumberOfTokens <= ERC20token.totalSupply(), "Total supply");

        investingDuration = _fundingDuration;
        pricePerToken = _pricePerToken;
        minNumberOfTokens = _minNumberOfTokens;

        registerState("Investing", this.investing.selector, investing_distribution, this.distribution.selector);
        registerState("Investing", this.investing.selector, investing_refunding, this.refunding.selector);
        registerState("Distribution", this.distribution.selector);
        registerState("Refunding", this.refunding.selector);
        
        coinOfferingTimeStarted = block.timestamp;
    }
    event Debug(uint);
    // Public Callable Functions
    function invest() state(this.investing.selector) payable external {
        require(msg.value != 0, ' 0 investmnets made'); 
        uint sellableTokens = ERC20token.balanceOf(address(this)) - totalTokensSold;
        
        uint requestedTokens = msg.value / pricePerToken;
        emit Debug(msg.value);
        emit Debug(pricePerToken);
        emit Debug(requestedTokens);

        require(sellableTokens > 0, 'all tokens already sold');
        require(sellableTokens >= requestedTokens, 'not enougth sellable Tokens to invest all provided funds');
        
        investments[msg.sender] += msg.value;
        receivableTokens[msg.sender] += requestedTokens; 
        totalTokensSold += requestedTokens;

        next();
    }

    function requestToken() state(this.distribution.selector) external {
        uint amount = receivableTokens[msg.sender];
        Debug(amount);
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
        // TODO: Make Burnable
        
        uint balance = ERC20token.balanceOf(address(this));
        ERC20token.transfer(founder, balance - totalTokensSold);

        // Send ether to AssetToken
        
        address destination = address(ERC20token);
        (payable(destination)).transfer(address(this).balance);
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
