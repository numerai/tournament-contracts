const etherlime = require('etherlime-lib');
const utils = require('ethers').utils;
const Wallet = require('ethers').Wallet;

const NumeraiTournamentV2 = require('../build/NumeraiTournamentV2.json');
const Relay = require('../build/Relay.json');
const MockNMR = require('../build/MockNMR.json');

const nmrTokenDeployer = '0x9608010323ed882a38ede9211d7691102b4f0ba0';
const multiSigWallet = '0x249e479b571Fea3DE01F186cF22383a79b21ca7F';

const fundedAccountPrivateKey = '0x4f3edf983ac636a65a842ce7c78d9aa706d3b113bce9c46f30d7d21715b23b1d';

async function increaseNonce(signer, increaseTo) {
    const currentNonce = await signer.getTransactionCount();
    if (currentNonce === increaseTo) {
        return;
    }
    if (currentNonce > increaseTo) {
        throw Error(`nonce is greater than desired value ${currentNonce} > ${increaseTo}`);
    }

    for (let index = 0; index < increaseTo - currentNonce; index++) {
        const transaction = {
            to: multiSigWallet, // just send to a random address, it doesn't really matter who
            value: utils.parseEther("0.0000000000001"),
        }
        await signer.sendTransaction(transaction);
    }
}

describe('Setup Accounts And Deploy Contracts', () => {
    let deployer;
    let v2Contract, relayContract, mockNMRContract;

    before(async () => {
        deployer = new etherlime.EtherlimeGanacheDeployer(fundedAccountPrivateKey);

        let transaction = {
            to: nmrTokenDeployer,
            value: utils.parseEther("10.0"),
        }

        await deployer.signer.sendTransaction(transaction);
        console.log("sent 10 eth to " + nmrTokenDeployer);

        transaction = {
            to: multiSigWallet,
            value: utils.parseEther("10.0"),
        }

        await deployer.signer.sendTransaction(transaction);
        console.log("sent 10 eth to " + multiSigWallet);
    });

    it('should deploy mockNMR', async () => {
        deployer.signer = deployer.provider.getSigner(nmrTokenDeployer);
        await increaseNonce(deployer.signer, 1);
        mockNMRContract = await deployer.deploy(MockNMR, {});

        let balance = await mockNMRContract.balanceOf('0x0000000000000000000000000000000000000001');

        assert.strictEqual(balance.toString(), utils.parseEther("100").toString(), 'Initial balance is wrong');
    });

    it('should deploy tournament', async () => {
        deployer.signer = deployer.provider.getSigner(multiSigWallet);
        await increaseNonce(deployer.signer, 1);
        v2Contract = await deployer.deploy(NumeraiTournamentV2, {});
        await v2Contract.initialize(multiSigWallet);

        let _owner = await v2Contract.owner();

        assert.strictEqual(_owner, multiSigWallet, 'Initial contract owner does not match');
    });

    it('should deploy relay', async () => {
        deployer.signer = deployer.provider.getSigner(multiSigWallet);
        await increaseNonce(deployer.signer, 5);
        relayContract = await deployer.deploy(Relay, {}, v2Contract.contractAddress);

        let _owner = await relayContract.owner();

        assert.strictEqual(_owner, v2Contract.contractAddress, 'Initial contract owner does not match');
    });

    it('should withdraw through tournament', async () => {
        await v2Contract.withdraw('0x0000000000000000000000000000000000000005', '0x0000000000000000000000000000000000000010', utils.parseEther("10").toString());

        let balance = await mockNMRContract.balanceOf('0x0000000000000000000000000000000000000005');
        assert.strictEqual(balance.toString(), utils.parseEther("90").toString(), 'balance is wrong for 0x05');

        balance = await mockNMRContract.balanceOf('0x0000000000000000000000000000000000000010');
        assert.strictEqual(balance.toString(), utils.parseEther("10").toString(), 'balance is wrong for 0x10');
    });
});
