const contracts = require('./helpers/contracts');
const constants = require('./helpers/constants');
const etherlime = require('etherlime-lib');

const utils = require('ethers').utils;


describe('Test Erasure agreements', async () => {
    let agreement;
    let mockNMRContract;
    let tournamentContract;
    const userAddress = '0x0000000000000000000000000000000000000021';

    beforeEach(async () => {
        agreement = await contracts.deployAgreement(userAddress, constants.multiSigWallet, constants.tournamenContractAddress);
        mockNMRContract = await contracts.getMockNMR();
        tournamentContract = await contracts.getTournament();

        await mockNMRContract.transfer(userAddress, utils.parseEther("100"));
    });

    it('should increaseStake', async () => {
        const stakeAmount = utils.parseEther("10");
        let txn = await tournamentContract.increaseStakeErasure(agreement.contractAddress, userAddress, 0, stakeAmount);
        const receipt = await tournamentContract.verboseWaitForTransaction(txn);
        const stakeEvent = receipt.events.find(
            emittedEvent => emittedEvent.event === "IncreaseStakeErasure",
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
            "0",
        );

        let balance = await mockNMRContract.balanceOf(userAddress);
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for user');
    });
});
