pragma solidity ^0.6.3;
import './StateMachine.sol';

contract SimpleStateMachineExample is StateMachine {
    
    bool public clickbool = false;
    
    event Trans(string);

    constructor() public StateMachine()  {
        registerState("State1", this.state1.selector, a1, this.state2.selector);
        registerState("State2", this.state2.selector, b1, this.state1.selector);
    }
    
    // Inputs::
    function click() public {
        clickbool = !clickbool;
    }
    
    // Conditions::
    function getClick() internal returns (bool) {
        return clickbool;
    }
    
    // Transitions::
    function a1() condition(getClick()) internal {
        emit Trans("a1");
    }

    function b1() internal {    // == condition(true) 
        emit Trans("b1");
    }


    // States::
    function state1() stateTransition(0) external {}
    function state2() stateTransition(0) external {}
    
}