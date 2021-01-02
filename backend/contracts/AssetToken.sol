pragma solidity ^0.6.3;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StateMachine.sol";
import "./Access.sol";
import "./Election.sol";
import "./ERC20share.sol";


contract AssetToken is StateMachine, AccessControl, ERC20share {

    enum Role {
        SHAREHOLDER,
        SUPERVISOR,
        CEO
    }

    uint[] CEO = [uint(Role.CEO)];
    uint[] SUPERVISOR = [uint(Role.SUPERVISOR)];
    uint[] SHAREHOLDER = [uint(Role.SHAREHOLDER)];


    string companyName;
    address public currentCEO;
    uint public numberOfSupervisors;
    address[] public supervisors;                
    
    // Election Cycle
    Election public election;
    mapping(address => bool) reelection; 
    uint lastElection;
    address[] internal newSupervisors;
    
    // Dividend Cycle
    uint lockedBalance;                 //TODO: Problem reset after Fail!!  
    mapping(address => uint) dividend; //for shareholder
    uint lastTimeDividend;

    uint proposedDividend;
    bool proposed;
    mapping(address => uint8) approved; //by supervisor


    // constructor sets Company Name, Proposal for SB
    constructor(uint initialSupply, string memory _companyName, string memory _symbol, uint _numberOfSupervisors) 
    AccessControl() StateMachine() ERC20share(initialSupply, _companyName, _symbol) public {
        require(_numberOfSupervisors%2 == 1);
        numberOfSupervisors = _numberOfSupervisors;
        
        registerState("START", this.start.selector, start_electionStarted, this.electionStarted.selector);
        registerState("START", this.start.selector, start_dividendProposed, this.dividendProposed.selector);

        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted1, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);

        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start, this.start.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start1, this.start.selector);

        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start, this.start.selector);
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start, this.start.selector);
    }


    // External Callable Functions
    //---------------------------------------------------------------------------------------------
    // CEO Functions
    function sendEther(address payable _destination, uint _amount) access(CEO) external {
        require(_amount <= address(this).balance - lockedBalance);
        _destination.transfer(_amount);
    }

    function changeCompanyName(string calldata _companyName) access(CEO) external {
        companyName = _companyName;
    }
    
    // Shareholder Functions
    function requestDividend() access(SHAREHOLDER) external {
        lockedBalance -= dividend[msg.sender];
        msg.sender.transfer(dividend[msg.sender]);
        dividend[msg.sender] = 0;
    }

    function setReElection(bool _b) access(SUPERVISOR) state(this.start.selector) external {
        reelection[msg.sender] = _b;
        next();
    }

    function proposeDividend(uint128 _amountPerShare) access(CEO) state(this.start.selector) external {
        
        uint payout = _amountPerShare  * totalSupply();
        require(payout <= address(this).balance);
        lockedBalance += payout;
        proposedDividend = _amountPerShare;
        proposed=true; 
        next();
    }
    
    function setDividendApproval(bool vote) access(SUPERVISOR) state(this.dividendProposed.selector) external {
        if(!vote) approved[msg.sender] = 1;
        if(vote) approved[msg.sender] = 2;

        next();
    }


    // STATES
    //---------------------------------------------------------------------------------------------
    //State::START
    function start() stateTransition(0) external {}
    
    //Condition
    function daysPassedLastElection(uint daysPassed) internal view returns (bool)  {
        lastElection +  daysPassed * 1 days <= block.timestamp;
        return true;
    }

    function reElection() internal view returns (bool) { 
        uint count =0;
        for(uint i= 0; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]) count++; 
        } 
        return numberOfSupervisors/2 < count; 
    }

    function daysPassedLastDividend(uint daysPassed) internal view returns (bool)  {
        lastTimeDividend +  daysPassed * 1 days <= block.timestamp;
        return true;
    }

    // Transition 
    function start_electionStarted() condition(daysPassedLastElection(365) || reElection()) internal {
            Election e = setUpElectionSupervisor();
            e.next();
    }

    // TODO What if CEO dosen't propose Dividend
    function start_dividendProposed() condition(daysPassedLastDividend(365) && proposed) internal {
        delete propose; 
    }

    //---------------------------------------------------------------------------------------------
    //State::ELECTION_STARTED
    function electionStarted() stateTransition(0) external{
        election.next();
    }
    
    // Transition
    function electionStarted_electionStarted() condition(election.currentState() == election.failed.selector) internal {
        Election e = setUpElectionSupervisor();
        // exclude already Voted Supervisors
        for(uint i= 0; i < newSupervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        e.next();
    }

    function electionStarted_electionStarted1() condition(election.currentState() == election.counted.selector && newSupervisors.length < numberOfSupervisors) internal {
        uint index = election.getMaxVotesIndices()[0];
        address supervisor = address(bytes20(election.getCandidate(index)));
        newSupervisors.push(supervisor);
        
        Election e = setUpElectionSupervisor();
        // exclude already Voted Supervisors
        for(uint i= 0; i < newSupervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        e.next();
    }

    function electionStarted_ceoElectionStarted() condition(election.currentState() == election.counted.selector && newSupervisors.length == numberOfSupervisors) internal {

        uint index = election.getMaxVotesIndices()[0];
        address supervisor = address(bytes20(election.getCandidate(index)));
        newSupervisors.push(supervisor);
        
        // Start CEO-Election
        Election e = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < supervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(supervisors[i])));
        }
        e.next();
    }

    //---------------------------------------------------------------------------------------------
    //State::CEO_ELECTION_STARTED
    function ceoElectionStarted() external {
        election.next();
    }

    // Transition
    uint failCountCEO=0;
    function ceoElectionStarted_ceoElectionStarted() condition(election.currentState() == election.failed.selector && failCountCEO < 4) internal {
        failCountCEO++;
        Election e = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < newSupervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        e.next();
    }

    // What if Supervisors are evil and don't want to elect a new CEO ?? ->> make this a reset event >>TIMEOUT
    function ceoElectionStarted_start() condition(election.currentState() == election.failed.selector && failCountCEO == 2 || ) internal {
        // TODO: ADD timeOut!!
        // started = block.timestamp
        // maxDuration + started >= block.timestamp

        // TODO: reset Election Cycle Result DONE!

        delete newSupervisors;
    }

    function ceoElectionStarted_start1() condition(election.currentState() == election.counted.selector) internal {
        uint index = election.getMaxVotesIndices()[0];
        address newCEO = address(bytes20(election.getCandidate(index)));
        addRole(uint(Role.CEO), newCEO);
        removeRole(uint(Role.CEO), currentCEO);
        currentCEO = newCEO;

        // Make newSupervisors operational
        for(uint i=0; i < supervisors.length; i++) {
            removeRole(uint(Role.SUPERVISOR), supervisors[i]);
        }
        delete supervisors;
        supervisors = newSupervisors;
        for(uint i=0; i < supervisors.length; i++) {
            addRole(uint(Role.SUPERVISOR), supervisors[i]);
        }
        delete newSupervisors;

        lastElection = block.timestamp;
    }
    

    //---------------------------------------------------------------------------------------------
    //State::DIVIDEND_PROPOSED
    function dividendProposed() external {}

    //Condition
    function approvalDividendReached() internal returns (uint8) {
        uint countApprove = 0;
        uint countDisagree = 0;
        
        for(uint i=0; i < supervisors.length; i++) {

            uint8 descision = approved[supervisors[i]];
            if(descision == 2) countApprove++;
            if(descision == 1) countDisagree++;
        }

        if(numberOfSupervisors/2 < countApprove) return 2;
        if(numberOfSupervisors/2 < countDisagree) return 1;
        return 0;
    }

    function timeoutDividend() internal returns(bool) {
        return block.timestamp > lastTimeDividend + 30 minutes; // TODO: Bullshit!!
    }
    
    // Transition
    function dividendProposed_start() condition(approvalDividendReached() == 1 || timeoutDividend()) internal {
        delete proposedDividend;
        delete proposed;

        for(uint i=0; i < supervisors.length; i++) {
            approved[supervisors[i]] = 0; 
        }

        uint payout = proposed * totalSupply();
        lockedBalance -= payout;
    }
    function dividendProposed_start1() condition(approvalDividendReached() == 2 ) internal {
        lastTimeDividend = block.timestamp;

        for(uint i=0; i < Shareholders.length(); i++) {
            dividend[Shareholders.at(i)] = balanceOf(Shareholders.at(i)) * proposedDividend ;
        }
    }


    // Private Funcitons
    //---------------------------------------------------------------------------------------------
    function setUpElectionSupervisor() private returns(Election)  {
        election = new Election(1, "Supervisor Election");
        uint l = Shareholders.length();
        for (uint i=0; i<l; i++) {
            address addr = Shareholders.at(i);
            election.registerVoter(addr, balanceOf(addr));
        }
        
        // Supervisors can only propose
        for(uint i=0; i< supervisors.length; i++) {
            election.registerProposer(supervisors[i]);
        }

        return election;
    }

    function setUpElectionCEO() private returns(Election){
        election = new Election(1, "CEO Election");

        for(uint i=0; i< supervisors.length; i++) {
            address addr = supervisors[i];
            election.registerVoter(addr, 1);
        }
        return election;
    }

}