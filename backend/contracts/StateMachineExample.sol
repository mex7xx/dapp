pragma solidity ^0.6.3;
import './StateMachine.sol';

contract SimpleStateMachineExample is StateMachine {
    
    bool private clickbool = false;
    bool private endMachine = false;

    event Trans(string);

    constructor() public StateMachine()  {
        registerState("State1", this.state1.selector, a1, this.state2.selector);
        registerState("State1", this.state1.selector, a2, this.state3.selector);
        registerState("State2", this.state2.selector, b1, this.state1.selector);
        registerState("State3", this.state3.selector);
    }
    
    
    //function next() override public{}
    
    
    //User Inputs::
    function click() public {
        clickbool = !clickbool;
    }

    function end() public {
        endMachine = true;
    }
    
    
    // Conditions::
    function getClick() public view returns (bool) {
        return clickbool;
    }
    
    function isEnd() public view returns (bool) {
        return endMachine;
    }
    

    // Transitions::
    function a1() condition(getClick) internal {
        emit Trans("a1");
    }
    
    function a2() condition(isEnd) internal {
        emit Trans("a2");
    }

    function b1() internal {    // == condition(true) 
        emit Trans("b1");
    }
    

    // States::
    function state1() stateTransition(0) external {}
    function state2() stateTransition(0) external {}
    function state3() stateTransition(0) external {}
    
}