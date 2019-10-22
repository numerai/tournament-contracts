const etherlime = require("etherlime-lib");
const ethers = require("ethers");
const path = require("path");

const deploy = async (network, secret) => {
  require("dotenv").config({
    path: path.resolve(__dirname, `../${network}.env`)
  });

  let c = {
    NumeraiErasureV1: {
      artifact: require("../build/NumeraiErasureV1.json")
    },
    AdminUpgradeabilityProxy: {
      artifact: require("../build/AdminUpgradeabilityProxy.json")
    }
  };

  let deployer;
  const multisig = "0x0000000000377d181a0ebd08590c6b399b272000";
  const hotwallet = "0xdc6997b078C709327649443D0765BCAa8e37aA6C";
  const proxyadmin = "0x047EbD5F7431c005c9D3a59CE0675ac998417e9d";

  let defaultGas = ethers.utils.parseUnits("15", "gwei");

  if (network == "mainnet" || network == "rinkeby") {
    // initialize deployer
    deployer = await new etherlime.InfuraPrivateKeyDeployer(
      process.env.DEPLOYMENT_PRIV_KEY,
      network,
      process.env.INFURA_API_KEY,
      { gasPrice: defaultGas, etherscanApiKey: process.env.ETHERSCAN_API_KEY }
    );

    console.log(`Deployment Wallet: ${deployer.signer.address}`);
  } else if (network == "ganache") {
    // initialize deployer
    deployer = new etherlime.EtherlimeGanacheDeployer(
      process.env.DEPLOYMENT_PRIV_KEY
    );
    deployer.deployAndVerify = deployer.deploy;
  }

  console.log(`
Deploy NumeraiErasureV1
          `);

  // deploy NumeraiErasureV1 template
  c.NumeraiErasureV1.template = await deployer.deployAndVerify(
    c.NumeraiErasureV1.artifact
  );

  // create initialize(...) encoded call. This will be called by the
  // AdminUpgradeabilityProxy, when initializing the NumeraiErasureV1 template
  const initializeInterface = new ethers.utils.Interface([
    "initialize(address _owner)"
  ]);
  const initializeCallData = await initializeInterface.functions.initialize.encode(
    [deployer.signer.address]
  ); // set the owner to the deployer, and then transfer ownership at the end of this script

  // deploy AdminUpgradeabilityProxy
  c.AdminUpgradeabilityProxy.instance = await deployer.deployAndVerify(
    c.AdminUpgradeabilityProxy.artifact,
    false,
    c.NumeraiErasureV1.template.contractAddress,
    proxyadmin, // proxyadmin is the admin of AdminUpgradeabilityProxy
    initializeCallData
  );

  // wrap the deployed AdminUpgradeabilityProxy as a NumeraiErasureV1
  c.NumeraiErasureV1.instance = deployer.wrapDeployedContract(
    c.NumeraiErasureV1.artifact,
    c.AdminUpgradeabilityProxy.instance.contractAddress
  );

  // TODO pass in gas price
  // transfer ownership/management
  await c.NumeraiErasureV1.instance.transferManagement(hotwallet);
  console.log(`Successfully transferred management to ${hotwallet}`);
  await c.NumeraiErasureV1.instance.transferOwnership(multisig);
  console.log(`Successfully transferred ownership to ${multisig}`);
};

module.exports = { deploy };
