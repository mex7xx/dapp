pragma solidity ^0.6.3;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StateMachine.sol";
import "./Access.sol";
import "./Election.sol";
import "./ERC20share.sol";


contract AssetToken is StateMachine, AccessControl, ERC20share {

    // TODO: Check for StateMachine
    //function() external returns(uint) m = this.closeProposal;
    // make next() return uint state

    enum Role {
        SHAREHOLDER,
        SUPERVISOR,
        CEO
    }

    uint[] CEO = [uint(Role.CEO)];
    uint[] SUPERVISOR = [uint(Role.SUPERVISOR)];
    uint[] SHAREHOLDER = [uint(Role.SHAREHOLDER)];
    uint[] SUPERVISOR_SHAREHOLDER = [uint(Role.SHAREHOLDER), uint(Role.SUPERVISOR)];

    string companyName;

    // Election Cycle                     
    Election public election;
    address public currentCEO;
    uint public numberOfSupervisors;
    address[] public supervisors;
    address[] internal newSupervisors;


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

        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start, this.start.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start1, this.start.selector);

        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_dividendApproved, this.dividendApproved.selector);
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_dividendApproved, this.dividendApproved.selector);

        registerState("DIVIDEND_APPROVED", this.dividendApproved.selector);
        
    }

    // TODO: help Funktion clear/reset all State Variable with return to Start

    // Dividend
    mapping(address => uint) dividend; 
    uint proposedDividend;
    uint lockedBalance;
    
    bool proposed;

    // Supervisor Functions
    mapping(address => bool) reelection;

    //---------------------------------------------------------------------------------------------
    //State::START
    function start() stateTransition(0) external {}
    
    //Condition
    function daysPassedLastElection(uint i) internal returns (bool)  {
        //lastElection + daysPassed >= block.timestamp         
        return true;
    }

    function reElection() internal returns (bool)  { 
        uint count =0;
        for(uint i= 0; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]) count++; 
        } 
        return numberOfSupervisors/2 < count; 
    }

    // Transition 
    function start_electionStarted() condition(daysPassedLastElection(1) || reElection()) internal {
            Election e = setUpElectionSupervisor();
            e.next();
    }
    
    function start_dividendProposed() condition(proposed) internal {}


    // UserCallable Functions
    // Set Relection 
    function setReElection(bool _b) access(SUPERVISOR) state(this.start.selector) external {
        reelection[msg.sender] = _b;
        next();
    }

    function proposeDividend(uint128 _amountPerShare) access(CEO) state(this.start.selector) external {
        // check if amountPerShare * Sharholderblance <= address(this).balance()
        uint sum = 0;
        for(uint i=0; i < Shareholders.length(); i++) {
            sum += balanceOf(Shareholders.at(i));
        }
        uint payout = _amountPerShare * sum;
        require(payout <= address(this).balance);
        lockedBalance += payout;
        proposedDividend = _amountPerShare;
        proposed=true; 
        next();
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

    // What if Supervisors are evil and don't want to elect a new CEO ?? ->> make this a reset event
    function ceoElectionStarted_start() condition(election.currentState() == election.failed.selector && failCountCEO == 2) internal {
        // reset Election Cycle Result

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
    }

    //---------------------------------------------------------------------------------------------
    //State::DIVIDEND_PROPOSED
    function dividendProposed() external {}

    uint lastTimeDividend;
    mapping(address => uint8) approved;

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
        return block.timestamp > lastTimeDividend + 30 minutes;
    }
    
    // Transition
    function dividendProposed_start() condition(approvalDividendReached() == 1 || timeoutDividend()) internal {
        // reset

    }
    //
    function dividendProposed_dividendApproved() condition(approvalDividendReached() == 2 ) internal {
        // payout
        lastTimeDividend = block.timestamp;
    }

    //
    function setDividendApproval(bool vote) access(SUPERVISOR) state(this.dividendProposed.selector) external {
        if(!vote) approved[msg.sender] = 1;
        if(vote) approved[msg.sender] = 2;

        next();
    }


    //---------------------------------------------------------------------------------------------
    // State: DIVIDEND_APPROVED
    function  dividendApproved() external {}

    
    //---------------------------------------------------------------------------------------------
    // External Callable Functions
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


    // Private Funcitons
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