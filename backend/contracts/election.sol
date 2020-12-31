pragma solidity ^0.6.3;
import "./state.sol";
import "./access.sol";

contract Election is AccessControl, StateMachine {

    enum State {
        _,                              // FailState
        REGISTER,
        PROPOSE,
        VOTE,
        TALLY,
        ELECTION_FAILED
    }

    bytes4[] transitionsSelectors = [this.endRegister.selector,
                                    this.endPropose.selector, 
                                    this.endVote.selector];

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
    
    uint[] ADMIN = [uint(Role.ADMIN)];
    uint[] VOTER = [uint(Role.VOTER)];
    uint[] PROPOSER = [uint(Role.PROPOSER), uint(Role.VOTER)];


    Proposal[] proposals;
    mapping(address => bool) internal proposed;
    mapping(bytes32 => bool) proposeExists;

    mapping(address => Voter) public voters;

    uint[] internal maxVotesIndices;
    uint internal numberToElect;
    string public electionPurpose;


    constructor(uint _numberToElect, string memory _electionPurpose) AccessControl() StateMachine(transitionsSelectors) public {
        require(_numberToElect >= 1);
        numberToElect = _numberToElect;
        electionPurpose = _electionPurpose;
        AccessControl.addRole(uint(Role.ADMIN), msg.sender);
    }
    
    //
    function registerVoter(address voterAddr, uint weight) access(ADMIN) state(uint(State.REGISTER)) public {
        AccessControl.addRole(uint(Role.VOTER), voterAddr);
        voters[voterAddr] = Voter(false, weight);
    }

    // 
    function registerProposer(address proposerAddr) access(ADMIN) state(uint(State.REGISTER)) public {
        AccessControl.addRole(uint(Role.PROPOSER), proposerAddr);
    }

    // 
    function excludeFromPropose(bytes32 Data) access(ADMIN) state(uint(State.REGISTER)) public {
        proposeExists[Data] = true; 
    }

    // returns newly proposed candidate ID 
    function proposeCandidate(bytes32 proposalData) access(PROPOSER) state(uint(State.PROPOSE)) public returns(uint) {
        require(!proposed[msg.sender]);
        proposed[msg.sender] = true;                // only one proposal per address to avoid spam

        require(!proposeExists[proposalData]);
        proposeExists[proposalData] = true; 
        proposals.push(Proposal(0,proposalData));
        return proposals.length - 1;
    }

    // Vote for CandidateID
    function vote(uint candidateNumber) access(VOTER) state(uint(State.VOTE)) public {
        require(!voters[msg.sender].voted);
        proposals[candidateNumber].vote += voters[msg.sender].weight;
        voters[msg.sender].voted == true;
    }

    //
    function getCandidate(uint i) public returns(bytes32) {
        bytes32 candidateData = proposals[i].data;
        require(candidateData != 0);
        return candidateData;
    }

    function finished() public returns(bool) {
        if (State(currentState) == State.TALLY) return true;
        return false;
    }
    
    function failed() public returns(bool) {
        if (State(currentState) == State.ELECTION_FAILED) return true;
        return false;
    }

    //
    function getMaxVotesIndices() public returns(uint[] memory) {
        return maxVotesIndices;
    }

    // returns an array of indeces with first to nth greatest proposal if several proposals on nth place have same vote the array is extended 
    function makeMaxVotesIndices(uint n) state(uint(State.TALLY)) internal returns (uint[] memory)  {
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

    // make next() only callable by admin
    //TODO: remove access 
    function next() access(ADMIN) override public {
        StateMachine.next();
    }
    
    // State Transition Functions - called by contract itself
    function endRegister() stateTransition(0) external returns (uint)  {
        return uint(State.PROPOSE);
    }

    function endPropose() stateTransition(30) external returns (uint)  {
        //Fail state if not enougth proposed candidates
        if(numberToElect > proposals.length) return uint(State.ELECTION_FAILED);

        return uint(State.VOTE);
    }

    function endVote() stateTransition(30) external returns (uint)  {
        makeMaxVotesIndices(numberToElect);

        // Check if at least one vote was given
        if (proposals[maxVotesIndices[0]].vote >= 0) return uint(State.ELECTION_FAILED);

        return uint(State.TALLY);
    }

}