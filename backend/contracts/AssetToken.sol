pragma solidity ^0.6.3;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./StateMachine.sol";
import "./Access.sol";
import "./IElection.sol";
import "./IElectionFactory.sol";


contract AssetToken is StateMachine, AccessControl, ERC20 {

    uint16 private constant ELECTION_PROPOSAL_DURATION = 60*15;
    uint16 private constant ELECTION_VOTE_DURATION = 60*15;
    uint32 private constant RESTART_ELECTION_DURATION = 365 days;
    uint8 private constant RETRYS_CEO_ELECTION = 2;
    uint32 private constant RESTART_DIVIDEND_CYCLE = 365 days;
    uint32 private constant DIVIDENDS_PROPOSED_CYCLE = 1 days;

    enum Role {
        SHAREHOLDER,
        SUPERVISOR,
        CEO
    }

    uint[] internal CEO = [uint(Role.CEO)];
    uint[] internal SUPERVISOR = [uint(Role.SUPERVISOR)];
    uint[] internal SHAREHOLDER = [uint(Role.SHAREHOLDER)];

    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet internal Shareholders;
    
    address public currentCEO;
    address[] public supervisors;   
    string internal assetName;
    string internal assetSymbol;
    uint internal numberOfSupervisors;         
    
    // Election Cycle
    IElection public election;
    address electionFactoryAddress;

    mapping(address => bool) internal reelection; 
    uint internal lastElection;
    address[] internal newSupervisors;
    uint internal timeCEOstarted;
    uint internal failCountCEO;
    

    // Dividend Cycle
    uint internal lockedBalance;                                //TODO: Problem reset after Fail!!  
    mapping(address => uint) internal dividend;                 //for shareholder
    uint internal lastTimeDividend;

    uint public proposedDividend;
    uint internal dividendStartedTime;
    bool internal proposed;
    
    mapping(address => uint8) internal approved;                //by supervisor


    // constructor sets Company Name, Proposal for SB
    constructor(address _electionFactoryAddress, uint _initialSupply, string memory _name, string memory _symbol, uint _numberOfSupervisors)
     StateMachine() ERC20(_name, _symbol) public {
        require(_numberOfSupervisors%2 == 1);
        numberOfSupervisors = _numberOfSupervisors;
        assetName = _name;
        assetSymbol = _symbol;
        
        _mint(msg.sender, _initialSupply);
        Shareholders.add(msg.sender);

        // address _electionFactoryAddress,
        //electionFactoryAddress = _electionFactoryAddress;

        registerState("START", this.start.selector, start_electionStarted, this.electionStarted.selector);
        registerState("START", this.start.selector, start_dividendProposed, this.dividendProposed.selector);
        
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted1, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);

        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start_success, this.start.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start_reset, this.start.selector);
        
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start, this.start.selector);
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start1, this.start.selector);
    }

    function transfer(address recipient, uint amount) override public returns(bool) {
        ERC20.transfer(recipient, amount);

        Shareholders.add(recipient);
        addRole(uint(Role.SHAREHOLDER), recipient);
        if(balanceOf(msg.sender) == 0) {
            Shareholders.remove(msg.sender);
            removeRole(uint(Role.SHAREHOLDER), msg.sender);
        }
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) override public returns(bool) {
        ERC20.transferFrom(sender, recipient, amount);

        Shareholders.add(recipient);
        addRole(uint(Role.SHAREHOLDER), recipient);
        if(balanceOf(sender) == 0) {
            Shareholders.remove(sender);
            removeRole(uint(Role.SHAREHOLDER), sender);
        }

        return true;
    }

    //TODO: CHECK next() in Function
    // befor better because of timed Conditions State 
    // after better because of stateChange by InputFunctions


    // Callable Functions
    //---------------------------------------------------------------------------------------------
    // CEO Functions
    function sendEther(address payable _destination, uint _amount) access(CEO) external {
        require(_amount <= address(this).balance - lockedBalance);
        _destination.transfer(_amount);
    }

    function proposeDividend(uint _amountPerShare) access(CEO) state(this.start.selector) external {
        
        uint payout = _amountPerShare  * totalSupply();
        require(payout <= address(this).balance);
        lockedBalance += payout;
        proposedDividend = _amountPerShare;
        proposed=true; 
        next();
    }

    function setDividendApproval(bool vote) access(SUPERVISOR) state(this.dividendProposed.selector) external {
        if(vote) approved[msg.sender] = 2;
        else approved[msg.sender] = 1;
        next();
    }

    function setReElection(bool _b) access(SUPERVISOR) state(this.start.selector) external {
        reelection[msg.sender] = _b;
        next();
    }


    function requestDividend() access(SHAREHOLDER) external {
        lockedBalance -= dividend[msg.sender];
        msg.sender.transfer(dividend[msg.sender]);
        dividend[msg.sender] = 0;

        // 
    }


    /*
    function setCompanyNameSymbol(string calldata _name, string calldata _symbol) access(CEO) external {
        assetName = _name;
        assetSymbol = _symbol;
    }

    function name() override public view returns(string memory) {
        return assetName;
    }
    
    function symbol() override public view returns(string memory) {
        return assetSymbol;
    }
    */


    // STATES
    //---------------------------------------------------------------------------------------------
    //State::START
    function start() stateTransition(0) external {}

    //Condition
    function reElectionORTimePassed() internal view returns (bool) { 
        uint count =0;
        for(uint i= 0; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]) count++; 
        }
        bool reElection = numberOfSupervisors/2 < count;
        
        bool timePassed = lastElection + RESTART_ELECTION_DURATION <= block.timestamp;

        return reElection || timePassed;
    }

    function proposedANDTimePassed() internal view returns (bool)  {
        bool timePassed = block.timestamp >= lastTimeDividend + RESTART_DIVIDEND_CYCLE;
        return proposed && timePassed;
    }

    // Transition 
    function start_electionStarted() condition(reElectionORTimePassed) internal {
            election = setUpElectionSupervisor();
            
            election.next();
    }

    function start_dividendProposed() condition(proposedANDTimePassed) internal {       // What if CEO dosen't propose Dividend >> Supervisor can start reelection
        delete proposed;
        dividendStartedTime = block.timestamp;
    }


    //---------------------------------------------------------------------------------------------
    //State::ELECTION_STARTED
    function electionStarted() stateTransition(0) external{
        election.next();
    }

    //Condition
    function electionFailed() view internal returns (bool) {
        return election.fail();
        //return StateMachine(address(election)).currentState() == election.failed.selector;
    }
    function electionCountedANDNotEnougthSupervisor() view internal returns (bool) {
        //return election.currentState() == election.counted.selector && newSupervisors.length < numberOfSupervisors - 1;
        return election.success() && newSupervisors.length < numberOfSupervisors - 1;
    }

    function electionCountedANDEnougthSupervisor() view internal returns (bool) {
        return election.success() && newSupervisors.length == numberOfSupervisors - 1;
    }
    
    // Transition
    function electionStarted_electionStarted() condition(electionFailed) internal {
        election = setUpElectionSupervisor();
        // exclude already Voted Supervisors
        for(uint i= 0; i < newSupervisors.length; i++) {
            election.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        election.next();
    }

    function electionStarted_electionStarted1() condition(electionCountedANDNotEnougthSupervisor) internal {
        uint index = election.getMaxVotesIndices()[0];
        address supervisor = address(bytes20(election.getCandidate(index)));
        newSupervisors.push(supervisor);
        
        election = setUpElectionSupervisor();
        // exclude already Voted Supervisors
        for(uint i= 0; i < newSupervisors.length; i++) {
            election.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        election.next();
    }

    function electionStarted_ceoElectionStarted() condition(electionCountedANDEnougthSupervisor) internal {
        uint index = election.getMaxVotesIndices()[0];
        address supervisor = address(bytes20(election.getCandidate(index)));
        newSupervisors.push(supervisor);
        
        // Start CEO-Election
        election = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < supervisors.length; i++) {
            election.excludeFromPropose(bytes32(bytes20(supervisors[i])));
        }
        timeCEOstarted = block.timestamp;
        election.next();
    }


    //---------------------------------------------------------------------------------------------
    //State::CEO_ELECTION_STARTED
    function ceoElectionStarted() stateTransition(0) external {
        election.next();
    }

    //event Debug(uint);

    // Condition
    function electionFailedANDfailCountnotReached() internal view returns (bool) {
        return election.fail() && failCountCEO < RETRYS_CEO_ELECTION;
    }

    function electionFailedANDfailCountCEO() internal view returns (bool) {
        return election.fail() && failCountCEO >= RETRYS_CEO_ELECTION;
    }

    function electionSuccessCEO() internal view returns (bool) {
        return election.success();
    }

    // Transition
    function ceoElectionStarted_ceoElectionStarted() condition(electionFailedANDfailCountnotReached) internal {
        failCountCEO++;
        election = setUpElectionCEO();
        // Supervisors can't be elected as CEO
        for(uint i= 0; i < newSupervisors.length; i++) {
            election.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        election.next();
    }

    function ceoElectionStarted_start_reset() condition(electionFailedANDfailCountCEO) internal {
        // TODO: reset Election Cycle Result DONE!
        delete newSupervisors;
        for(uint i=0; i < supervisors.length; i++) {
            reelection[supervisors[i]] = false;
        }
        failCountCEO=0;
    }

    function ceoElectionStarted_start_success() condition(electionSuccessCEO) internal {

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

        for(uint i=0; i < newSupervisors.length; i++) {
            addRole(uint(Role.SUPERVISOR), newSupervisors[i]);
        }

        supervisors = newSupervisors;
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
        return approvalDividendReached() == 1 || block.timestamp > dividendStartedTime + DIVIDENDS_PROPOSED_CYCLE;
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

        delete proposedDividend;
    }

    function dividendProposed_start1() condition(approvalDividend) internal {
        lastTimeDividend = block.timestamp;

        for(uint i=0; i < Shareholders.length(); i++) {
            dividend[Shareholders.at(i)] = balanceOf(Shareholders.at(i)) * proposedDividend ;
        }
    }


    // Private Funcitons
    //---------------------------------------------------------------------------------------------
    function setUpElectionSupervisor() private returns(IElection)  {
        //election = new Election(1, "Supervisor Election", ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION);

        IElectionFactory electionFactory = IElectionFactory(electionFactoryAddress);
        election = IElection(electionFactory.createElection(1, "CEO Election",ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION));

        //election = new createElection();

        uint l = Shareholders.length();

        for (uint i=0; i<l; i++) {
            address addr = Shareholders.at(i);
            election.registerVoter(addr, balanceOf(addr));
        }
        
        // Supervisors can only propose not vote
        for(uint i=0; i< supervisors.length; i++) {
            election.registerProposer(supervisors[i]);
        }

        return election;
    }

    function setUpElectionCEO() private returns(IElection){
        //election = new Election(1, "CEO Election",ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION);

        IElectionFactory electionFactory = IElectionFactory(electionFactoryAddress);
        election = IElection(electionFactory.createElection(1, "CEO Election",ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION));

        for(uint i=0; i< newSupervisors.length; i++) {
            address addr = newSupervisors[i];
            election.registerVoter(addr, 1);
        }
        return election;
    }

    // Fallback function 
    receive() external payable {
    }
}