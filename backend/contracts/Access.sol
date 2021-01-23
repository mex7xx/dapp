pragma solidity ^0.6.3;

contract AccessControl {
    mapping(address => mapping(uint => bool)) associatedRoles;  //  (addr, role) => associated  // TODO: Register Function & Check what happens if not in map.

    // TODO: Make to function to provide contract as Lib // new modifier in 
    modifier access(uint[] memory allowedRoles) {
        bool allowed = false;
        for(uint i = 0; i < allowedRoles.length; i++) {
            if (hasRole(allowedRoles[i], msg.sender)) {
                allowed = true;
                break;
            }
        }
        require(allowed, "no access rights");
        _;
    }

    function addRole(uint _role, address _to) internal {
        associatedRoles[_to][_role] = true;
    }
    function removeRole(uint _role, address _from) internal {
        associatedRoles[_from][_role] = false;
    }
    function hasRole(uint _role, address _add) public view returns(bool) {
        return associatedRoles[_add][_role];
    }
}