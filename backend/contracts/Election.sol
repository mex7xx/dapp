pragma solidity ^0.6.3;
import "./StateMachine.sol";
import "./Access.sol";

contract Election is AccessControl, StateMachine {

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

    Proposal[] private proposals;
    mapping(address => bool) private proposed;
    mapping(bytes32 => bool) private proposeExists;

    mapping(address => Voter) public voters;

    uint[] private maxVotesIndices;
    uint public numberToElect;
    string public electionPurpose;

    uint private proposeStartTime;

    uint private proposalDuration;
    uint private voteDuration;
    uint private voteTimeStarted;

    constructor(uint _numberToElect, string memory _electionPurpose, uint _proposalDuration, uint _voteDuration) AccessControl() StateMachine() public {
        require(_numberToElect >= 1);
        numberToElect = _numberToElect;
        electionPurpose = _electionPurpose;
        proposalDuration = _proposalDuration;
        voteDuration = _voteDuration;
        AccessControl.addRole(uint(Role.ADMIN), msg.sender);

        // States
        registerState("REGISTER", this.register.selector, register_propose, this.propose.selector);

        registerState("PROPOSE", this.propose.selector, propose_failed, this.failed.selector);
        registerState("PROPOSE", this.propose.selector, propose_vote, this.vote.selector);
        
        registerState("VOTE", this.vote.selector, vote_failed, this.failed.selector);
        registerState("VOTE", this.vote.selector, vote_counted, this.counted.selector);

        // End States
        registerState("COUNTED", this.counted.selector);
        registerState("FAILED",this.failed.selector);
    }

    // State::REGISTER
    function register() stateTransition(0) external {}

    // Transition
    function register_propose() private {
        proposeStartTime = block.timestamp;
    }
    
    function registerVoter(address voterAddr, uint weight) access(ADMIN) state(this.register.selector) public {
        AccessControl.addRole(uint(Role.VOTER), voterAddr);
        voters[voterAddr] = Voter(false, weight);
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
    function propose_vote() condition(enougthProposalsANDTimeout) private {}

    function registerProposer(address proposerAddr) access(ADMIN) state(this.propose.selector) public {
        AccessControl.addRole(uint(Role.PROPOSER), proposerAddr);
    }

    function excludeFromPropose(bytes32 Data) access(ADMIN) state(this.propose.selector) public {
        proposeExists[Data] = true; 
    }

    // Returns newly proposed candidate ID 
    function proposeCandidate(bytes32 proposalData) access(PROPOSER) state(this.propose.selector) public returns(uint) {
        require(!proposed[msg.sender]);
        proposed[msg.sender] = true;                    // only one proposal per address to avoid spam

        require(!proposeExists[proposalData]);
        proposeExists[proposalData] = true; 
        proposals.push(Proposal(0,proposalData));
        return proposals.length - 1;
    }

    //State::VOTE
    function vote() stateTransition(0) external {
        makeMaxVotesIndices(numberToElect);
    }

    // Condition
    function notVotedANDTimeout() internal view returns (bool) {
        return proposals[maxVotesIndices[0]].vote == 0 && block.timestamp >= voteDuration + voteTimeStarted;
    }

    function votedANDTimeout() internal view returns (bool) {
        return proposals[maxVotesIndices[0]].vote != 0 && block.timestamp >= voteDuration + voteTimeStarted;
    }

    // Transitions
    function vote_failed() condition(notVotedANDTimeout) private {}
    function vote_counted() condition(votedANDTimeout) private {}

    // Vote for CandidateID
    function voteCandidate(uint candidateNumber) access(VOTER) state(this.vote.selector) public {
        require(!voters[msg.sender].voted);
        proposals[candidateNumber].vote += voters[msg.sender].weight;
        voters[msg.sender].voted == true;
    }

    //State::COUNTED
    function counted() stateTransition(0) external {}

    //State::FAILED
    function failed() stateTransition(0) external {}


    //Redefinition of next to be only accessible for ADMIN
    function next() access(ADMIN) override public {
        StateMachine.next();
    }

    //
    function getCandidate(uint i) public view returns(bytes32) {
        bytes32 candidateData = proposals[i].data;
        require(candidateData != 0);
        return candidateData;
    }

    //
    function getMaxVotesIndices() public view returns(uint[] memory) {
        return maxVotesIndices;
    }

    // returns an array of indeces with first to nth greatest proposal if several proposals on nth place have same vote the array is extended 
    function makeMaxVotesIndices(uint n) state(this.counted.selector) internal returns (uint[] memory)  {
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

        // search for with same number of votes and extend array
        uint lastIndex = maxVotesIndices[n-1];
        uint voteCount = proposals[maxVotesIndices[n-1]].vote;

        for(uint i = lastIndex-1; i >= 0; i--) {
            if(voteCount == proposals[i].vote) {
                maxVotesIndices.push(i); 
            }
        }
        return maxVotesIndices;
    }

}