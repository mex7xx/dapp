pragma solidity ^0.6.3;


interface IElectionFactory {
    function createElection(uint _numberToElect, string calldata _electionPurpose, uint _proposalDuration, uint _voteDuration, address _admin) external returns(address);
}

