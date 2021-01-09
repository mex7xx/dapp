/*
var c1 = artifacts.require("c1");

module.exports = function (deployer) {
  deployer.deploy(c1);
};
*/

let assetToken = artifacts.require("AssetToken.sol");
let ico = artifacts.require("ICO.sol");


module.exports = async function(deployer) {

  await deployer.deploy(assetToken, 1000, "MyToken", "MT", 3);
  await deployer.deploy(ico, assetToken.address, 60, 10, 1000000);
  
};
