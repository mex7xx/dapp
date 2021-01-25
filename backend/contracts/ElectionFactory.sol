pragma solidity ^0.6.3;
import "./IElectionFactory.sol";
import "./Election.sol";


contract ElectionFactory is IElectionFactory {


    function createElection(uint _numberToElect, string calldata _electionPurpose, uint _proposalDuration, uint _voteDuration, address _admin) override external returns(address) {
        Election e = new Election(_numberToElect, _electionPurpose, _proposalDuration, _voteDuration, _admin);
        address add = address(e); 
        return add;
    }

}

