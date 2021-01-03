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
    uint timeCEOstarted;
    uint failCountCEO;
    
    // Dividend Cycle
    uint lockedBalance;                 //TODO: Problem reset after Fail!!  
    mapping(address => uint) dividend;  //for shareholder
    uint lastTimeDividend;
    

    uint proposedDividend;
    uint dividendStartedTime;
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
    function reElectionORYearPassed() internal view returns (bool) { 
        uint count =0;
        for(uint i= 0; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]) count++; 
        }
        bool reElection = numberOfSupervisors/2 < count;
        
        bool yearPassed = lastElection + 365 days <= block.timestamp;

        return reElection || yearPassed;
    }

    function proposedANDYearPassed() internal view returns (bool)  {
        bool lastTime = lastTimeDividend + 365 days <= block.timestamp;
        return proposed && lastTime;
    }


    // Transition 
    function start_electionStarted() condition(reElectionORYearPassed) internal {
            Election e = setUpElectionSupervisor();
            e.next();
    }

    // TODO What if CEO dosen't propose Dividend >> Supervisor can start reelection
    function start_dividendProposed() condition(proposedANDYearPassed) internal {
        delete proposed; 
    }

    //---------------------------------------------------------------------------------------------
    //State::ELECTION_STARTED
    function electionStarted() stateTransition(0) external{
        election.next();
    }

    //Condition
    function electionFailed() view internal returns (bool) {
        return election.currentState() == election.failed.selector;
    }
    function electionFailedANDnewSupervisor() view internal returns (bool) {
        return election.currentState() == election.counted.selector && newSupervisors.length < numberOfSupervisors;
    }
    
    // Transition
    function electionStarted_electionStarted() condition(electionFailed) internal {
        Election e = setUpElectionSupervisor();
        // exclude already Voted Supervisors
        for(uint i= 0; i < newSupervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        e.next();
    }

    function electionStarted_electionStarted1() condition(electionFailed) internal {
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

    function electionStarted_ceoElectionStarted() condition(electionFailedANDnewSupervisor) internal {

        uint index = election.getMaxVotesIndices()[0];
        address supervisor = address(bytes20(election.getCandidate(index)));
        newSupervisors.push(supervisor);
        
        // Start CEO-Election
        Election e = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < supervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(supervisors[i])));
        }
        timeCEOstarted = block.timestamp;
        e.next();
    }

    //---------------------------------------------------------------------------------------------
    //State::CEO_ELECTION_STARTED
    function ceoElectionStarted() external {
        election.next();
    }

    // Condition
    function electionFailedANDfailCountnotReached() view internal returns (bool) {
        return election.currentState() == election.counted.selector && failCountCEO < 2;
    }

    function electionFailedANDfailCountReachedORTimeout() view internal returns (bool) {
        return election.currentState() == election.failed.selector && failCountCEO >= 2 || timeCEOstarted + 1 days < block.timestamp;
    }

    function electionCounted() view internal returns (bool){
        return election.currentState() == election.counted.selector;
    }

    // Transition
    function ceoElectionStarted_ceoElectionStarted() condition(electionFailedANDfailCountnotReached) internal {
        failCountCEO++;
        Election e = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < newSupervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        e.next();
    }

    // What if Supervisors are evil and don't want to elect a new CEO ?? ->> make this a reset event >>TIMEOUT
    function ceoElectionStarted_start() condition(electionFailedANDfailCountReachedORTimeout) internal {
        
        // TODO: reset Election Cycle Result DONE!
        delete newSupervisors;
        for(uint i=0; i < supervisors.length; i++) {
            reelection[supervisors[i]] = false;
        }
        failCountCEO=0;
    }

    function ceoElectionStarted_start1() condition(electionCounted) internal {
        uint index = election.getMaxVotesIndices()[0];
        address newCEO = address(bytes20(election.getCandidate(index)));
        addRole(uint(Role.CEO), newCEO);
        removeRole(uint(Role.CEO), currentCEO);
        currentCEO = newCEO;


        // Make newSupervisors operational
        for(uint i=0; i < supervisors.length; i++) {
            removeRole(uint(Role.SUPERVISOR), supervisors[i]);
            reelection[supervisors[i]] = false;
        }
        delete supervisors;
        supervisors = newSupervisors;
        for(uint i=0; i < supervisors.length; i++) {
            addRole(uint(Role.SUPERVISOR), supervisors[i]);
        }
        delete newSupervisors;

        lastElection = block.timestamp;
        failCountCEO=0;
    }
    

    //---------------------------------------------------------------------------------------------
    //State::DIVIDEND_PROPOSED
    function dividendProposed() external {}

    //Condition
    function approvalDividendReached() internal view returns (uint8) {
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

    function approvalDividendNotReachedORTimeout() internal view returns (bool) {
        return approvalDividendReached() == 1 || block.timestamp > dividendStartedTime + 1 days;
    }

    function approvalDividend() internal view returns (bool) {
        return approvalDividendReached() == 2;
    }
    
    // Transition
    function dividendProposed_start() condition(approvalDividendNotReachedORTimeout) internal {
        for(uint i=0; i < supervisors.length; i++) {
            approved[supervisors[i]] = 0; 
        }
        
        uint payout = proposedDividend * totalSupply();
        lockedBalance -= payout;

        dividendStartedTime;
        delete proposedDividend;
        delete proposed;
    }

    function dividendProposed_start1() condition(approvalDividend) internal {
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