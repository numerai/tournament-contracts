const contracts = require('./helpers/contracts');
const constants = require('./helpers/constants');
const SimpleGriefing = require('../build/SimpleGriefing.json');

const utils = require('ethers').utils;

describe('Setup Accounts And Deploy Contracts', async () => {
    it('should deploy mockNMR', async () => {
        const contract = await contracts.getMockNMR();
        const balance = await contract.balanceOf('0x0000000000000000000000000000000000000001');
        assert.strictEqual(balance.toString(), utils.parseEther("100").toString(), 'Initial balance is wrong');
    });

    it('should deploy Relay', async () => {
        const relay = await contracts.getRelay();
        const _owner = await relay.owner();
        assert.strictEqual(_owner, constants.multiSigWallet, 'Initial contract owner does not match');
    });

    it('should deploy TournamentV2', async () => {
        const contract = await contracts.getTournament();
        const _owner = await contract.owner();
        assert.strictEqual(_owner, constants.multiSigWallet, 'Initial contract owner does not match');
    });

    it('should deploy agreement', async () => {
        const factory = await contracts.deployAgreementFactory();

        const callData = contracts.createSimpleGriefingCallData(constants.multiSigWallet, constants.tournamenContractAddress);
        const txn = await factory.create(callData);
        const receipt = await factory.verboseWaitForTransaction(txn);
        const expectedEvent = "InstanceCreated";
        const eventFound = receipt.events.find(
            emittedEvent => emittedEvent.event === expectedEvent,
            "There is no such event"
        );

        const contract = deployer.wrapDeployedContract(SimpleGriefing, eventFound.args.instance);

        const isStaker = await contract.isStaker(constants.multiSigWallet);
        assert.strictEqual(isStaker, true, 'Agreement staker is wrong');
    });

    it('should deploy NumeraiErasureV1', async () => {
        const contract = await contracts.deployNumeraiErasureV1();
        const _owner = await contract.owner();
        assert.strictEqual(_owner, constants.fundedAccountAddress, 'Initial contract owner does not match');
    });
});
