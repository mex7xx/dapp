pragma solidity ^0.6.3;

import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StateMachine.sol";
import "./Access.sol";
import "./Election.sol";
import "./ERC20share.sol";

contract SimpleICO {

}
/*
// ToDo: Make funktion voteable so that if quorum is reached function can be called once!
// with help of Access control and StateMachine
contract CompanyToken is ERC20 {

    address[] public Shareholders;

    // invoked by Founder
    constructor(uint256 initialSupply, string memory _name, string memory _symbol) public ERC20(_name, _symbol) {
        _mint(msg.sender, initialSupply);
    }

    // proposeConsentCall onlyCE0, 
    function consentCall(bytes4 funcSig) public { //argument ??
        // call Function if Signature in Set delet form Set 
    }

    // Kapitalerhöhung // only CEO
    // propose Signature to be called  
    function increaseSupply(uint amount) public {
        _mint(address(this), amount);
    }

    // REentrancy!! // only CEO 
    function spendEtherFor(string memory purpose, address payable _destination, uint _amount) public {
        //try first call receive cast CompanyToken(address)
    }

    function receiveEtherFor(string memory purpose) payable public {
        // msg.value , msg.sender
    }
}



contract V1 is StateMachine, AccessControl, ERC20share {

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

    enum State {
        _,                              // FailState as required by StateMachine
        START,
        SUPERVISOR_ELECTION_STARTED,
        SUPERVISOR_ELECTION_ENDED,
        CEO_ELECTION_STARTED,
        CEO_ELECTION_ENDED,
        DIVIDEND_PROPOSED,
        DIVIDEND_APPROVED
    }

    bytes4[] transitionsSelectors = [this.start.selector,
                                    this.endSupervisorElection.selector,
                                    this.startCEOElection.selector,
                                    this.endCEOElection.selector];

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
    }

    // External Callable Functions


    // CEO Functions
    function sendEther(address payable _destination, uint _amount) access(CEO) external {
        require(_amount <= address(this).balance - lockedBalance);
        _destination.transfer(_amount);
    }

    function changeCompanyName(string calldata _companyName) access(CEO) external {
        companyName = _companyName;
    }





    function proposeDividend(uint128 _amountPerShare) access(CEO) state(uint(State.START)) external {
        // check if amountPerShare * Sharholderblance <= address(this).balance()
        
        uint sum = 0;
        for(uint i=0; i < Shareholders.length(); i++) {
            sum += balanceOf(Shareholders.at(i));
        }

        uint payout = _amountPerShare * sum;
        require(payout <= address(this).balance);
        lockedBalance += payout;
        proposedDividend = _amountPerShare;

        next();
    }


    // Supervisor Functions

    mapping(address => bool) reelection;

    // Set Relection 
    function setReElection(bool _b) access(SUPERVISOR) state(uint(State.START)) external {
        reelection[msg.sender] = _b;
        next();
    }

    // Dividend
    mapping(address => uint) dividend; 
    uint proposedDividend;
    uint lockedBalance;
    bool approved;
    bool proposed;

    function approveDividend() access(SUPERVISOR) state(uint(State.DIVIDEND_PROPOSED)) external {
        //
        next();
    }
    
    // Shareholder Functions
    function requestDividend() access(SHAREHOLDER) external {
        lockedBalance -= dividend[msg.sender];
        msg.sender.transfer(dividend[msg.sender]);
        dividend[msg.sender] = 0;
    }

    // 
    function reElection() internal returns(bool) {
        // if(lastTimeElection + CycleTime <= block.timestamp) {}
        return true;

        // check if supervisors call for reelection
        for(uint i; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]){
                return false;
            }
        }
        return true;
    }

 

    function start_proposed() internal returns (bool) {
        if(proposed) {
            // business logic 

            proposed = false;
            return true; 
        }
        return false;
    }


    function start_election() internal returns (bool) {
        if(reElection()) {
            Election e = setUpElectionSupervisor();
            e.next();
            return true;           
        }
        return false; 
    }
    
    modifier cond(bool condition){
        if(condition){
            _;
            globalReturn = true;
        }
        globalReturn = false;
    }

    function start_proposed2() cond(election.finished()) internal returns (bool) {
        uint b0 = 1;
    }

    function x() internal returns (bool) {

        return bool;
    }

    modifier fuTrans(function()[] memory fus) {
        fus[0]();
        _;
    }

    // State Transitions
    function start() stateTransition(0) fuTrans(x()) external returns (uint state)  {

        state = this.currentState(); // put into modifier

        start_proposed2();
        if(globalReturn) state = uint(State.DIVIDEND_PROPOSED);

        if(start_proposed()) state = uint(State.DIVIDEND_PROPOSED);
        if(start_election()) state = uint(State.SUPERVISOR_ELECTION_STARTED);  
        


        if(reElection()) {
            // Start new election Cycle 
            Election e = setUpElectionSupervisor();
            e.next();

            return uint(State.SUPERVISOR_ELECTION_STARTED);
        }

        if(proposed) {

            election = new Election(1, "Dividend Election");

            for(uint i=0; i < supervisors.length; i++) {
                address addr = supervisors[i];
                election.registerVoter(addr, 1);
            }

            election.next();
            election.proposeCandidate(bytes32(proposedDividend));
            //election.proposeCandidate(bytes32(-1));
            election.next(); 
            proposed = false;

            return uint(State.DIVIDEND_PROPOSED);
        }

    }

    uint timeout =0;
    
    function endDividendElection() external returns (uint) {

        election.next();

        if(election.finished()) {
            uint [] memory indices = election.getMaxVotesIndices();
            if(indices.length == 1) {
                int result = int(bytes32(election.getCandidate(indices[0])));
                
                return uint(State.DIVIDEND_APPROVED);  
            }

        }

        if(timeout == 0 ) { // timeout
            // reset 
            return uint(State.START);
        }

        return this.currentState();
    }

    function endSupervisorElection() stateTransition(30) external returns (uint) {
        election.next();

        if(election.finished()) {

            uint index = election.getMaxVotesIndices()[0];
            address supervisor = address(bytes20(election.getCandidate(index)));
            newSupervisors.push(supervisor);

            if(newSupervisors.length == numberOfSupervisors) {

                for(uint i=0; i < supervisors.length; i++) {
                    removeRole(uint(Role.SUPERVISOR), supervisors[i]);
                }

                delete supervisors;
                supervisors = newSupervisors;

                for(uint i=0; i < supervisors.length; i++) {
                    addRole(uint(Role.SUPERVISOR), supervisors[i]);
                }
                delete newSupervisors;

                return uint(State.SUPERVISOR_ELECTION_ENDED);
            } else {
                Election e = setUpElectionSupervisor();
                // exclude already Voted Supervisors
                for(uint i= 0; i < newSupervisors.length; i++) {
                    e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
                }
                e.next();
            }
        }


        if(election.failed()) {
            Election e = setUpElectionSupervisor();
            // exclude already Voted Supervisors
            for(uint i= 0; i < newSupervisors.length; i++) {
                e.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
            }
            e.next();
        }

        return this.currentState();
    }

    function startCEOElection() stateTransition(30) external returns (uint) {
        Election e = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < supervisors.length; i++) {
            e.excludeFromPropose(bytes32(bytes20(supervisors[i])));
        }
        e.next();

        return uint(State.CEO_ELECTION_STARTED);
    }

    function endCEOElection() stateTransition(30) external returns (uint) {
        election.next();

        if(election.finished()) {
            uint index = election.getMaxVotesIndices()[0];
            address newCEO = address(bytes20(election.getCandidate(index)));
            addRole(uint(Role.CEO), newCEO);
            removeRole(uint(Role.CEO), currentCEO);

            return uint(State.CEO_ELECTION_ENDED);  // TODO: Change to START
        }

        if(election.failed()) {

            Election e = setUpElectionCEO();
            for(uint i= 0; i < supervisors.length; i++) {
                e.excludeFromPropose(bytes32(bytes20(supervisors[i])));
            }
            e.next();
        }
        
        return uint(this.currentState());
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

*/
