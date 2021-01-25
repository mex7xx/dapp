pragma solidity ^0.6.3;

interface IElection {
    function registerVoter(address voterAddr, uint weight) external;
    function registerProposer(address proposerAddr) external;
    function excludeFromPropose(bytes32 Data) external;
    function finishRegisterPhase() external;
    function proposeCandidate(bytes32 proposalData) external;
    function voteCandidate(uint candidateNumber) external;
    function getCandidate(uint i) view external returns(bytes32);
    function getMaxVotesIndices() external view returns(uint[] memory);
    function fail() view external returns(bool);
    function success() view external returns(bool);
    function next() external;
}