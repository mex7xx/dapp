pragma solidity ^0.6.3;

contract StateMachine {

    // could be packed in struct to be used as lib
    bytes4[] transitions;
    uint public currentState;
    uint lastTime;

    event NewState (uint newState, uint oldState);

    constructor(bytes4[] memory _transitionsSelectors) public {        
        require(_transitionsSelectors.length != 0);
        transitions = _transitionsSelectors;
        lastTime = block.timestamp;
        currentState = 1; 
    }

    // Modifier for State Dependent Functions
    modifier state(uint _requiredState) {
        require(currentState == _requiredState, "Function not callable in current State");
        _;
    }

    // Modifier for State Transition Functions
    modifier stateTransition(uint _afterSeconds) {
        // Time Restriction
        require(block.timestamp >= lastTime + _afterSeconds * 1 seconds, "minimal time passed after last State Transition not reached yet");
        
        // Ensure State contains Transition 
        require(msg.sig == transitions[currentState -1], "Transition not callable in current State"); 
        
        // Reject all calls coming from outside the contract
        require(msg.sender == address(this), "Transition must be called from inside the State Machine");
        _;
    }

    // drives the State Machine - callable for everybody 
    function next() public {
        uint oldState = currentState;
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(transitions[currentState - 1])); //call wegen msg.sender == contract statemachine
        require(success, "State Machine call failed");
        currentState = abi.decode(data,(uint));
        assert(currentState != 0);                  // 0 == FailState
        if(currentState != oldState) lastTime = block.timestamp; // set if State Transition happend
        emit NewState(currentState, oldState);
    }
}