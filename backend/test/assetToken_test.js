const timeMachine = require('ganache-time-traveler');
//const electionContract = require('../build/contracts/Election.json');
const electionContract = artifacts.require("Election");
const assetTokenContract = artifacts.require("AssetToken");

const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
  } = require('@openzeppelin/test-helpers');
const { web3 } = require('@openzeppelin/test-helpers/src/setup');


contract('AssetToken', (accounts) => {

    let assetToken;
    let election;

    beforeEach(async() => {
        let snapshot = await timeMachine.takeSnapshot();
        snapshotId = snapshot['result'];

        assetToken = await assetTokenContract.deployed();

        for(let i=1; i < accounts.length; i++) {
            await assetToken.transfer(accounts[i], 1000000);
        }

        let toAddress = assetToken.address;
        let val = web3.utils.toWei('10', 'ether');

        web3.eth.sendTransaction({from: accounts[0], to: toAddress, value: val});

    });

    afterEach(async() => {
        await timeMachine.revertToSnapshot(snapshotId);
    });

    contract('Test transfer of Token', () => {
        it('Transfer', async () => {
            let balance = await assetToken.balanceOf(accounts[1]);
            assert.strictEqual(balance.toString(), '1000000');
        });

        it('Balance of AssetToken', async () => {
            let toAddress = assetToken.address;
            let val = web3.utils.toWei('10', 'ether');


            let balance = await web3.eth.getBalance(toAddress);
            console.log(balance.toString());

            assert.strictEqual(balance, val);
        });

        it('isSharholder', async () => {
            hasRole = await assetToken.hasRole(0,accounts[1]);
            assert.strictEqual(hasRole, true);
        });

    });


    contract('State Start', () => {

        it('Check Start State to electionStarted', async () => {
            const actualState1 = await assetToken.currentState();  

            await timeMachine.advanceTimeAndBlock(60);
            await assetToken.next();

            const actualState2 = await assetToken.currentState();

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('electionStarted()'));
        });

        it('Check Start State to dividendProposed', async () => {

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));

            // TODO:  proposeDividend with elected ceo 
            //expectRevert(assetToken.proposeDividend(10, {from: accounts[1]}), "no access rights");
            //assetToken.proposeDividend(10, {from: accounts[1]});


            b = await assetToken.hasRole(0, accounts[1]);
            assert.strictEqual(true, b);
            //await assetToken.requestDividend({from: accounts[1]});

            await timeMachine.advanceTimeAndBlock(60);
            await assetToken.next();

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
        });
    });


    simpleVoteCycle = async () => {
        let electionAddress = await assetToken.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(accounts[1], {from: accounts[1]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();
        await election.voteCandidate(0, {from: accounts[1]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();

        state = await election.currentState();
        assert.strictEqual(state, web3.eth.abi.encodeFunctionSignature('counted()'));

        electionAddress = await assetToken.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(accounts[2], {from: accounts[2]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();
        await election.voteCandidate(0, {from: accounts[1]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();

        electionAddress = await assetToken.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(accounts[3], {from: accounts[3]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();
        await election.voteCandidate(0, {from: accounts[1]});
        await timeMachine.advanceTimeAndBlock(60*15);
        await assetToken.next();
    };

    contract('State electionStarted', () => {

        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            //election = new web3.eth.Contract(electionContract.abi, electionAddress);
        });

        it('Test election role Voter for Shareholders', async ()=> {
            b = await election.hasRole(2, accounts[1]);
            assert.strictEqual(b,true);
        });

        it('Test fail loop', async () => {
            const actualStateAssetToken1 = await assetToken.currentState();
            assert.strictEqual(actualStateAssetToken1, web3.eth.abi.encodeFunctionSignature('electionStarted()'));

            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();

            const actualStateAssetToken2 = await assetToken.currentState();
            assert.strictEqual(actualStateAssetToken2, web3.eth.abi.encodeFunctionSignature('electionStarted()'));


            const actualStateElection1 = await election.currentState();
            assert.strictEqual(actualStateElection1, web3.eth.abi.encodeFunctionSignature('failed()'));


            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);


            const actualStateElection2 = await election.currentState();
            assert.strictEqual(actualStateElection2, web3.eth.abi.encodeFunctionSignature('propose()'));
        });


        it('Check Transition electionStarted_ceoElectionStarted', async () => {

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('electionStarted()'));

            await simpleVoteCycle();

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));
        });

    });

    contract('State ceoElectionStarted', () => { 
        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            //election = new web3.eth.Contract(electionContract.abi, electionAddress);
        });

        it('Transition ceoElectionStarted_start', async () => {
            await simpleVoteCycle();

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            const actualStateElection1 = await election.currentState();
            assert.strictEqual(actualStateElection1, web3.eth.abi.encodeFunctionSignature('propose()'));


            await election.proposeCandidate(accounts[4], {from: accounts[1]});
            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();
            await election.voteCandidate(0, {from: accounts[1]});
            await election.voteCandidate(0, {from: accounts[2]});
            
            expectRevert(election.voteCandidate(0, {from: accounts[4]}), "no access rights");

            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();


            const actualStateElection2 = await election.currentState();
            assert.strictEqual(actualStateElection2, web3.eth.abi.encodeFunctionSignature('counted()'));

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));


            ceo = await assetToken.currentCEO();
            supervisor0 = await assetToken.supervisors(0);
            supervisor1 = await assetToken.supervisors(1);
            supervisor2 = await assetToken.supervisors(2);

            assert.strictEqual(ceo, accounts[4]);
            assert.strictEqual(supervisor0, accounts[1]);
            assert.strictEqual(supervisor1, accounts[2]);
            assert.strictEqual(supervisor2, accounts[3]);
        });


        it('Transition ceoElectionStarted_start_reset', async () => {
            await simpleVoteCycle();

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));

            let timeOut = 
            // Make election fail 3 Times
            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();

            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();
            
            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();


            //console.log(web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));      // 0x86f302ff 
            //console.log(web3.eth.abi.encodeFunctionSignature('electionStarted()'));         // 0xd5346da1

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));
        });

    });

    voteSupervisor = async () => {

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            const actualStateElection1 = await election.currentState();
            assert.strictEqual(actualStateElection1, web3.eth.abi.encodeFunctionSignature('propose()'));


            await election.proposeCandidate(accounts[4], {from: accounts[1]});
            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();
            await election.voteCandidate(0, {from: accounts[1]});
            await election.voteCandidate(0, {from: accounts[2]});
            
            expectRevert(election.voteCandidate(0, {from: accounts[4]}), "no access rights");

            await timeMachine.advanceTimeAndBlock(60*15);
            await assetToken.next();


            const actualStateElection2 = await election.currentState();
            assert.strictEqual(actualStateElection2, web3.eth.abi.encodeFunctionSignature('counted()'));

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));


            ceo = await assetToken.currentCEO();
            supervisor0 = await assetToken.supervisors(0);
            supervisor1 = await assetToken.supervisors(1);
            supervisor2 = await assetToken.supervisors(2);

            assert.strictEqual(ceo, accounts[4]);
            assert.strictEqual(supervisor0, accounts[1]);
            assert.strictEqual(supervisor1, accounts[2]);
            assert.strictEqual(supervisor2, accounts[3])
    }

    contract('State dividendProposed', () => {
        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            // election = new web3.eth.Contract(electionContract.abi, electionAddress);
            await simpleVoteCycle();
            await voteSupervisor();
        });

        it('start_dividendProposed', async() => {

            let val = web3.utils.toWei('10', 'gwei');

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));


            await assetToken.proposeDividend(val ,{from: accounts[4]});


            const actualState3 = await assetToken.currentState();
            assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
        });

        it('dividendProposed_startTimeout', async() => {

            let val = web3.utils.toWei('10', 'gwei');
            await assetToken.proposeDividend(val, {from: accounts[4]});

            const actualState3 = await assetToken.currentState();
            assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));

            let dividendProposedDuration = await assetToken.DIVIDENDS_PROPOSED_CYCLE();
            web3.eth.getStorageAt(contractAddress, 0).then(console.log);
            await timeMachine.advanceTimeAndBlock(dividendProposedDuration);

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));
        });


        it('dividendProposed_startApproved', async() => {

            let val = web3.utils.toWei('10', 'gwei');
            await assetToken.proposeDividend(val, {from: accounts[4]});

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
            
            supervisor0 = await assetToken.supervisors(0);
            supervisor1 = await assetToken.supervisors(1);
            supervisor2 = await assetToken.supervisors(2);
            console.log(supervisor0);

            await assetToken.setDividendApproval(true, {from: supervisor0});
            await assetToken.setDividendApproval(true, {from: supervisor1});
            
            //await assetToken.setDividendApproval(true, {from: supervisor2});

            /*
            let dividendProposedDuration = await assetToken.DIVIDENDS_PROPOSED_CYCLE();
            web3.eth.getStorageAt(contractAddress, 0).then(console.log);
            await timeMachine.advanceTimeAndBlock(dividendProposedDuration);
            */

            console.log(web3.eth.abi.encodeFunctionSignature('dividendProposed()'));

            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));
        });

    })
});