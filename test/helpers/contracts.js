const constants = require('./constants');

const etherlime = require('etherlime-lib');
const utils = require('ethers').utils;
const ethers = require('ethers');

const NumeraiTournament = require('../../build/NumeraiTournamentV3.json');
const Relay = require('../../build/Relay.json');
const MockNMR = require('../../build/MockNMR.json');
const SimpleGriefingFactory = require('../../build/SimpleGriefing_Factory.json');
const SimpleGriefing = require('../../build/SimpleGriefing.json');

async function increaseNonce(signer, increaseTo) {
    const currentNonce = await signer.getTransactionCount();
    if (currentNonce === increaseTo) {
        return;
    }
    if (currentNonce > increaseTo) {
        throw new Error(`nonce is greater than desired value ${currentNonce} > ${increaseTo}`);
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

    const contract = await deployer.deploy(MockNMR);

    await contract.mintMockTokens('0x0000000000000000000000000000000000000001', utils.parseEther("100").toString());
    await contract.mintMockTokens('0x0000000000000000000000000000000000000002', utils.parseEther("100").toString());
    await contract.mintMockTokens('0x0000000000000000000000000000000000000003', utils.parseEther("100").toString());
    await contract.mintMockTokens('0x0000000000000000000000000000000000000004', utils.parseEther("100").toString());
    await contract.mintMockTokens('0x0000000000000000000000000000000000000005', utils.parseEther("100").toString());

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
    await increaseNonce(deployer.signer, 23);

    const contract = await deployer.deploy(NumeraiTournament, {});

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

    await fundEth(deployAddress);

    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);
    deployer.signer = deployer.provider.getSigner(deployAddress);
    await increaseNonce(deployer.signer, 5);

    const contract = await deployer.deploy(Relay, {}, constants.tournamenContractAddress);

    return contract;
}
async function getRelay() {
    if (!_relayContract) {
        _relayContract = _deployRelay();
    }

    return await _relayContract;
}

function createSelector(functionName, abiTypes) {
    const joinedTypes = abiTypes.join(",");
    const functionSignature = `${functionName}(${joinedTypes})`;

    const selector = ethers.utils.hexDataSlice(
        ethers.utils.keccak256(ethers.utils.toUtf8Bytes(functionSignature)),
        0,
        4
    );
    return selector;
}

function abiEncodeWithSelector(functionName, abiTypes, abiValues) {
    const abiEncoder = new ethers.utils.AbiCoder();
    const initData = abiEncoder.encode(abiTypes, abiValues);
    const selector = createSelector(
        functionName,
        abiTypes
    );
    const encoded = selector + initData.slice(2);
    return encoded;
}

async function deployAgreement(staker, counterparty, operator = ethers.constants.AddressZero) {
    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);

    const template = await deployer.deploy(SimpleGriefing, {});
    const factory = await deployer.deploy(SimpleGriefingFactory, {}, template.contractAddress, template.contractAddress);

    const createTypes = [
        "address",
        "address",
        "address",
        "uint256",
        "uint8",
        "bytes"
    ];

    const createArgs = [
        operator,
        staker,
        counterparty,
        0,
        1, // 1 = Inf griefing type
        '0x0'
    ];

    const callData = abiEncodeWithSelector("initialize", createTypes, createArgs);

    const txn = await factory.create(callData);
    const receipt = await factory.verboseWaitForTransaction(txn);
    const expectedEvent = "InstanceCreated";
    const eventFound = receipt.events.find(
        emittedEvent => emittedEvent.event === expectedEvent,
        "There is no such event"
    );

    const contract = deployer.wrapDeployedContract(SimpleGriefing, eventFound.args.instance);
    return contract;
}

// It turns out etherlime only supports calling `contract.from` on the built in addresses
// For custom addresses such as the multisig wallet, we have to use the following instead
function contractFrom(contract, address) {
    const deployer = new etherlime.EtherlimeGanacheDeployer(constants.fundedAccountPrivateKey);
    const signer = deployer.provider.getSigner(address);
    return contract.contract.connect(signer);
}

module.exports = {
    getMockNMR,
    getTournament,
    getRelay,
    deployAgreement,
    contractFrom,
};
