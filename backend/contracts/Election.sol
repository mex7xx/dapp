pragma solidity ^0.6.3;
import "./StateMachine.sol";
import "./Access.sol";
import "./IElection.sol";


contract Election is IElection, AccessControl, StateMachine {
    
    enum Role {
        ADMIN,
        PROPOSER,
        VOTER
    }

    struct Voter {
        bool voted;
        uint weight;
    }

    struct Proposal {
        uint vote; 
        bytes32 data;
    }
    
    uint[] private ADMIN = [uint(Role.ADMIN)];
    uint[] private VOTER = [uint(Role.VOTER)];
    uint[] private PROPOSER = [uint(Role.PROPOSER), uint(Role.VOTER)];

    bool finishedRegister;

    Proposal[] private proposals;
    mapping(address => uint) private proposed;
    mapping(bytes32 => bool) private proposeExists;

    mapping(address => Voter) public voters;

    uint[] private maxVotesIndices;
    uint public numberToElect;
    string public electionPurpose;
   
    bool internal voted;
    uint internal proposeStartTime;
    uint internal proposalDuration;
    uint internal voteDuration;
    uint internal voteTimeStarted;

    constructor(uint _numberToElect, string memory _electionPurpose, uint _proposalDuration, uint _voteDuration, address _admin) StateMachine() public {
        require(_numberToElect >= 1);
        numberToElect = _numberToElect;
        electionPurpose = _electionPurpose;
        proposalDuration = _proposalDuration;
        voteDuration = _voteDuration;
        
        if(_admin != address(0)) {
            AccessControl.addRole(uint(Role.ADMIN), _admin);
        } else {
             AccessControl.addRole(uint(Role.ADMIN), msg.sender);
        }
        

        // States
        registerState("REGISTER", this.register.selector, register_propose, this.propose.selector);

        registerState("PROPOSE", this.propose.selector, propose_failed, this.failed.selector);
        registerState("PROPOSE", this.propose.selector, propose_vote, this.vote.selector);
        
        registerState("VOTE", this.vote.selector, vote_failed, this.failed.selector);
        registerState("VOTE", this.vote.selector, vote_counted, this.counted.selector);

        // Final States
        registerState("COUNTED", this.counted.selector);
        registerState("FAILED",this.failed.selector);

    }

    // Functions

    // Election Process failed
    function fail() external view override returns(bool) {
        if (currentState == Election.failed.selector) return true;
        else return false;
    }

    function success() external view override returns(bool) {
        if (currentState == Election.counted.selector) return true;
        else return false;
    }
    
    // Register Voter
    function registerVoter(address voterAddr, uint weight) access(ADMIN) state(this.register.selector) override external {
        AccessControl.addRole(uint(Role.VOTER), voterAddr);
        voters[voterAddr] = Voter(false, weight);
    }

    // Register Proposer
    function registerProposer(address proposerAddr) access(ADMIN) state(this.register.selector) override external {
        AccessControl.addRole(uint(Role.PROPOSER), proposerAddr);
    }

    // Exclude Proposal 
    function excludeFromPropose(bytes32 Data) access(ADMIN) state(this.register.selector) override external {
        proposeExists[Data] = true;
    }

    function finishRegisterPhase() access(ADMIN) state(this.register.selector) override external {
        finishedRegister = true;
    }

    // 
    function proposeCandidate(bytes32 proposalData) access(PROPOSER) state(this.propose.selector) override external {

        require(proposed[msg.sender] <= numberToElect, "max proposals reached");     // max proposal per address to avoid spam
        proposed[msg.sender]++;

        require(!proposeExists[proposalData]);
        proposeExists[proposalData] = true;
        proposals.push(Proposal(0,proposalData));

        // TODO: AHHH!!
    }
    
    // Vote for Candidate ID
    function voteCandidate(uint candidateNumber) access(VOTER) state(this.vote.selector) override public {
        voted = true;
        require(!voters[msg.sender].voted, "already voted");
        voters[msg.sender].voted = true;
        proposals[candidateNumber].vote += voters[msg.sender].weight;     
    }

    function getCandidate(uint i) override external view returns(bytes32) {
        bytes32 candidateData = proposals[i].data;
        require(candidateData != 0);
        return candidateData;
    }

    //
    function getMaxVotesIndices() override external view returns(uint[] memory) {
        return maxVotesIndices;
    }

    // STATES::

    // State::REGISTER
    function register() stateTransition(0) external {}

    // Condition
    function finishedRegisterPhase() internal view returns (bool) {
        return finishedRegister;
    }

    // Transition
    function register_propose() condition(finishedRegisterPhase) private {
        proposeStartTime = block.timestamp;
    }
    

    // State::PROPOSE
    function propose() stateTransition(0) external {}

    // Condition
    function notEnougthProposalsANDTimeout() internal view returns (bool) {
        return numberToElect > proposals.length && block.timestamp >= proposeStartTime + proposalDuration;
    }

    function enougthProposalsANDTimeout() internal view returns (bool) {
        return numberToElect <= proposals.length && block.timestamp >= proposeStartTime + proposalDuration;
    }

    // Transition
    function propose_failed() condition(notEnougthProposalsANDTimeout) private {}

    function propose_vote() condition(enougthProposalsANDTimeout) private {
        voteTimeStarted = block.timestamp;
    }


    //State::VOTE
    function vote() stateTransition(0) external {}

    // Condition
    function notVotedANDTimeout() internal view returns (bool) {
        return !voted && block.timestamp >= voteDuration + voteTimeStarted;
    }

    function votedANDTimeout() internal view returns (bool) {
        return voted && block.timestamp >= voteDuration + voteTimeStarted;
    }

    // Transitions
    function vote_failed() condition(notVotedANDTimeout) private {}

    function vote_counted() condition(votedANDTimeout) private {
        makeMaxVotesIndices(numberToElect);
    }


    //State::COUNTED
    function counted() stateTransition(0) external {}

    //State::FAILED
    function failed() stateTransition(0) external {}

    // TODO: Redefinition of next to be only accessible for ADMIN
    
    function next() override(StateMachine, IElection) public {
        StateMachine.next();
    }
    
    // updates an array of indeces with first to nth greatest proposal if several proposals on nth place have same vote the array is extended 
    function makeMaxVotesIndices(uint n) internal {
        if(proposals.length < n) n = proposals.length;

        maxVotesIndices = new uint[](n);

        for (uint i = 0; i < proposals.length; i++) {       
            for (uint j=0; j < n; j++) {                

                if(proposals[i].vote >= proposals[maxVotesIndices[j]].vote) {
                    uint m = n-1;
                    while(j<m) {
                        maxVotesIndices[m] = maxVotesIndices[m-1];
                        m--;
                    }
                    maxVotesIndices[j] = i; 
                    break;
                }
            }
        }

        //search for index with same number of votes and extend array
        
        /*
        uint lastIndex = maxVotesIndices[n-1];
        uint voteCount = proposals[maxVotesIndices[n-1]].vote;

        for(uint i = lastIndex-1; i >= 0; i--) {
            if(voteCount == proposals[i].vote) {
                maxVotesIndices.push(i); 
            }
        }
        */
    }

}