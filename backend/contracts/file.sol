pragma solidity ^0.6.3;


contract StateMachine {
    
    struct Transition {
        function()  fu;
        bytes4 nextState;
    }
    
    event NewStateEntered(string); 
    
    bytes4 public currentState;
    mapping(bytes4 => string) public stateNames;
    mapping(bytes4 => Transition[]) transitions;
    
    
    bool globalReturn;
    uint lastTime;
    bool currentStateSet = false;
    bool taken = false;
    
    constructor() public {        
        lastTime = block.timestamp;
    }
    
    function registerState(string memory name, bytes4 stateSig, function() fu, bytes4 nextState) internal {
        require(stateSig != 0);
        if(!currentStateSet) {
           currentStateSet = true;
           currentState = stateSig;
        }
        stateNames[stateSig] = name;
        transitions[stateSig].push(Transition(fu, nextState));
    }

    // Modifier for State Dependent Functions
    modifier state(bytes4 _requiredState) {
        require(currentState == _requiredState, "Function not callable in current State");
        _;
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
        
        for(uint i=0; i < transitions[currentState].length; i++) {
            globalReturn = true; 
            transitions[currentState][i].fu();
            
            if(globalReturn) {
                currentState = transitions[currentState][i].nextState;
                break;
            }
        }
    }
    
    modifier cond(bool condition) {
        if(condition) {
            _;
        } else {
            globalReturn = false;
        }
    }
    
    // Drives the State Machine - callable by everybody 
    function next() public {
        require(!taken); // Reentrancy Protection 
        
        bytes4 oldState = currentState;
        (bool success, bytes memory data) = address(this).call(abi.encodeWithSelector(currentState));  //call wegen msg.sender == contract statemachine
        require(success, "State Machine call failed");
         //currentState = abi.decode(data,(bytes4));               // Ceck if bytes4 can be decoded
        
        require(currentState != 0, "Fail State entered");       // 0 == FailState
        
        if(currentState != oldState) {
            lastTime = block.timestamp;                         // set if State Transition happend
            emit NewStateEntered(stateNames[currentState]);
        }
        
        taken = false;
    }
    
}

contract SimpleStateMachineExample is StateMachine {
    
    bool public clickAck = false;
    
    event Trans(string);

    constructor() public StateMachine()  {
        registerState("State1", this.state1.selector, a1, this.state2.selector);
        registerState("State2", this.state2.selector, b1, this.state1.selector);
    }
    
    // Inputs::
    function click() public {
        clickAck = !clickAck;
    }
    
    // Conditions::
    function getClick() internal returns (bool) {
        return clickAck;
    }
    
    // Transitions::
    function a1() cond(getClick()) internal {
        emit Trans("a1");
    }

    function b1() internal {    // == cond(true) 
        emit Trans("b1");
    }

    // States::
    function state1() stateTransition(0) external {}
    
    function state2() stateTransition(0) external {}
    
}