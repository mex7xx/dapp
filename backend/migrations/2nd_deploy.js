/*
var c1 = artifacts.require("c1");

module.exports = function (deployer) {
  deployer.deploy(c1);
};
*/

let assetToken = artifacts.require("AssetToken.sol");
let ico = artifacts.require("ICO.sol");
let election = artifacts.require("Election.sol");

let electionFactory = artifacts.require("ElectionFactory.sol");

module.exports = async function(deployer) {

  await deployer.deploy(electionFactory);
  
  await deployer.deploy(assetToken, electionFactory.address, 10000000, "MyToken", "MT", 3);
  
  await deployer.deploy(ico, assetToken.address, 60, 1, 80);

  await deployer.deploy(election, 1, "ElectionTest", 15*60, 15*60);
};
