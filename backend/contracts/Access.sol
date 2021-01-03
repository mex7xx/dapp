pragma solidity ^0.6.3;

contract AccessControl {
    event AccessAllowed(address _to);
    mapping(address => mapping(uint => bool)) associatedRoles;  //  (addr, role) => associated  // TODO: Register Function & Check what happens if not in map. 

    // TODO: Make to function to provide contract as Lib // new modifier in 
    modifier access(uint[] memory allowedRoles) {
        bool allowed = false;
        for(uint i; i < allowedRoles.length; i++) {
            if (hasRole(i, msg.sender) ) {
                allowed = true;
                break;
            }
        }
        require(allowed);
        emit AccessAllowed(msg.sender);
        _;
    }
    
    function addRole(uint _role, address _to) internal {
        associatedRoles[_to][_role] = true;
    }
    function removeRole(uint _role, address _from) internal {
        associatedRoles[_from][_role] = false;
    }
    function hasRole(uint _role, address _add) internal view returns(bool) {
        return associatedRoles[_add][_role];
    }
}