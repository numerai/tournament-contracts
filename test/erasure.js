const contracts = require("./helpers/contracts");
const constants = require("./helpers/constants");
const etherlime = require("etherlime-lib");

const utils = require("ethers").utils;

describe("Test Erasure agreements", async () => {
  let agreement;
  let mockNmr;
  const userAddress = "0x0000000000000000000000000000000000000021";

  beforeEach(async () => {
    agreement = await contracts.deployAgreement(
      userAddress,
      constants.multiSigWallet
    );
    mockNmr = await contracts.getMockNMR();

    await mockNmr.transfer(userAddress, utils.parseEther("100"));
    await mockNmr.transfer(constants.multiSigWallet, utils.parseEther("100"));
  });

  it("should stake", async () => {
    const contract = contracts.contractFrom(mockNmr, userAddress);
    let txn = await contract.approve(
      agreement.contractAddress,
      utils.parseEther("1")
    );
    // const receipt = await mockNmr.verboseWaitForTransaction(txn);
    console.log("txn", txn);
    txn = await contracts
      .contractFrom(agreement, userAddress)
      .increaseStake(0, utils.parseEther("1"));
  });

  it("should reward", async () => {
    const contract = contracts.contractFrom(mockNmr, constants.multiSigWallet);
    await contract.approve(agreement.contractAddress, utils.parseEther("1"));
    const txn = await contracts
      .contractFrom(agreement, constants.multiSigWallet)
      .reward(0, utils.parseEther("1"));
  });
});
