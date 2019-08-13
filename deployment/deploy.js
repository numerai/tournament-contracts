const etherlime = require('etherlime-lib');
const NumeraiTournamentV2 = require('../build/NumeraiTournamentV2.json');


const deploy = async (network, secret, etherscanApiKey) => {

	const deployer = new etherlime.EtherlimeGanacheDeployer();
	const result = await deployer.deploy(NumeraiTournamentV2);

};
module.exports = {
	deploy
};
