/*
var c1 = artifacts.require("c1");

module.exports = function (deployer) {
  deployer.deploy(c1);
};
*/


let ico = artifacts.require("ICO.sol");

module.exports = function (deployer) {
  deployer.deploy(ico, 60, "MyAssetToken", "MAT", 10, 1000000, 10);
};
