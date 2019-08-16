
const contracts = require('./helpers/contracts');

const utils = require('ethers').utils;

describe('Test withdrawals', () => {
    it('should withdraw through tournament', async () => {
        const mockNMRContract = await contracts.getMockNMR();
        const tournamentContract = await contracts.getTournament();

        await tournamentContract.withdraw('0x0000000000000000000000000000000000000005', '0x0000000000000000000000000000000000000010', utils.parseEther("10").toString());

        let balance = await mockNMRContract.balanceOf('0x0000000000000000000000000000000000000005');
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for 0x05');

        balance = await mockNMRContract.balanceOf('0x0000000000000000000000000000000000000010');
        assert.strictEqual(balance.toString(), utils.parseEther("10").toString(), 'balance is wrong for 0x10');
    });
});
