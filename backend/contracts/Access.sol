pragma solidity ^0.6.3;

/*
AccessControll stellt Modifier (access) für externe Smart-Contract Funktionen bereit die zugriffsgeschützt sein sollen. Wie in Ethereum üblich werden die Ethereum-Adressen als Kennung für die Nutzer verwendet. 
Es lassen sich verschiede Rollen den einzelnen Adressen zuweisen. Bei einer mit dem Modifier access versehenen Funktion wird geprüft ob die Adresse die benötigten Zugriffsrechte zugewiesen bekommen hat ansonsten wird die Transaktion rückgängig gemacht.
*/

contract AccessControl {

    event AccessFor(address, bool); 
    // Address
    mapping(address => mapping(uint => bool)) associatedRoles;      //  (addr, role) => associated  // TODO: Register Function & Check what happens if not in map.

    // TODO: Make to function to provide contract as Lib // new modifier in 
    modifier access(uint[] memory allowedRoles) {
        bool allowed = false;
        for(uint i = 0; i < allowedRoles.length; i++) {
            if (hasRole(allowedRoles[i], msg.sender)) {
                allowed = true;
                break;
            }
        }
        emit AccessFor(msg.sender, allowed);
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