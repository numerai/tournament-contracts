const constants = require('./constants');

const etherlime = require('etherlime-lib');
const utils = require('ethers').utils;

const NumeraiTournamentV2 = require('../../build/NumeraiTournamentV2.json');
const Relay = require('../../build/Relay.json');
const MockNMR = require('../../build/MockNMR.json');

async function increaseNonce(signer, increaseTo) {
    const currentNonce = await signer.getTransactionCount();
    if (currentNonce === increaseTo) {
        return;
    }
    if (currentNonce > increaseTo) {
        throw `nonce is greater than desired value ${currentNonce} > ${increaseTo}`;
    }

    for (let index = 0; index < increaseTo - currentNonce; index++) {
        const transaction = {
            to: constants.multiSigWallet, // just send to a random address, it doesn't really matter who
            value: utils.parseEther("0.0000000000001"),
        }
        await signer.sendTransaction(transaction);
    }
}
async function fundEth(to) {
    deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);

    let transaction = {
        to: to,
        value: utils.parseEther("1.0"),
    }

    await deployer.signer.sendTransaction(transaction);
}

let _mockNmrContract;
async function _deployMockNMR() {
    const deployAddress = constants.nmrTokenDeployer;
    await fundEth(deployAddress);

    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);
    deployer.signer = deployer.provider.getSigner(deployAddress);
    await increaseNonce(deployer.signer, 1);

    const contract = await deployer.deploy(MockNMR, {});

    return contract;
}
async function getMockNMR() {
    if (!_mockNmrContract) {
        _mockNmrContract = _deployMockNMR();
    }

    return await _mockNmrContract;
}

let _tournamentContract;
async function _deployTournament() {
    const deployAddress = constants.multiSigWallet;

    await fundEth(deployAddress);

    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);
    deployer.signer = deployer.provider.getSigner(deployAddress);
    await increaseNonce(deployer.signer, 1);

    const contract = await deployer.deploy(NumeraiTournamentV2, {});

    await contract.initialize(deployAddress);

    return contract;
}
async function getTournament() {
    if (!_tournamentContract) {
        _tournamentContract = _deployTournament();
    }

    return await _tournamentContract;
}

let _relayContract;
async function _deployRelay() {
    const deployAddress = constants.multiSigWallet;

    const tournContract = await getTournament();

    await fundEth(deployAddress);

    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);
    deployer.signer = deployer.provider.getSigner(deployAddress);
    await increaseNonce(deployer.signer, 5);

    const contract = await deployer.deploy(Relay, {}, tournContract.contractAddress);

    return contract;
}
async function getRelay() {
    if (!_relayContract) {
        _relayContract = _deployRelay();
    }

    return await _relayContract;
}

module.exports = {
    getMockNMR,
    getTournament,
    getRelay,
};
