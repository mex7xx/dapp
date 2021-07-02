pragma solidity ^0.6.3;
import "@openzeppelin/contracts/utils/EnumerableSet.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Prob not needed 

contract ERC20share is ERC20 {

    using EnumerableSet for EnumerableSet.AddressSet;
    
    EnumerableSet.AddressSet internal Shareholders;
    
    constructor(uint256 initialSupply, string memory _name, string memory _symbol) public ERC20(_name, _symbol) {
        _mint(msg.sender, initialSupply);
        Shareholders.add(msg.sender);
    }

    function transfer(address recipient, uint amount) override public returns(bool) {
        // add recipient to shareholders
        ERC20.transfer(recipient, amount);
        // check if sender has balance == 0 then remove from
        Shareholders.add(recipient);
        if(balanceOf(msg.sender) == 0) {
            Shareholders.remove(msg.sender);
        }
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) override public returns(bool) {
        ERC20.transferFrom(sender, recipient, amount);

        Shareholders.add(recipient);
        if(balanceOf(sender) == 0) {
            Shareholders.remove(sender);
        }
        return true;
    }
}