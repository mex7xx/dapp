

let assetToken = artifacts.require("AssetToken.sol");
let ico = artifacts.require("ICO.sol");
let election = artifacts.require("Election.sol");

let electionFactory = artifacts.require("ElectionFactory.sol");
let assetTokenFactory = artifacts.require("AssetTokenFactory.sol");

module.exports = async function(deployer) {
  const zeroAddress = '0x0000000000000000000000000000000000000000';

  await deployer.deploy(assetTokenFactory);
  await deployer.deploy(electionFactory);

  const initialSupply = 10000000;
  const childName = "TestToken";
  const childSymbol = "TTK";
  const childNumberOfSupervisors = 3;
  const childElectionFactoryAddress = electionFactory.address;
  const ratioFollower = 0; 
  const ratioInitiator = 0;

  await deployer.deploy(assetToken, initialSupply, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator ,zeroAddress, zeroAddress);

  await deployer.deploy(ico, assetToken.address, 60, 1, 80);

  await deployer.deploy(election, 1, "ElectionTest", 15*60, 15*60, zeroAddress);



};
