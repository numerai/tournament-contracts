const etherlime = require("etherlime-lib");
const ethers = require("ethers");
const path = require("path");

const deploy = async (network, secret) => {
    require("dotenv").config({ path: path.resolve(__dirname, `../${network}.env`) });

    let c = {
        NMR: {
            artifact: require("../build/MockNMR.json"),
            mainnet: {
                address: "0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671"
            },
            rinkeby: {
                address: "0x1A758E75d1082BAab0A934AFC7ED27Dbf6282373"
            },
            ganache: {
                address: "0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671"
            }
        },
        NumeraiErasureV1: {
            artifact: require("../build/NumeraiErasureV1.json"),
        },
    };

    let deployer;
    let multisig;

    let defaultGas = ethers.utils.parseUnits("15", "gwei");

    if (network == "mainnet") {
        // set owner address
        multisig = "0x0000000000377d181a0ebd08590c6b399b272000";

        // initialize deployer
        deployer = await new etherlime.InfuraPrivateKeyDeployer(
            process.env.DEPLOYMENT_PRIV_KEY,
            "mainnet",
            process.env.INFURA_API_KEY,
            { gasPrice: defaultGas, etherscanApiKey: process.env.ETHERSCAN_API_KEY }
        );

        console.log(`Deployment Wallet: ${deployer.signer.address}`);
    } else if (network == "ganache") {
        // initialize deployer
        deployer = new etherlime.EtherlimeGanacheDeployer(process.env.DEPLOYMENT_PRIV_KEY);
        deployer.deployAndVerify = deployer.deploy;
        multisig = deployer.signer.address;
    }

    console.log(`
Deploy NumeraiErasureV1
          `);

    await deployer.deployAndVerify(c.NumeraiErasureV1.artifact).then(wrap => {
        c.NumeraiErasureV1[network] = {
            wrap: wrap,
            address: wrap.contractAddress
        };
    });

    console.log(`address ${c.NumeraiErasureV1[network].address}`);
};

module.exports = { deploy };
