pragma solidity ^0.6.3;
import "./AssetToken.sol";


interface IAssetTokenFactory {
    function createAssetToken(uint _initialSupply, string calldata _name, string calldata _symbol, uint _numberOfSupervisors, address _electionFactoryAddress, uint _followerRatio , uint _initiatorRatio , address _parentFollower, address _parentInitiator) external returns(address);
}

 

contract AssetTokenFactory is IAssetTokenFactory {

    function createAssetToken(uint _initialSupply, string calldata _name, string calldata _symbol, uint _numberOfSupervisors, address _electionFactoryAddress, uint _followerRatio , uint _initiatorRatio , address _parentFollower, address _parentInitiator) override external returns(address) {
        return address (new AssetToken(_initialSupply, _name, _symbol,  _numberOfSupervisors, _electionFactoryAddress, _followerRatio , _initiatorRatio, _parentFollower, _parentInitiator));
    }
}