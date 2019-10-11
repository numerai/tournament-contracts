const contracts = require('./helpers/contracts');

const utils = require('ethers').utils;

const SimpleGriefing = require('../build/SimpleGriefing.json');


describe('Test Erasure agreements', async () => {
    let agreement;
    let factory;
    let mockNMRContract;
    let numeraiErasureContract;
    const userAddress = '0x0000000000000000000000000000000000000021';

    before(async () => {
        factory = await contracts.deployAgreementFactory();
        mockNMRContract = await contracts.getMockNMR();
        numeraiErasureContract = await contracts.deployNumeraiErasureV1();
        const relay = await contracts.getRelay();
        await relay.transferManagement(numeraiErasureContract.contractAddress);

        await mockNMRContract.transfer(userAddress, utils.parseEther("100"));
        await mockNMRContract.transfer(numeraiErasureContract.signer.address, utils.parseEther("100"));

        await mockNMRContract.from(numeraiErasureContract.signer).approve(numeraiErasureContract.contractAddress, utils.parseEther("11000000"));
    });

    it('should createStake', async () => {
        const stakeAmount = utils.parseEther("10");
        let salt = utils.formatBytes32String("should createStake");
        const callData = contracts.createSimpleGriefingCallData(userAddress, numeraiErasureContract.contractAddress, numeraiErasureContract.contractAddress);

        const agreementAddress = await factory.getSaltyInstance(callData, salt);

        let txn = await numeraiErasureContract.createStake(factory.contractAddress, agreementAddress, userAddress, stakeAmount, callData, salt);

        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "IncreaseStake",
            "There is no increaseStake event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreementAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountAdded.toString(),
            stakeAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            "0",
        );

        const stakeEventCreate = receipt.events.find(
            emittedEvent => emittedEvent.event === "CreateStake",
            "There is no createStake event"
        );

        assert.isDefined(stakeEventCreate);
        assert.equal(stakeEventCreate.args.agreement, agreementAddress);
        assert.equal(stakeEventCreate.args.staker, userAddress);
        assert.strictEqual(
            stakeEventCreate.args.amount.toString(),
            stakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for user');

        agreement = deployer.wrapDeployedContract(SimpleGriefing, agreementAddress);
    });

    it('should increaseStake', async () => {
        const stakeAmount = utils.parseEther("15");
        const oldStakeAmount = utils.parseEther("10");
        let txn = await numeraiErasureContract.increaseStake(agreement.contractAddress, userAddress, oldStakeAmount, stakeAmount);
        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "IncreaseStake",
            "There is no such event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreement.contractAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountAdded.toString(),
            stakeAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            oldStakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("75").toString(), 'balance is wrong for user');
    });

    it('should reward', async () => {
        const stakeAmount = utils.parseEther("10");
        const oldStakeAmount = utils.parseEther("25");

        let txn = await numeraiErasureContract.reward(agreement.contractAddress, userAddress, oldStakeAmount, stakeAmount);
        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "Reward",
            "There is no such event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreement.contractAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountAdded.toString(),
            stakeAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            oldStakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("75").toString(), 'balance is wrong for user');
    });

    it('should punish', async () => {
        const punishAmount = utils.parseEther("10");
        const oldStakeAmount = utils.parseEther("35");

        let txn = await numeraiErasureContract.punish(agreement.contractAddress, userAddress, oldStakeAmount, punishAmount, '0x0');
        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "Punish",
            "There is no such event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreement.contractAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountPunished.toString(),
            punishAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            oldStakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("75").toString(), 'balance is wrong for user');
    });

    it('should releaseStake partial', async () => {
        const releaseAmount = utils.parseEther("10");
        const oldStakeAmount = utils.parseEther("25");

        let txn = await numeraiErasureContract.releaseStake(agreement.contractAddress, userAddress, oldStakeAmount, releaseAmount);
        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "ReleaseStake",
            "There is no such event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreement.contractAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountReleased.toString(),
            releaseAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            oldStakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("85").toString(), 'balance is wrong for user');
    });

    it('should releaseStake full', async () => {
        const releaseAmount = utils.parseEther("15");
        const oldStakeAmount = utils.parseEther("15");

        let txn = await numeraiErasureContract.releaseStake(agreement.contractAddress, userAddress, oldStakeAmount, releaseAmount);
        const receipt = await numeraiErasureContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "ReleaseStake",
            "There is no such event"
        );

        assert.isDefined(stakeEvent);
        assert.equal(stakeEvent.args.agreement, agreement.contractAddress);
        assert.equal(stakeEvent.args.staker, userAddress);
        assert.strictEqual(
            stakeEvent.args.amountReleased.toString(),
            releaseAmount.toString(),
        );
        assert.strictEqual(
            stakeEvent.args.oldStakeAmount.toString(),
            oldStakeAmount.toString(),
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("100").toString(), 'balance is wrong for user');
    });
});
