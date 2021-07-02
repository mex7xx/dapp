pragma solidity ^0.6.5;   


import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./StateMachine.sol";
import "./Access.sol";
import "./IElection.sol";
import "./Election.sol";
import "./IElectionFactory.sol";
//import "./AssetTokenFactory.sol"; // Not needed
import "./CloneFactory.sol"; // create Clone 



interface IMergable {
    function merge(address _mergePartner, address assetTokenContractToCloneFrom, string calldata childName, string calldata childSymbol, uint childNumberOfSupervisors, address childElectionFactoryAddress, uint ratioFollower, uint ratioInitiator) external;          // calledby that.CEO 
    function mergeRequested(bytes calldata data) external;
    function mergeAccepted(bytes32 dataHash) external returns(address);
    function acceptMerge() external returns (bool);
    function reclaimBalanceFromParentToken() external; 
}

interface IAssetToken is IMergable {
    function requestDividend() external;
    function proposeDividend(uint) external;
    function sendEther(address payable, uint) external;
    function setReElection(bool) external;
    function setDividendApproval(bool) external;
    function initialize(uint _initialSupply, string calldata _name, string calldata _symbol, uint _numberOfSupervisors, address _electionFactoryAddress, uint _followerRatio, uint _initiatorRatio, address _parentFollower, address _parentInitiator) external;
}


// TODO: interface
contract AssetToken is IAssetToken, StateMachine, AccessControl, CloneFactory, ERC20Upgradeable {

    using EnumerableSet for EnumerableSet.mergeAddressSet;

    // Number of possible Retries for CEO Election
    uint32 public constant RETRYS_CEO_ELECTION = 2;                 
    
    // DURATIONS / TIMEOUTS
    uint32 public constant ELECTION_PROPOSAL_DURATION = 60*15;      // Time which has to pass before Proposal Phase of possible Candidates ends
    uint32 public constant ELECTION_VOTE_DURATION = 60*15;          // Time which has to pass before Voting Phase on Proposals ends.
    uint32 public constant RESTART_ELECTION_DURATION = 365 days;    // Term of Supervisor and CEO in office. Restarts a new Election Cycle.
    
    uint32 public constant RESTART_DIVIDEND_CYCLE = 365 days;       // Time which has to pass before new Dividends can be propoesed and payed out.
    uint32 public constant DIVIDENDS_PROPOSED_TIMEOUT = 1 days;     // Time wich is available for Supervisors to agree on proposed Dividends.
    uint32 public constant MERGE_ACCEPTANCE_DURATION = 1 days;      // Time in which a possible Merge with another contract has 

    // ROLES
    enum Role {
        SHAREHOLDER,    // Owner to the underlying asset of this smart contract. Sharholder elect group of Supervisors
        SUPERVISOR,     // Supervisor overseas and elects CEO
        CEO             // Controlls the underlying assets
    }

    uint[] internal CEO = [uint(Role.CEO)];
    uint[] internal SUPERVISOR = [uint(Role.SUPERVISOR)];
    uint[] internal SHAREHOLDER = [uint(Role.SHAREHOLDER)];

    // Address of CEO
    address public currentCEO;
    // Address of Supervisors
    address[] public supervisors;   
    // Number of Supervisors
    uint internal numberOfSupervisors;
    // Address of Shareholders
    EnumerableSet.mergeAddressSet private Shareholders;


    // Contract Initialized 
    bool private initialized;

    // Election Cycle
    // -------------
    IElection public election;                      // current election contract
    // Address of ElectionFactoryContract
    address private electionFactoryAddress;         

    mapping(address => bool) internal reelection; 
    uint internal lastElection;
    address[] internal newSupervisors;
    uint internal timeCEOstarted;
    uint internal failCountCEO;


    // Dividend Cycle
    // -------------
    uint internal lockedBalance;                                //TODO: Problem reset after Fail!!  
    mapping(address => uint) internal dividend;                 //for shareholder
    uint internal lastTimeDividend;

    uint public proposedDividend;
    uint internal dividendStartedTime;
    bool internal proposed;
    mapping(address => uint8) internal approved;                //by supervisor


    // Merge Cycle
    // -------------

    // Address of new Contract created by the merge
    address public childAssetToken;
    // Blocktime Merge Started
    uint startMergeTime;
    // Succesfull merge 
    bool mergeFinished;
    // Target to merge with
    address public mergePartner;


    // Potential Parents of Contract
    address parentFollower;                 
    address parentInitiator;
    // Ratio for converting Parten Token into new Token
    uint followerRatioParent;   // TODO: Set immutable , not possible since immutalbe variables can only be set by constructor
    uint initiatorRatioParent;

    // Parameters to agree on between merge parties

    // Address of ElectionFactory for the 
    address  public childElectionFactoryAddress;
    address public assetTokenContractToCloneFrom;

    // Name of New Token
    string childName;
    // Tiker Symbol of new Token               
    string childSymbol;
    // Number of Supervisors for new Token
    uint childNumberOfSupervisors;
    // Conversion Ratio
    uint ratioFollower;
    uint ratioInitiator;

    // Events
    
    event MergerRequested(address);
    event MergeSuccess(address, address, address);

    event Debug(string);

    // TODO: Change stateTransition to state && state to stateAccess

    constructor() public {}

    // initialize Function
    function initialize(uint _initialSupply, string calldata _name, string calldata _symbol, uint _numberOfSupervisors, address _electionFactoryAddress, uint _followerRatio, 
    uint _initiatorRatio, address _parentFollower, address _parentInitiator) external override virtual {
        require(!initialized, "already initialized");
        initialized = true;

        require(_numberOfSupervisors%2 == 1, "number of Supervisors must be odd");
        numberOfSupervisors = _numberOfSupervisors;
        
        // Init ERC20 
        __ERC20_init(_name, _symbol);
        _mint(msg.sender, _initialSupply);

        Shareholders.add(msg.sender);

        electionFactoryAddress = _electionFactoryAddress;
        followerRatioParent = _followerRatio;
        initiatorRatioParent = _initiatorRatio;
        parentFollower = _parentFollower;
        parentInitiator = _parentInitiator;
        

        // StateMachine Setup: registerState("StateName" , "State" , "StateTransition" ,  "NextState")
        //              
        registerState("START", this.start.selector, start_electionStarted, this.electionStarted.selector);
        registerState("START", this.start.selector, start_dividendProposed, this.dividendProposed.selector);
        registerState("START", this.start.selector, start_mergeInit, this.mergeInit.selector);

        registerState("MERGE_INITIALIZED", this.mergeInit.selector, mergeInit_start, this.start.selector); 
        registerState("MERGE_INITIALIZED", this.mergeInit.selector, mergeInit_stop, this.stop.selector);
        
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start_reject, this.start.selector);
        registerState("DIVIDEND_PROPOSED",this.dividendProposed.selector, dividendProposed_start_success, this.start.selector);
        
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_electionStarted1, this.electionStarted.selector);
        registerState("ELECTION_STARTED", this.electionStarted.selector, electionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);

        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start_success, this.start.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_ceoElectionStarted, this.ceoElectionStarted.selector);
        registerState("CEO_ELECTION_STARTED", this.ceoElectionStarted.selector, ceoElectionStarted_start_reset, this.start.selector);

        registerState("STOP", this.stop.selector);
    }


    // transfer ERC20 token to another address 
    function transfer(address recipient, uint amount) override public returns(bool) {
        ERC20Upgradeable.transfer(recipient, amount);
        Shareholders.add(recipient);
        
        // Add Recipient of payment
        addRole(uint(Role.SHAREHOLDER), recipient);

        // Remove Shareholder 
        if(balanceOf(msg.sender) == 0) {
            Shareholders.remove(msg.sender);
            removeRole(uint(Role.SHAREHOLDER), msg.sender);
        }
        
        return true;
    }

    // transferFrom 
    function transferFrom(address sender, address recipient, uint256 amount) override public returns(bool) {
        ERC20Upgradeable.transferFrom(sender, recipient, amount);

        // Add Recipient of payment
        Shareholders.add(recipient);
        addRole(uint(Role.SHAREHOLDER), recipient);

        // Remove Shareholder 
        if(balanceOf(sender) == 0) {
            Shareholders.remove(sender);
            removeRole(uint(Role.SHAREHOLDER), sender);
        }

        return true;
    }

    //TODO: CHECK next() in Function  DONE!
    // before better because of timed Conditions State could have run out
    // after better because of stateChange by InputFunctions 


    // USER Callable Functions
    //---------------------------------------------------------------------------------------------
    
    // CEO Functions

    // sendEther allows CEO to spend Ether from the balance which is not locked for paying out Dividends.
    function sendEther(address payable _destination, uint _amount) access(CEO) override external {
        require(_amount <= address(this).balance - lockedBalance);
        _destination.transfer(_amount);
    }


    // proposeDividend allows CEO to propose the amount of divdends - which are added to the lockedBalance
    function proposeDividend(uint _amountPerShare) access(CEO) state(this.start.selector) override external {
        uint payout = _amountPerShare  * totalSupply();
        
        require(payout <= address(this).balance);  // TODO:NEW - lockedBalance
        lockedBalance += payout;
        proposedDividend = _amountPerShare;
        proposed = true;
    }

    // Supervisor Functions
    
    // setDividendApproval allows the Supervisors to vote on the proposed Dividend 
    function setDividendApproval(bool vote) access(SUPERVISOR) state(this.dividendProposed.selector) override external {
        if(vote) approved[msg.sender] = 2;
        else approved[msg.sender] = 1;
    }

    // setReElection allows the Supervisors to vote on a Start of a new Election Cycle. For example to get rid of the current CEO 
    function setReElection(bool _b) access(SUPERVISOR) state(this.start.selector) override external {
        reelection[msg.sender] = _b;
    }


    // Shareholder Functions

    // requestDividend allows the Shareholder to transfer his dividends to his address
    function requestDividend() access(SHAREHOLDER) override external {
        lockedBalance -= dividend[msg.sender];
        msg.sender.transfer(dividend[msg.sender]);
        dividend[msg.sender] = 0;
    }

    //reclaimBalanceFromParentToken lets Shareholders claim new Tokens after a successfull Merge between two Contracts. 
    function reclaimBalanceFromParentToken() override external {
        if (parentFollower != address(0) && parentInitiator != address(0)) {

            // Recursive Calls
            IMergable(parentFollower).reclaimBalanceFromParentToken();
            IMergable(parentInitiator).reclaimBalanceFromParentToken();
            
            //initFromParent[msg.sender] = true; TODO:

            IERC20 tokenFollower = IERC20(parentFollower);
            IERC20 tokenInitiator = IERC20(parentInitiator);

            uint balanceOnParent0 = tokenFollower.balanceOf(tx.origin);
            uint balanceOnParent1 = tokenInitiator.balanceOf(tx.origin);

        
            if(balanceOnParent0 > 0) {
                //tokenFollower.transfer(address(this), balanceOnParent0);
                this.transfer(tx.origin, balanceOnParent0 * followerRatioParent);
            }

            if(balanceOnParent1 > 0) {
                //tokenInitiator.transfer(address(this), balanceOnParent1);
                this.transfer(tx.origin, balanceOnParent1 * initiatorRatioParent);
            }
        }
    }


    /*
    ------------------------------------------------------------------------------------------------------------------------------------------
    >>> Merge Process

        Purpose: Both CEOs of both Contracts want to merge their Assets into a new Contract which we call Child-Contract.

        A Smart Contract in a Merge Process can have one of two Roles either it is the Initator (I) of the Merge or the Follower (F).


        I.merge()           --->    F.mergeRequested()

        I.mergeAccepted()   <---    F.acceptMerge()


        I calls its function merge which then calls mergeRequested. F has then the ability to verify the provided Data for the merge and the CEO of F 
        then calls acceptMerge(). AcceptMerge then calls mergeAccepted where the new Child Contract with the agreed on configuration is created.

    */

    // Initiator Functions
    //---------------------

    // merge 
    function merge(address _mergePartner, address _assetTokenContractToCloneFrom, string calldata _childName, string calldata _childSymbol, uint _childNumberOfSupervisors, address _childElectionFactoryAddress, uint _ratioFollower, uint _ratioInitiator) access(CEO) state(this.start.selector) override external {
        // Selct Target to merge with
        
        mergePartner = _mergePartner;

        // Set Factory to agree on for creating Child Contract
        assetTokenContractToCloneFrom = _assetTokenContractToCloneFrom;  //  Both Contracts have to agree on a AssetTokenFaktory for creating the ChildToken

        // Set Conditions to agree on  for the initilize Function of the Child Contract 
        childName = _childName;
        childSymbol = _childSymbol;
        childNumberOfSupervisors = _childNumberOfSupervisors;
        childElectionFactoryAddress = _childElectionFactoryAddress;

        // Ratio determines how many new Tokens are distributed for old Tokens
        ratioFollower = _ratioFollower;
        ratioInitiator = _ratioInitiator;

        bytes memory data = abi.encode(assetTokenContractToCloneFrom, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator);

        // Propose Conditions to Contract to merge with
        IMergable(mergePartner).mergeRequested(data);
    }

    // Verification by Follower 
    
    // mergeAccepted
    function mergeAccepted(bytes32 _dataHash) state(this.mergeInit.selector) override external returns(address) {  // state(this.mergeInit.selector)  // move to mergeInit if !=0 

        require(msg.sender == mergePartner, "only callable by Merge Target"); 

        //require(IMergable(mergePartner).acceptMerge(), "only callable by acceptMerge()");      // Not TRUE     // calls origin to get true therfore all other calls by other functions are blocked

        // Calculate Hash to proof proposed Conditions have not been changed by Follower
        require(_dataHash == keccak256(abi.encodePacked(assetTokenContractToCloneFrom, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator)), "Conditions are not allowed to change!");
        
        // calculate initialSupply
        uint followerTotalSupply = IERC20(mergePartner).totalSupply();
        uint newInitialSupply = followerTotalSupply * ratioFollower + totalSupply() * ratioInitiator;

        // createClone
        childAssetToken = CloneFactory.createClone(assetTokenContractToCloneFrom); // TODO: Change to AssetTokentToCloneFrom
        

        IAssetToken(childAssetToken).initialize(newInitialSupply, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator, mergePartner, address(this));

        // send Ether Balance to newly created Child Contract
        payable(childAssetToken).transfer(address(this).balance);
        // send minted token back to child 
        IERC20(childAssetToken).transfer(childAssetToken, IERC20(childAssetToken).balanceOf(address(this)));

        emit MergeSuccess(address(this), mergePartner, childAssetToken);
     
        return childAssetToken;
    }

    // Follower Functions
    //------------------------

    // mergeRequested called by thisToken to name MergeRequest 
    function mergeRequested(bytes calldata data) state(this.start.selector) override external {          // access(MERGECONTRACT)
        require(mergePartner == address(0), "mergeRequest already Set");
        mergePartner = msg.sender;                                      

        // Set Conditions in Follower
        (assetTokenContractToCloneFrom, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator) = abi.decode(data,(address, string ,string, uint, address, uint, uint));
        
        emit MergerRequested(mergePartner);
    }

    // acceptMerge called by followerCEO to aggree to received conditions by Creating new TokenContract 
    function acceptMerge() access(CEO) state(this.mergeInit.selector) override external returns(bool) {           
        require(mergePartner != address(0));                            // Implizit schon garantiert durch übergang

        bytes32 conditionHash = keccak256(abi.encodePacked(assetTokenContractToCloneFrom, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator));
        childAssetToken = IMergable(mergePartner).mergeAccepted(conditionHash);

        // transfer Ether Balance to Child
        payable(childAssetToken).transfer(address(this).balance); 

        // set stop
        emit MergeSuccess(address(this), mergePartner, childAssetToken);
        
    }



    // STATE Machine Functions  
    /* The following Code represents the States for the internal StateMachine of the Contract
        Each State contains 3 Types of Functions:

        - State Function -- represents a viable State. The current State (or lets better say its State Function representation) is executed everytime the StateMachine.next() is called to figure out if the State can be advanced.
        - Condition Functions -- represents Conditions that have to be met to execute the the corresponding Transition Function
        - Transition Function -- represents the State Transition from one State to another. Contains actual Business Logic which is executed if a State Transitions occurs.
    */

    //---------------------------------------------------------------------------------------------
    // State::STOP
    function stop() stateTransition(0) external {}

    //---------------------------------------------------------------------------------------------
    //State::START 
    function start() stateTransition(0) external {}


    //Conditions
    // reElectionORTimePassed checks if majority of Supervisors voted for a reElection or if term has ended regularly
    function reElectionORTimePassed() internal view returns (bool) {
        uint count =0;
        for(uint i= 0; i < supervisors.length; i++) {
            if(reelection[supervisors[i]]) count++; 
        }

        bool reElection = numberOfSupervisors/2 < count;
        bool timePassed = lastElection + RESTART_ELECTION_DURATION <= block.timestamp;
        bool init = lastElection == 0;                       // TODO: Überfl

        return (reElection || timePassed || init) && initialized; // initialized checks if smart Contract has been initzialzed by the initilaziation function and prevents any state Transition if not.
    }

    // proposedANDTimePassed checks if CEO has proposed a ddvidend and the period for new payouts has passed. Since dividends are only payed once a year. 
    function proposedANDTimePassed() internal view returns (bool)  {
        bool timePassed = block.timestamp >= lastTimeDividend + RESTART_DIVIDEND_CYCLE;
        return initialized && (proposed && timePassed);
    }

    // mergeAddressSet checks if potential merge Partner Contract was set
    function mergeAddressSet() internal view returns(bool) {
        return mergePartner != address(0);
    }

    // Transitions

    // start_electionStarted sets up new Election Contract to vote on Supervisors 
    function start_electionStarted() condition(reElectionORTimePassed) internal {
            election = setUpElectionSupervisor();
            election.finishRegisterPhase();
    }
    // start_dividendPropose 
    function start_dividendProposed() condition(proposedANDTimePassed) internal {           // What if CEO dosen't propose Dividend -->> Supervisor can start reelection to replace him
        delete proposed;
        dividendStartedTime = block.timestamp;
    }

    // start_mergeInit
    function start_mergeInit() condition(mergeAddressSet) internal {
        startMergeTime = block.timestamp;
    }

    //---------------------------------------------------------------------------------------------
    // State::MERGE_INITIALIZED
    function mergeInit() stateTransition(0) external {}

    //Condition
    function timeoutMerge() internal view returns(bool) {
        return MERGE_ACCEPTANCE_DURATION + startMergeTime < block.timestamp;
    }

    function mergeSuccess() internal view returns(bool) {
        return childAssetToken != address(0);
    }

    //Transition
    function mergeInit_stop() condition(mergeSuccess) internal {
    }

    function mergeInit_start() condition(timeoutMerge) internal {
    }


    //---------------------------------------------------------------------------------------------
    //State::ELECTION_STARTED
    function electionStarted() stateTransition(0) external{
        election.next();
    }

    //Condition

    // electionFailed electionFailed checks if ElectionStateMachine 
    function electionFailed() view internal returns (bool) {
        //return StateMachine(address(election)).currentState() == election.failed.selector;
        return election.fail();
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
        // exclude already Voted Supervisors, ensures that no supervisor has 2 Seats at the board
        for(uint i= 0; i < newSupervisors.length; i++) {
            election.excludeFromPropose(bytes32(bytes20(newSupervisors[i])));
        }
        election.finishRegisterPhase();
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
        election.finishRegisterPhase();
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
        election.finishRegisterPhase();
    }


    //---------------------------------------------------------------------------------------------
    //State::CEO_ELECTION_STARTED
    function ceoElectionStarted() stateTransition(0) external {
        election.next();
    }

    

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
        election.finishRegisterPhase();
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
    function dividendProposed() stateTransition(0) external {}

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
        //return true;
        return approvalDividendReached() == 1 || block.timestamp > dividendStartedTime + DIVIDENDS_PROPOSED_TIMEOUT;
    }

    function approvalDividend() internal view returns (bool) {
        return approvalDividendReached() == 2;
    }
    

    // Transition
    function dividendProposed_start_reject() condition(approvalDividendNotReachedORTimeout) internal {

        for(uint i=0; i < supervisors.length; i++) {
            approved[supervisors[i]] = 0; 
        }
        
        uint payout = proposedDividend * totalSupply();
        lockedBalance -= payout;

        delete proposedDividend;
    }

    function dividendProposed_start_success() condition(approvalDividend) internal {
        lastTimeDividend = block.timestamp;

        for(uint i=0; i < Shareholders.length(); i++) {
            dividend[Shareholders.at(i)] = balanceOf(Shareholders.at(i)) * proposedDividend ;
        }
    }


    // Private HelperFuncitons
    //---------------------------------------------------------------------------------------------
    
    // setUpElectionSupervisor returns new election Contract for voting on new supervisors.
    function setUpElectionSupervisor() private returns(IElection)  {

        IElectionFactory electionFactory = IElectionFactory(electionFactoryAddress);
        election = IElection(electionFactory.createElection(1, "Supervisor Election", ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION, address(this)));

        // Create a Snapshot of the current Shareholders for the election contract to determine who is eligible to vote.
        // List of Shareholders has to be copied on to the election Contract, since in this contract the shareholders can transfer their tokens to different addresses an could double vote.
        // the alternative would be to prevent the Transfer of tokens completly during an Election Cycle.
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

    // setUpElectionCEO returns new election Contract for voting on new CEO.
    function setUpElectionCEO() private returns(IElection){
        //election = new Election(1, "CEO Election",ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION);
        
        IElectionFactory electionFactory = IElectionFactory(electionFactoryAddress);
        election = IElection(electionFactory.createElection(1, "CEO Election",ELECTION_PROPOSAL_DURATION, ELECTION_VOTE_DURATION, address(this)));
        
        for(uint i=0; i< newSupervisors.length; i++) {
            address addr = newSupervisors[i];
            election.registerVoter(addr, 1);
        }
        return election;
    }

    // Fallback function 
    receive() external payable {}
}
