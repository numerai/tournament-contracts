
const contracts = require('./helpers/contracts');

const utils = require('ethers').utils;

describe('Test withdrawals', () => {
    let numeraiErasureContract;
    let tournamentContract;
    let nmrContract;
    let relay;

    before(async () => {
        numeraiErasureContract = await contracts.deployNumeraiErasureV1();
        tournamentContract = await contracts.getTournament();
        nmrContract = await contracts.getMockNMR();
        relay = await contracts.getRelay();
    })

    it('should withdraw through tournament', async () => {
        await relay.transferManagement(tournamentContract.contractAddress);

        await tournamentContract.withdraw('0x0000000000000000000000000000000000000005', '0x0000000000000000000000000000000000000010', utils.parseEther("10").toString());

        let balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000005');
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for 0x05');

        balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000010');
        assert.strictEqual(balance.toString(), utils.parseEther("10").toString(), 'balance is wrong for 0x10');
    });

    it('should withdraw through numeraierasure', async () => {
        await relay.transferManagement(numeraiErasureContract.contractAddress);

        await numeraiErasureContract.withdraw('0x0000000000000000000000000000000000000005', '0x0000000000000000000000000000000000000010', utils.parseEther("10").toString());

        let balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000005');
        assert.strictEqual(balance.toString(), utils.parseEther("80").toString(), 'balance is wrong for 0x05');

        balance = await nmrContract.balanceOf('0x0000000000000000000000000000000000000010');
        assert.strictEqual(balance.toString(), utils.parseEther("20").toString(), 'balance is wrong for 0x10');
    });
});
