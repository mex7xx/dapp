//const { default: Web3 } = require("web3");

/*
const c1 = artifacts.require("c1"); 

contract('Test', (accounts) => {
    contract('String lengthtest()', () => {
        it('the lenght shoud be 8', async () => {
          
            web3.eth.getBalance(accounts[0])
            .then( (s) => {
                console.log(s)
                assert.strictEqual(8,'Ethereum'.length);
            });

            let c1instance = await c1.deployed();

            let v1 = await c1instance.i();
            console.log(v1);

            await c1instance.inc(2);

            let v2 = await c1instance.i();
            console.log(v2);
            assert.equal(v2, 2);
        });
    });
});

*/

const ico = artifacts.require("ICO.sol"); 
const assetToken = artifacts.require("AssetToken.sol"); 

contract('Test Deployment', (accounts) => {
    contract('ICO contains Asset Token', () => {
        it('erc20token === assetTokenInstance', async () => {

            console.log(await web3.eth.getBalance(accounts[0]));

            const icoInstance = await ico.deployed();

            const assetTokenInstance  = await assetToken.deployed();
            let erc20 =  await icoInstance.ERC20token();

            assert.strictEqual(erc20, assetTokenInstance.address);
        });
    });
});