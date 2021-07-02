const timeMachine = require('ganache-time-traveler');
//const electionContract = require('../build/contracts/Election.json');
const electionContract = artifacts.require("Election");
const assetTokenContract = artifacts.require("AssetToken");
const electionFactory = artifacts.require("ElectionFactory.sol");

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

            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));
        
            await assetToken.next();

            const actualState2 = await assetToken.currentState();

            //assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('electionStarted()'));
        });

        xit('Check Start State to dividendProposed', async () => {

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


    simpleVoteCycle = async (contract, sup1, sup2, sup3) => {
        let electionAddress = await contract.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(sup1, {from: sup1});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();
        await election.voteCandidate(0, {from: sup1});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();

        state = await election.currentState();
        assert.strictEqual(state, web3.eth.abi.encodeFunctionSignature('counted()'));

        electionAddress = await contract.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(sup2, {from: sup2});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();
        await election.voteCandidate(0, {from: sup1});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();

        electionAddress = await contract.election();
        election = await electionContract.at(electionAddress);

        await election.proposeCandidate(sup3, {from: sup3});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();
        await election.voteCandidate(0, {from: sup1});
        await timeMachine.advanceTimeAndBlock(60*15);
        await contract.next();
    };

    contract('State electionStarted', () => {

        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();

            //console.log(electionAddress);
            election = await electionContract.at(electionAddress);


            const actualState2 = await assetToken.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('electionStarted()'));
            
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

            //await simpleVoteCycle(assetToken);
            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);

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
            //await simpleVoteCycle(assetToken);
            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);

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
            //await simpleVoteCycle(assetToken);
            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);

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

    // voteSupervisor(accounts[1], accounts[2], accounts[3], accounts[4]);


    voteSupervisor = async (contract, sup1, sup2, sup3, ceo) => {

            const actualState1 = await contract.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('ceoElectionStarted()'));

            let electionAddress = await contract.election();
            election = await electionContract.at(electionAddress);

            const actualStateElection1 = await election.currentState();
            assert.strictEqual(actualStateElection1, web3.eth.abi.encodeFunctionSignature('propose()'));


            await election.proposeCandidate(ceo, {from: sup1});
            await timeMachine.advanceTimeAndBlock(60*15);
            await contract.next();
            await election.voteCandidate(0, {from: sup1});
            await election.voteCandidate(0, {from: sup2});
            
            expectRevert(election.voteCandidate(0, {from: ceo}), "no access rights");

            await timeMachine.advanceTimeAndBlock(60*15);
            await contract.next();

            const actualStateElection2 = await election.currentState();
            assert.strictEqual(actualStateElection2, web3.eth.abi.encodeFunctionSignature('counted()'));

            const actualState2 = await contract.currentState();
            assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));


            ceoActual = await contract.currentCEO();
            supervisor0 = await contract.supervisors(0);
            supervisor1 = await contract.supervisors(1);
            supervisor2 = await contract.supervisors(2);

            assert.strictEqual(ceoActual, ceo);
            assert.strictEqual(supervisor0, sup1);
            assert.strictEqual(supervisor1, sup2); 
            assert.strictEqual(supervisor2, sup3);

    }


    contract('State Start - setReElection', () => {
        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            //await simpleVoteCycle(assetToken);
            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);
            await voteSupervisor(assetToken, accounts[1], accounts[2], accounts[3], accounts[4]);
        });

        it('Start to ElectionStarted by setReElection', async() => {
            supervisor0 = await assetToken.supervisors(0);
            supervisor2 = await assetToken.supervisors(2);

            await assetToken.setReElection(true, {from: supervisor0});
            await assetToken.setReElection(true, {from: supervisor2});

            const actualStateAssetToken1 = await assetToken.currentState();
            assert.strictEqual(actualStateAssetToken1, web3.eth.abi.encodeFunctionSignature('electionStarted()'));
        });
    });


    contract('Merge Cycle', () => {

        let mergeTarget;
        let mergeTargetAddress

        beforeEach('create mergeTarget', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            // election = new web3.eth.Contract(electionContract.abi, electionAddress);


            // Elect Account 1,2,3 as Supervisor and Account 4 as CEO
            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);
            await voteSupervisor(assetToken, accounts[1], accounts[2], accounts[3], accounts[4]);

            
            mergeTargetAddress = await assetTokenContract.new({from: accounts[0]});
            mergeTarget = await assetTokenContract.at(mergeTargetAddress.address);

            console.log(mergeTargetAddress.address);
            console.log(assetToken.address);


            const elFactory = await electionFactory.deployed();

            const initialSupply = 10000000;
            const childName = "MergeToken";
            const childSymbol = "MGT";
            const childNumberOfSupervisors = 3;
            const childElectionFactoryAddress = elFactory.address;
            const ratioFollower = 0; 
            const ratioInitiator = 0
            const zeroAddress = '0x0000000000000000000000000000000000000000';

            //console.log(childElectionFactoryAddress);
            await mergeTarget.initialize(initialSupply, childName, childSymbol, childNumberOfSupervisors, childElectionFactoryAddress, ratioFollower, ratioInitiator ,zeroAddress, zeroAddress);

            // Check balance
            let balance = await mergeTarget.balanceOf(accounts[0]);
            assert.strictEqual(balance.toString(), '10000000');

            // Token Distribution
            for(let i=1; i < accounts.length; i++) {
                await mergeTarget.transfer(accounts[i], 1000000);
            }

            await mergeTarget.next();
            await simpleVoteCycle(mergeTarget, accounts[5], accounts[6], accounts[7], accounts[8]);
            await voteSupervisor(mergeTarget, accounts[5], accounts[6], accounts[7], accounts[8]);

            // Check 
            ceo = await mergeTarget.currentCEO();
            supervisor0 = await mergeTarget.supervisors(0);
            supervisor1 = await mergeTarget.supervisors(1);
            supervisor2 = await mergeTarget.supervisors(2);

            /*
            bool = await mergeTarget.hasRole(2, ceo);
            assert.strictEqual(true, bool);
            */

            assert.strictEqual(ceo, accounts[8]);
            assert.strictEqual(supervisor0, accounts[5]);
            assert.strictEqual(supervisor1, accounts[6]);
            assert.strictEqual(supervisor2, accounts[7]);
        });


        it('start_mergeInit', async() => {

            const curentState = await mergeTarget.currentState();
            assert.strictEqual(curentState, web3.eth.abi.encodeFunctionSignature('start()'));

            const curentState1 = await assetToken.currentState();
            assert.strictEqual(curentState1, web3.eth.abi.encodeFunctionSignature('start()'));

            // MergeTarget
            //merge(mergePartner,_assetTokenContractToCloneFrom, string calldata _childName, string calldata _childSymbol, uint _childNumberOfSupervisors, address _childElectionFactoryAddress, uint _ratioFollower, uint _ratioInitiator)
            
            state  = await mergeTarget.currentState();
            console.log(state);  //0xbe9a6555

            // init merge by ceo1
            await assetToken.merge(
                mergeTarget.address,
                mergeTarget.address,
                "childToken",
                "CDT",
                3,
                electionFactory.address,
                1,
                1,
                {from: accounts[4]}
            );
            

            // Check State is mergeInit
            const actualState3 = await assetToken.currentState();
            assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('mergeInit()'));
            const actualState4 = await mergeTarget.currentState();
            assert.strictEqual(actualState4, web3.eth.abi.encodeFunctionSignature('mergeInit()')); //mergeInit 0xb384bd54


            // acceptance of Merge offer by ceo2

            await mergeTarget.acceptMerge({from: accounts[8]});
            

            // Check State for each contract 
            const actualState5 = await assetToken.currentState();
            assert.strictEqual(actualState5, web3.eth.abi.encodeFunctionSignature('stop()'));

            const actualState6 = await mergeTarget.currentState();
            assert.strictEqual(actualState6, web3.eth.abi.encodeFunctionSignature('stop()'));
            

            const childAssetTokenAddress = await assetToken.childAssetToken();
            
            let childAssetToken = await assetTokenContract.at(childAssetTokenAddress);
            const actualState7 = await childAssetToken.currentState();
            assert.strictEqual(actualState7, web3.eth.abi.encodeFunctionSignature('start()'));

            

            // Claim new Tokens after Merge - convert old token to childtokens
            const balance9parent = await assetToken.balanceOf(accounts[9]);
            assert.strictEqual(balance9parent.toString(), "1000000");

            const balance9parent2 = await mergeTarget.balanceOf(accounts[9]);
            assert.strictEqual(balance9parent2.toString(), "1000000");

            const balanceChild = await childAssetToken.balanceOf(childAssetTokenAddress);
            assert.strictEqual(balanceChild.toString(), "20000000");
            

            await childAssetToken.reclaimBalanceFromParentToken({from: accounts[9]});

            const balance9child = await childAssetToken.balanceOf(accounts[9]);
            assert.strictEqual(balance9child.toString(), balance9parent.add(balance9parent2).toString());
        });
    });


    contract('State dividendProposed', () => {
        beforeEach('', async() => {

            await assetToken.next();

            let electionAddress = await assetToken.election();
            election = await electionContract.at(electionAddress);

            // election = new web3.eth.Contract(electionContract.abi, electionAddress);
            //await simpleVoteCycle(assetToken);

            await simpleVoteCycle(assetToken, accounts[1], accounts[2], accounts[3]);
            await voteSupervisor(assetToken, accounts[1], accounts[2], accounts[3], accounts[4]);

        });

        it('start_dividendProposed', async() => {

            let val = web3.utils.toWei('10', 'gwei');

            const actualState1 = await assetToken.currentState();
            assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));


            await assetToken.proposeDividend(val ,{from: accounts[4]});


            const actualState3 = await assetToken.currentState();
            assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
        });

        contract('dividendProposd to ', async () => {
            beforeEach('', async() => {
                
                let val = web3.utils.toWei('10', 'gwei');
                await assetToken.proposeDividend(val, {from: accounts[4]});

                const actualState3 = await assetToken.currentState();
                assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));

            });

            it('dividendProposed_startTimeout', async() => {
                //const DIVIDENDPROPOSEDDURATION = await assetToken.DIVIDENDS_PROPOSED_CYCLE();

                await timeMachine.advanceTimeAndBlock(60*60*25);

                await assetToken.next();

                const actualState1 = await assetToken.currentState();
                assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()')); 
            });

            it('dividendProposed_reject', async() => {
                supervisor0 = await assetToken.supervisors(0);
                supervisor2 = await assetToken.supervisors(2);

                await assetToken.setDividendApproval(false, {from: supervisor0});
                await assetToken.setDividendApproval(false, {from: supervisor2});

                const actualState1 = await assetToken.currentState();
                assert.strictEqual(actualState1, web3.eth.abi.encodeFunctionSignature('start()'));
            });
    
            it('dividendProposed_startApproved', async() => {
                const actualState3 = await assetToken.currentState();
                assert.strictEqual(actualState3, web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
    
                supervisor0 = await assetToken.supervisors(0);
                supervisor1 = await assetToken.supervisors(1);


                await assetToken.setDividendApproval(true, {from: supervisor0});
                await assetToken.setDividendApproval(true, {from: supervisor1});
                
                console.log(web3.eth.abi.encodeFunctionSignature('dividendProposed()'));
    
                const actualState2 = await assetToken.currentState();
                assert.strictEqual(actualState2, web3.eth.abi.encodeFunctionSignature('start()'));
            });
        });

    })
});