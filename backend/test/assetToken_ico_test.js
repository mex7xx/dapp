const timeMachine = require('ganache-time-traveler');

const ico = artifacts.require("ICO.sol"); 
const assetToken = artifacts.require("AssetToken.sol"); 

contract.skip('ICO', (accounts) => {

    //let exampleContract;

    beforeEach(async() => {
        let snapshot = await timeMachine.takeSnapshot();
        snapshotId = snapshot['result'];
    });

    afterEach(async() => {
        await timeMachine.revertToSnapshot(snapshotId);
    });


    contract('ICO contains Asset Token', () => {
        it('erc20token equals assetTokenInstance', async () => {
            const icoInstance = await ico.deployed();
            const assetTokenInstance  = await assetToken.deployed();

            let erc20 =  await icoInstance.ERC20token();

            assert.strictEqual(erc20, assetTokenInstance.address);
        });

        it('test transfer', async () => {
            let balanceBefore = web3.utils.fromWei(await web3.eth.getBalance(accounts[4]), 'ether');
            await web3.eth.sendTransaction({from: accounts[3], to: accounts[4], value: web3.utils.toWei('10', 'ether')});
            let balance = web3.utils.fromWei(await web3.eth.getBalance(accounts[4]), 'ether');

            assert.strictEqual(Number(balanceBefore), Number(balance) - 10);

            await web3.eth.sendTransaction({from: accounts[3], to: assetToken.address, value: web3.utils.toWei('10', 'ether')});
        });
    });

    contract('ICO.invest', () => {

        it('State after Investquorum reached', async () => {

            const icoInstance = await ico.deployed();
            const assetTokenInstance  = await assetToken.deployed();
            await assetTokenInstance.transfer(icoInstance.address, 80);
            
            //const balance = await assetTokenInstance.balanceOf(accounts[0]);

            await icoInstance.invest({from: accounts[1], value: 80});
            const actualState1 = await icoInstance.currentState();    

            await timeMachine.advanceTimeAndBlock(60);
            await icoInstance.next();

            const actualState2 = await icoInstance.currentState()


            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('investing()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('distribution()'));
        });

        it('requestToken', async () => {
            const icoInstance = await ico.deployed();
            const assetTokenInstance  = await assetToken.deployed();
            
            await assetTokenInstance.transfer(icoInstance.address, 80);
            await icoInstance.invest({from: accounts[1], value: 80});  
            await timeMachine.advanceTimeAndBlock(60);
            await icoInstance.next();

            await icoInstance.requestToken({from: accounts[1]});
            
            balance1 = await assetTokenInstance.balanceOf(icoInstance.address)
            balance2 = await assetTokenInstance.balanceOf(accounts[1]);

            assert.strictEqual(balance1.toString(), '0');
            assert.strictEqual(balance2.toString(), '80');
        });
    });

    contract('ICO.invest', async () => {

        it('State after Investquorum Not reached', async () => {

            const icoInstance = await ico.deployed();
            const assetTokenInstance  = await assetToken.deployed();
            await assetTokenInstance.transfer(icoInstance.address, 80);
            
            await icoInstance.invest({from: accounts[1], value: 79});
            const actualState1 = await icoInstance.currentState()

            await timeMachine.advanceTimeAndBlock(60);
            await icoInstance.next();

            const actualState2 = await icoInstance.currentState()


            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('investing()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('refunding()'));
        });
        
    });

    




});
