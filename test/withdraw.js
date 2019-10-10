
const contracts = require('./helpers/contracts');

const utils = require('ethers').utils;

describe('Test withdrawals', () => {
    let tournamentContract;
    let nmrContract;

    before(async () => {
        tournamentContract = await contracts.getTournament();
        nmrContract = await contracts.getMockNMR();
        const relay = await contracts.getRelay();
        await relay.transferManagement(tournamentContract.contractAddress);
    })

    it('should withdraw through tournament', async () => {
        await tournamentContract.withdraw('0x0000000000000000000000000000000000000005', '0x0000000000000000000000000000000000000010', utils.parseEther("10").toString());

        let balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000005');
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for 0x05');

        balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000010');
        assert.strictEqual(balance.toString(), utils.parseEther("10").toString(), 'balance is wrong for 0x10');
    });
});
