pragma solidity ^0.6.3;
import './StateMachine.sol';

contract SimpleStateMachineExample is StateMachine {
    
    bool public clickbool = false;
    bool endMachine = false;

    event Trans(string);

    constructor() public StateMachine()  {
        registerState("State1", this.state1.selector, a1, this.state2.selector);
        registerState("State2", this.state2.selector, b1, this.state1.selector);
        registerState("State1", this.state1.selector, a2, this.state3.selector);
        registerState("State3", this.state3.selector);
    }

    function next() override public{}
    
    //User Inputs::
    function click() public {
        clickbool = !clickbool;
    }

    function end() public {
        endMachine = true;
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

    function a2() condition(endMachine) internal {
        emit Trans("a2");
    }


    // States::
    function state1() stateTransition(0) external {}
    function state2() stateTransition(0) external {}
    function state3() stateTransition(0) external {}
    
}