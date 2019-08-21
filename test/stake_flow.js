const constants = require("./helpers/constants");
const contracts = require("./helpers/contracts");

const utils = require("ethers").utils;

describe("Test stake flow", () => {
  const roundDeadline = 1881269948;
  let tournamentContract;
  let nmrContract;
  let agreementContract;

  before(async () => {
    tournamentContract = await contracts.getTournament();
    nmrContract = await contracts.getMockNMR();
    agreementContract = await contracts.deployAgreement(
      tournamentContract.contractAddress, // operator
      constants.nmrTokenDeployer, // staker
      tournamentContract.contractAddress // counterparty
    );
  });

  it("should create tournament", async () => {
    await tournamentContract.createTournament(1);

    const tournament = await tournamentContract.getTournamentV2(1);
    assert.isOk(tournament.creationTime, "tournament not set");
  });

  it("should revert duplicate tournament", async () => {
    await assert.revertWith(
      tournamentContract.createTournament(1),
      "Tournament must not already be initialized"
    );
  });

  it("should create round", async () => {
    await tournamentContract.createRound(1, 1, roundDeadline);

    const round = await tournamentContract.getRoundV2(1, 1);
    assert.equal(round.stakeDeadline, roundDeadline, "round not set");
  });

  it("should revert duplicate round", async () => {
    await assert.revertWith(
      tournamentContract.createRound(1, 1, roundDeadline),
      "roundID must be increasing"
    );
  });

  it("should fail create stake without approve", async () => {
    const tag = utils.formatBytes32String("");

    await assert.revertWith(
      contracts
        .contractFrom(tournamentContract, constants.nmrTokenDeployer)
        .stake(
          1,
          1,
          tag,
          utils.parseEther("1"),
          0,
          agreementContract.contractAddress
        ),
      "insufficient allowance"
    );

    const stake = await tournamentContract.getStakeV2(
      1,
      1,
      constants.multiSigWallet,
      tag
    );
    assert.equal(stake.amount, 0, "stake not set");
  });

  it("should create stake", async () => {
    const tag = utils.formatBytes32String("");

    await contracts
      .contractFrom(nmrContract, constants.nmrTokenDeployer)
      .approve(tournamentContract.contractAddress, utils.parseEther("1"));
    await contracts
      .contractFrom(tournamentContract, constants.nmrTokenDeployer)
      .stake(
        1,
        1,
        tag,
        utils.parseEther("1"),
        0,
        agreementContract.contractAddress
      );

    const stake = await tournamentContract.getStakeV2(
      1,
      1,
      constants.nmrTokenDeployer,
      tag
    );
    assert.strictEqual(
      stake.amount.toString(),
      utils.parseEther("1").toString(),
      "stake not set"
    );
  });

  it("should stakeOnBehalf fail with no balance", async () => {
    const tag = utils.formatBytes32String("");
    const staker = "0x0000000000000000000000000000000000000100";

    await assert.revertWith(
      tournamentContract.stakeOnBehalf(
        1,
        1,
        staker,
        tag,
        utils.parseEther("1"),
        0,
        agreementContract.contractAddress
      ),
      ""
    );

    const stake = await tournamentContract.getStakeV2(1, 1, staker, tag);
    assert.equal(stake.amount, 0, "stake not set");
  });

  it("should stakeOnBehalf", async () => {
    const tag = utils.formatBytes32String("");
    const staker = "0x0000000000000000000000000000000000000100";

    await nmrContract.transfer(staker, utils.parseEther("2"));
    await tournamentContract.stakeOnBehalf(
      1,
      1,
      staker,
      tag,
      utils.parseEther("1"),
      0,
      agreementContract.contractAddress
    );

    const stake = await tournamentContract.getStakeV2(1, 1, staker, tag);
    assert.strictEqual(
      stake.amount.toString(),
      utils.parseEther("1").toString(),
      "stake not set"
    );
  });
});
