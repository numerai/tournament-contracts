pragma solidity >=0.5.0 <0.6.0;

import "./Pausable.sol";
import "./interfaces/INMR.sol";
import "./helpers/openzeppelin-eth/math/SafeMath.sol";
import "./helpers/zos-lib/Initializable.sol";


/// @title Numerai Tournament logic contract version 1
contract NumeraiTournamentV1 is Initializable, Pausable {

    uint256 public totalStaked;

    mapping (uint256 => Tournament) public tournaments;

    struct Tournament {
        uint256 creationTime;
        uint256[] roundIDs;
        mapping (uint256 => Round) rounds;
    }

    struct Round {
        uint128 creationTime;
        uint128 stakeDeadline;
        mapping (address => mapping (bytes32 => Stake)) stakes;
    }

    struct Stake {
        uint128 amount;
        uint32 confidence;
        uint128 burnAmount;
        bool resolved;
    }

    /* /////////////////// */
    /* Do not modify above */
    /* /////////////////// */

    // define an event for tracking the progress of stake initalization.
    event StakeInitializationProgress(
        bool initialized, // true if stake initialization complete, else false.
        uint256 firstUnprocessedStakeItem // index of the skipped stake, if any.
    );

    using SafeMath for uint256;
    using SafeMath for uint128;

    // set the address of the NMR token as a constant (stored in runtime code)
    address private constant _TOKEN = address(
        0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671
    );

    /// @notice constructor function, used to enforce implementation address
    constructor() public {
        require(
            address(this) == address(0xb2C4DbB78c7a34313600aD2e6E35d188ab4381a8),
            "Incorrect deployment address - check submitting account & nonce."
        );
    }

    /// @notice Initializer function called at time of deployment
    /// @param _owner The address of the wallet to handle permission control
    function initialize(
        address _owner
    ) public initializer {
        // initialize the contract's ownership.
        Pausable.initialize(_owner);
    }

    /// @notice Initializer function to set data for tournaments and the active
    ///         rounds (i.e. the four most recent) on each of the tournaments.
    /// @param _startingRoundID The most recent round ID to initialize - this
    ///        assumes that each round has a higher roundID than the last and
    ///        that each active round will have the same roundID as other rounds
    ///        that are started at approximately the same time.
    function initializeTournamentsAndActiveRounds(
        uint256 _startingRoundID
    ) public onlyManagerOrOwner {
        // set up the NMR token interface.
        INMR nmr = INMR(_TOKEN);

        // initialize tournament one through seven with four most recent rounds.
        for (uint256 tournamentID = 1; tournamentID <= 7; tournamentID++) {
            // determine the creation time and the round IDs for the tournament.
            (
                uint256 tournamentCreationTime,
                uint256[] memory roundIDs
            ) = nmr.getTournament(tournamentID);

            // update the creation time of the tournament in storage.
            tournaments[tournamentID].creationTime = tournamentCreationTime;

            // skip round initialization if there are no rounds.
            if (roundIDs.length == 0) {
                continue;
            }

            // find the most recent roundID.
            uint256 mostRecentRoundID = roundIDs[roundIDs.length - 1];

            // skip round initialization if mostRecentRoundID < _startingRoundID
            if (mostRecentRoundID < _startingRoundID) {
                continue;
            }

            // track how many rounds are initialized.
            uint256 initializedRounds = 0;

            // iterate through and initialize each round.
            for (uint256 j = 0; j < roundIDs.length; j++) {
                // get the current round ID.
                uint256 roundID = roundIDs[j];

                // skip this round initialization if roundID < _startingRoundID
                if (roundID < _startingRoundID) {
                    continue;
                }

                // add the roundID to roundIDs in storage.
                tournaments[tournamentID].roundIDs.push(roundID);

                // get more information on the round.
                (
                    uint256 creationTime,
                    uint256 endTime,
                ) = nmr.getRound(tournamentID, roundID);

                // set that information in storage.
                tournaments[tournamentID].rounds[roundID] = Round({
                    creationTime: uint128(creationTime),
                    stakeDeadline: uint128(endTime)
                });

                // increment the number of initialized rounds.
                initializedRounds++;
            }

            // delete the initialized rounds from the old tournament.
            require(
                nmr.createRound(tournamentID, initializedRounds, 0, 0),
                "Could not delete round from legacy tournament."
            );
        }
    }

    /// @notice Initializer function to set the data of the active stakes
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    function initializeStakes(
        uint256[] memory tournamentID,
        uint256[] memory roundID,
        address[] memory staker,
        bytes32[] memory tag
    ) public onlyManagerOrOwner {
        // set and validate the size of the dynamic array arguments.
        uint256 num = tournamentID.length;
        require(
            roundID.length == num &&
            staker.length == num &&
            tag.length == num,
            "Input data arrays must all have same length."
        );

        // start tracking the total stake amount.
        uint256 stakeAmt = 0;

        // set up the NMR token interface.
        INMR nmr = INMR(_TOKEN);

        // track completed state; this will be set to false if we exit early.
        bool completed = true;

        // track progress; set to the first skipped item if we exit early.
        uint256 progress;

        // iterate through each supplied stake.
        for (uint256 i = 0; i < num; i++) {
            // check gas and break if we're starting to run low.
            if (gasleft() < 100000) {
                completed = false;
                progress = i;
                break;
            }

            // get the amount and confidence
            (uint256 confidence, uint256 amount, , bool resolved) = nmr.getStake(
                tournamentID[i],
                roundID[i],
                staker[i],
                tag[i]
            );

            // only set it if the stake actually exists on the old tournament.
            if (amount > 0 || resolved) {
                uint256 currentTournamentID = tournamentID[i];
                uint256 currentRoundID = roundID[i];

                // destroy the stake on the token contract.
                require(
                    nmr.destroyStake(
                        staker[i], tag[i], currentTournamentID, currentRoundID
                    ),
                    "Could not destroy stake from legacy tournament."
                );

                // get the stake object.
                Stake storage stakeObj = tournaments[currentTournamentID]
                                           .rounds[currentRoundID]
                                           .stakes[staker[i]][tag[i]];

                // only set stake if it isn't already set on new tournament.
                if (stakeObj.amount == 0 && !stakeObj.resolved) {

                    // increase the total stake amount by the retrieved amount.
                    stakeAmt = stakeAmt.add(amount);

                    // set the amount on the stake object.
                    if (amount > 0) {
                        stakeObj.amount = uint128(amount);
                    }

                    // set the confidence on the stake object.
                    stakeObj.confidence = uint32(confidence);

                    // set returned to true if the round was resolved early.
                    if (resolved) {
                        stakeObj.resolved = true;
                    }

                }
            }
        }

        // increase the total stake by the sum of each imported stake amount.
        totalStaked = totalStaked.add(stakeAmt);

        // log the success status and the first skipped item if not completed.
        emit StakeInitializationProgress(completed, progress);
    }

    /// @notice Function to transfer tokens once intialization is completed.
    function settleStakeBalance() public onlyManagerOrOwner {
        // send the stake amount from the caller to this contract.
        require(INMR(_TOKEN).withdraw(address(0), address(0), totalStaked),
            "Stake balance was not successfully set on new tournament.");
    }

    /// @notice Get the state of a tournament in this version
    /// @param tournamentID The index of the tournament
    /// @return creationTime The UNIX timestamp of the tournament creation
    /// @return roundIDs The array of index of the tournament rounds
    function getTournamentV2(uint256 tournamentID) public view returns (
        uint256 creationTime,
        uint256[] memory roundIDs
    ) {
        Tournament storage tournament = tournaments[tournamentID];
        return (tournament.creationTime, tournament.roundIDs);
    }

    /// @notice Get the state of a round in this version
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @return creationTime The UNIX timestamp of the round creation
    /// @return stakeDeadline The UNIX timestamp of the round deadline for staked submissions
    function getRoundV2(uint256 tournamentID, uint256 roundID) public view returns (
        uint256 creationTime,
        uint256 stakeDeadline
    ) {
        Round storage round = tournaments[tournamentID].rounds[roundID];
        return (uint256(round.creationTime), uint256(round.stakeDeadline));
    }

    /// @notice Get the state of a staked submission in this version
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @return amount The amount of NMR in wei staked with this submission
    /// @return confidence The confidence threshold attached to this submission
    /// @return burnAmount The amount of NMR in wei burned by the resolution
    /// @return resolved True if the staked submission has been resolved
    function getStakeV2(uint256 tournamentID, uint256 roundID, address staker, bytes32 tag) public view returns (
        uint256 amount,
        uint256 confidence,
        uint256 burnAmount,
        bool resolved
    ) {
        Stake storage stakeObj = tournaments[tournamentID].rounds[roundID].stakes[staker][tag];
        return (stakeObj.amount, stakeObj.confidence, stakeObj.burnAmount, stakeObj.resolved);
    }

    /// @notice Get the state of a tournament in this version
    /// @param tournamentID The index of the tournament
    /// @return creationTime The UNIX timestamp of the tournament creation
    /// @return roundIDs The array of index of the tournament rounds
    function getTournamentV1(uint256 tournamentID) public view returns (
        uint256 creationTime,
        uint256[] memory roundIDs
    ) {
        return INMR(_TOKEN).getTournament(tournamentID);
    }

    /// @notice Get the state of a round in this version
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @return creationTime The UNIX timestamp of the round creation
    /// @return endTime The UNIX timestamp of the round deadline for staked submissions
    /// @return resolutionTime The UNIX timestamp of the round start time for resolutions
    function getRoundV1(uint256 tournamentID, uint256 roundID) public view returns (
        uint256 creationTime,
        uint256 endTime,
        uint256 resolutionTime
    ) {
        return INMR(_TOKEN).getRound(tournamentID, roundID);
    }

    /// @notice Get the state of a staked submission in this version
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @return confidence The confidence threshold attached to this submission
    /// @return amount The amount of NMR in wei staked with this submission
    /// @return successful True if the staked submission beat the threshold
    /// @return resolved True if the staked submission has been resolved
    function getStakeV1(uint256 tournamentID, uint256 roundID, address staker, bytes32 tag) public view returns (
        uint256 confidence,
        uint256 amount,
        bool successful,
        bool resolved
    ) {
        return INMR(_TOKEN).getStake(tournamentID, roundID, staker, tag);
    }
}
