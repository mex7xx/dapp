pragma solidity ^0.6.3;


interface IStateMachine {
    function next() external;
}

contract StateMachine is IStateMachine {
    
    struct Transition {
        function() fu;
        bytes4 nextState;
    }
    
    event NewStateEntered(bytes4, string); 
    
    bytes4 public currentState;
    mapping(bytes4 => string) public stateNames;
    mapping(bytes4 => Transition[]) transitions;
    

    bool globalReturn;
    uint lastTime;
    bool currentStateSet = false;
    bool taken = false;
    //string private stateMachineName;
    
    /*
    constructor() public {        
        //stateMachineName = _stateMachineName;
    }
    */
    event stateFailure(bytes4, bytes4);

    // Modifier for State Dependent Functions // Update State -> timeouts
    modifier state(bytes4 _requiredState) {
        next();                                             

        bool correctState = currentState == _requiredState;
        if(!correctState){
            emit stateFailure(currentState,_requiredState);
            revert("Function not callable in current State");
        }
        
        _;

        next();            
    }
     // Update State -> FunctionCalls
    
    function getCurrentStateName() external view returns (string memory) {
        return stateNames[currentState];
    }
    
    function registerState(string memory name, bytes4 stateSig) internal {
        require(stateSig != 0);
        if(!currentStateSet) {
           currentStateSet = true;
           currentState = stateSig;
        }
        stateNames[stateSig] = name;
    }

    function registerState(string memory name, bytes4 stateSig, function() fu, bytes4 nextState) internal {
        registerState(name, stateSig);
        transitions[stateSig].push(Transition(fu, nextState));
    }

    // Modifier for State Transition Functions
    modifier stateTransition(uint _releaseStateAfterSeconds) {
        // Time Restriction
        require(block.timestamp >= lastTime + _releaseStateAfterSeconds * 1 seconds, "minimal time passed after last State Transition not reached yet");
        
        // 
        require(msg.sig == currentState, "Transition not callable in current State"); 
        
        // Reject all calls coming from outside the contract
        require(msg.sender == address(this), "Transition must be called from inside the State Machine");

        _;

        uint l = transitions[currentState].length;
        for(uint i=0; i < l; i++) {
            globalReturn = true; 
            transitions[currentState][i].fu();

            if(globalReturn) {
                currentState = transitions[currentState][i].nextState;
                break;
            }
        }
    }
    
    modifier condition(function() view returns (bool) cond ) {
        if(cond()) {
            _;
        } else {
            globalReturn = false;
        }
    }

    event DebugState(bytes4);

    // Drives the State Machine - callable by everybody // since Ethereum has itself no lifeliness 
    function next() override public virtual {
        require(!taken, "no reentrancy allowed"); // Reentrancy Protection 
        
        bytes4 oldState = currentState;
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(currentState));  //call wegen msg.sender == contract statemachine
        if (!success) {
            emit DebugState(currentState);
            revert("State Machine call failed");
        }

        //currentState = abi.decode(data,(bytes4));             // Ceck if bytes4 can be decoded
        
        require(currentState != 0, "Fail State entered");       // 0 == FailState
        
        if(currentState != oldState) {
            lastTime = block.timestamp;                         // set if State Transition happend
            emit NewStateEntered(currentState, stateNames[currentState]);
        }

        taken = false;
    }
}