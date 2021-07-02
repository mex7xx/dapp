pragma solidity ^0.6.3;

contract Proxy {
    address immutable targetImpelmentation; 

    constructor(address _targetImpelmentation) public {
        targetImpelmentation = _targetImpelmentation;
    }

    fallback() external payable {
        //return targetImpelmentation.delegatecall(msg.data);
    }

    
}


contract CloneFactory {
    function createClone(address from) external returns(address) {
        return address(new Proxy(from));
    }
}
