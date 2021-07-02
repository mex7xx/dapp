const timeMachine = require('ganache-time-traveler');
const {
    BN,           // Big Number support
    constants,    // Common constants, like the zero address and largest integers
    expectEvent,  // Assertions for emitted events
    expectRevert, // Assertions for transactions that should fail
  } = require('@openzeppelin/test-helpers');


let electionContract = artifacts.require("Election.sol")
let electionFactoryContract = artifacts.require("ElectionFactory.sol")
let assetTokenContract = artifacts.require("AssetToken.sol");



contract.skip('Election', (accounts) => {

    let election;

    beforeEach(async() => {
        let snapshot = await timeMachine.takeSnapshot();
        snapshotId = snapshot['result'];
    });

    afterEach(async() => {
        await timeMachine.revertToSnapshot(snapshotId);
    });

    //  1, "ElectionTest", 15*60, 15*60
    contract('Election State register', () => {
        it('Election register_propose', async () => {
            election = await electionContract.deployed();

            let actualState1 = await election.currentState();
            await election.registerVoter(accounts[1], 1);

            await election.finishRegisterPhase();
            let actualState2 = await election.currentState();

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('register()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('propose()'));
        });
    });

    contract('Election propose', () => {

        beforeEach('', async () => {
            election = await electionContract.deployed();

            for(let i=1; i < accounts.length; i++) {
                await election.registerVoter(accounts[i], 1);
            }
            await election.finishRegisterPhase();
        });

        it('Election propose_vote', async () => {
            let actualState1 = await election.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('propose()'));
            await election.proposeCandidate(accounts[1], {from: accounts[1]});

            await timeMachine.advanceTimeAndBlock(60*15);
            await election.next();

            actualState2 = await election.currentState();

            
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('vote()'));
        });

        it('Election propose_failed', async () => {
            let actualState1 = await election.currentState();

            await timeMachine.advanceTimeAndBlock(60*15);
            await election.next();

            actualState2 = await election.currentState();

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('propose()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('failed()'));
        });
    });


    contract('Election vote', () => {

        beforeEach('', async () => {
            election = await electionContract.deployed();

            for(let i=1; i < accounts.length; i++) {
                await election.registerVoter(accounts[i], 1);
            }
            
            await election.finishRegisterPhase(); // propose

            await election.proposeCandidate(accounts[2], {from: accounts[5]});
            await election.proposeCandidate(accounts[3], {from: accounts[6]});
            await election.proposeCandidate(accounts[4], {from: accounts[7]});
            await election.proposeCandidate(accounts[5], {from: accounts[7]});

            await timeMachine.advanceTimeAndBlock(60*15);
            await election.next(); // vote
        });

        it('Election vote_counted', async () => {

            await election.next();

            let actualState1 = await election.currentState();

            assert.strictEqual(actualState1,web3.eth.abi.encodeFunctionSignature('vote()'));

            await election.voteCandidate(0, {from: accounts[4]});
            await election.voteCandidate(1, {from: accounts[5]});
            await election.voteCandidate(2, {from: accounts[6]});
            await election.voteCandidate(2, {from: accounts[7]});
            await election.voteCandidate(1, {from: accounts[8]});
            await election.voteCandidate(2, {from: accounts[9]});
            await election.voteCandidate(3, {from: accounts[2]});
            await election.voteCandidate(3, {from: accounts[3]});

            // Check Prevent Double Voting
            expectRevert(election.voteCandidate (1, {from: accounts[6]}), "already voted");

            await timeMachine.advanceTimeAndBlock(60*15);
            await election.next();
            await election.next();

            actualState2 = await election.currentState();
            let indices = await election.getMaxVotesIndices();

            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('counted()'));
            assert.strictEqual(indices[0].toString(), '2');

            /*
            console.log(web3.utils.isBN(indices))
            console.log(web3.utils.isBN(indices[0]))
            console.log(indices.toString());
            console.log(indices[0].toString());
            */
        });

        it('Election vote_failed', async () => {

            let actualState1 = await election.currentState();

            await timeMachine.advanceTimeAndBlock(60*15);
            await election.next();

            actualState2 = await election.currentState();

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('vote()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('failed()'));
        });
    });

});



contract.skip('ElectionFactory', (accounts) => {
    let election;
    contract('Test Factory', () => {
        it('testing', async () => {
            let factory = await electionFactoryContract.deployed();
            let electionAddress = await factory.createElection(1,"0",10, 10);
            let add = await factory.add();
            console.log(add);

            let assetToken = await assetTokenContract.deployed();
            await assetToken.setElection();
            add = await assetToken.election();
            console.log(add);


            assetToken.next();

            election = await electionContract.at(add);
            console.log(await election.currentState());
        });
    })
});