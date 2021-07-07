pragma solidity >=0.5.0 <0.6.0;

import "./Pausable.sol";
import "./interfaces/IRelay.sol";
import "./interfaces/INMR.sol";
import "./interfaces/IErasureStake.sol";
import "./helpers/zos-lib/Initializable.sol";
import "./helpers/openzeppelin-solidity/math/SafeMath.sol";


/// @title Numerai Tournament logic contract version 3
contract NumeraiTournamentV3 is Initializable, Pausable {

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

    using SafeMath for uint256;
    using SafeMath for uint128;

    event Staked(
        uint256 indexed tournamentID,
        uint256 indexed roundID,
        address indexed staker,
        bytes32 tag,
        uint256 stakeAmount,
        uint256 confidence
    );
    event StakeResolved(
        uint256 indexed tournamentID,
        uint256 indexed roundID,
        address indexed staker,
        bytes32 tag,
        uint256 originalStake,
        uint256 burnAmount
    );
    event RoundCreated(
        uint256 indexed tournamentID,
        uint256 indexed roundID,
        uint256 stakeDeadline
    );
    event TournamentCreated(
        uint256 indexed tournamentID
    );
    event IncreaseStakeErasure(
        address indexed agreement,
        address indexed staker,
        uint256 oldStakeAmount,
        uint256 amountAdded
    );

    // set the address of the NMR token as a constant (stored in runtime code)
    address private constant _TOKEN = address(
        0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671
    );

    // set the address of the relay as a constant (stored in runtime code)
    address private constant _RELAY = address(
        0xB17dF4a656505570aD994D023F632D48De04eDF2
    );

    /// @dev Throws if the roundID given is not greater than the latest one
    modifier onlyNewRounds(uint256 tournamentID, uint256 roundID) {
        uint256 length = tournaments[tournamentID].roundIDs.length;
        if (length > 0) {
            uint256 lastRoundID = tournaments[tournamentID].roundIDs[length - 1];
            require(roundID > lastRoundID, "roundID must be increasing");
        }
        _;
    }

    /// @dev Throws if the uint256 input is bigger than the max uint128
    modifier onlyUint128(uint256 a) {
        require(
            a < 0x100000000000000000000000000000000,
            "Input uint256 cannot be larger than uint128"
        );
        _;
    }

    /// @notice Initializer function called at time of deployment
    /// @param _owner The address of the wallet to handle permission control
    function initialize(
        address _owner
    ) public initializer {
        // initialize the contract's ownership.
        Pausable.initialize(_owner);
    }

    /////////////////////////////
    // Fund Recovery Functions //
    /////////////////////////////

    /// @notice Recover the ETH sent to this contract address
    ///         Can only be called by Numerai
    /// @param recipient The address of the recipient
    function recoverETH(address payable recipient) public onlyOwner {
        recipient.transfer(address(this).balance);
    }

    /// @notice Recover the NMR sent to this address
    ///         Can only be called by Numerai
    /// @param recipient The address of the recipient
    function recoverNMR(address payable recipient) public onlyOwner {
        uint256 balance = INMR(_TOKEN).balanceOf(address(this));
        uint256 amount = balance.sub(totalStaked);
        require(INMR(_TOKEN).transfer(recipient, amount));
    }

    ///////////////////////
    // Batched Functions //
    ///////////////////////

    /// @notice A batched version of stakeOnBehalf()
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @param stakeAmount The amount of NMR in wei to stake with this submission
    /// @param confidence The confidence threshold to submit with this submission
    function batchStakeOnBehalf(
        uint256[] calldata tournamentID,
        uint256[] calldata roundID,
        address[] calldata staker,
        bytes32[] calldata tag,
        uint256[] calldata stakeAmount,
        uint256[] calldata confidence
    ) external {
        uint256 len = tournamentID.length;
        require(
            roundID.length == len &&
            staker.length == len &&
            tag.length == len &&
            stakeAmount.length == len &&
            confidence.length == len,
            "Inputs must be same length"
        );
        for (uint i = 0; i < len; i++) {
            stakeOnBehalf(tournamentID[i], roundID[i], staker[i], tag[i], stakeAmount[i], confidence[i]);
        }
    }

    /// @notice A batched version of withdraw()
    /// @param from The user address
    /// @param to The recipient address
    /// @param value The amount of NMR in wei
    function batchWithdraw(
        address[] calldata from,
        address[] calldata to,
        uint256[] calldata value
    ) external {
        uint256 len = from.length;
        require(
            to.length == len &&
            value.length == len,
            "Inputs must be same length"
        );
        for (uint i = 0; i < len; i++) {
            withdraw(from[i], to[i], value[i]);
        }
    }

    /// @notice A batched version of resolveStake()
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @param burnAmount The amount of NMR in wei to burn from the stake
    function batchResolveStake(
        uint256[] calldata tournamentID,
        uint256[] calldata roundID,
        address[] calldata staker,
        bytes32[] calldata tag,
        uint256[] calldata burnAmount
    ) external {
        uint256 len = tournamentID.length;
        require(
            roundID.length == len &&
            staker.length == len &&
            tag.length == len &&
            burnAmount.length == len,
            "Inputs must be same length"
        );
        for (uint i = 0; i < len; i++) {
            resolveStake(tournamentID[i], roundID[i], staker[i], tag[i], burnAmount[i]);
        }
    }

    //////////////////////////////
    // Special Access Functions //
    //////////////////////////////

    /// @notice Stake a round submission on behalf of a Numerai user
    ///         Can only be called by Numerai
    ///         Calling this function multiple times will increment the stake
    /// @dev Calls withdraw() on the NMR token contract through the relay contract.
    ///      Can only be used on the first 1 million ethereum addresses.
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @param stakeAmount The amount of NMR in wei to stake with this submission
    /// @param confidence The confidence threshold to submit with this submission
    function stakeOnBehalf(
        uint256 tournamentID,
        uint256 roundID,
        address staker,
        bytes32 tag,
        uint256 stakeAmount,
        uint256 confidence
    ) public onlyManagerOrOwner whenNotPaused {
        _stake(tournamentID, roundID, staker, tag, stakeAmount, confidence);
        IRelay(_RELAY).withdraw(staker, address(this), stakeAmount);
    }

    /// @notice Transfer NMR on behalf of a Numerai user
    ///         Can only be called by Numerai
    /// @dev Calls the NMR token contract through the relay contract
    ///      Can only be used on the first 1 million ethereum addresses.
    /// @param from The user address
    /// @param to The recipient address
    /// @param value The amount of NMR in wei
    function withdraw(
        address from,
        address to,
        uint256 value
    ) public onlyManagerOrOwner whenNotPaused {
        IRelay(_RELAY).withdraw(from, to, value);
    }

    ////////////////////
    // User Functions //
    ////////////////////

    /// @notice Stake a round submission on your own behalf
    ///         Can be called by anyone
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param tag The UTF8 character string used to identify the submission
    /// @param stakeAmount The amount of NMR in wei to stake with this submission
    /// @param confidence The confidence threshold to submit with this submission
    function stake(
        uint256 tournamentID,
        uint256 roundID,
        bytes32 tag,
        uint256 stakeAmount,
        uint256 confidence
    ) public whenNotPaused {
        _stake(tournamentID, roundID, msg.sender, tag, stakeAmount, confidence);
        require(INMR(_TOKEN).transferFrom(msg.sender, address(this), stakeAmount),
            "Stake was not successfully transfered");
    }

    /////////////////////////////////////
    // Tournament Management Functions //
    /////////////////////////////////////

    /// @notice Resolve a staked submission after the round is completed
    ///         The portion of the stake which is not burned is returned to the user.
    ///         Can only be called by Numerai
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    /// @param burnAmount The amount of NMR in wei to burn from the stake
    function resolveStake(
        uint256 tournamentID,
        uint256 roundID,
        address staker,
        bytes32 tag,
        uint256 burnAmount
    )
    public
    onlyManagerOrOwner
    whenNotPaused
    onlyUint128(burnAmount)
    {
        Stake storage stakeObj = tournaments[tournamentID].rounds[roundID].stakes[staker][tag];
        uint128 originalStakeAmount = stakeObj.amount;
        if (burnAmount >= 0x100000000000000000000000000000000)
            burnAmount = originalStakeAmount;
        uint128 releaseAmount = uint128(originalStakeAmount.sub(burnAmount));

        assert(originalStakeAmount == releaseAmount + burnAmount);
        require(originalStakeAmount > 0, "The stake must exist");
        require(!stakeObj.resolved, "The stake must not already be resolved");
        require(
            uint256(
                tournaments[tournamentID].rounds[roundID].stakeDeadline
            ) < block.timestamp,
            "Cannot resolve before stake deadline"
        );

        stakeObj.amount = 0;
        stakeObj.burnAmount = uint128(burnAmount);
        stakeObj.resolved = true;

        require(
            INMR(_TOKEN).transfer(staker, releaseAmount),
            "Stake was not successfully released"
        );
        _burn(burnAmount);

        totalStaked = totalStaked.sub(originalStakeAmount);

        emit StakeResolved(tournamentID, roundID, staker, tag, originalStakeAmount, burnAmount);
    }

    /// @notice Initialize a new tournament
    ///         Can only be called by Numerai
    /// @param tournamentID The index of the tournament
    function createTournament(uint256 tournamentID) public onlyManagerOrOwner {

        Tournament storage tournament = tournaments[tournamentID];

        require(
            tournament.creationTime == 0,
            "Tournament must not already be initialized"
        );

        uint256 oldCreationTime;
        (oldCreationTime,) = getTournamentV1(tournamentID);
        require(
            oldCreationTime == 0,
            "This tournament must not be initialized in V1"
        );

        tournament.creationTime = block.timestamp;

        emit TournamentCreated(tournamentID);
    }

    /// @notice Initialize a new round
    ///         Can only be called by Numerai
    /// @dev The new roundID must be > the last roundID used on the previous tournament version
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param stakeDeadline The UNIX timestamp deadline for users to stake their submissions
    function createRound(
        uint256 tournamentID,
        uint256 roundID,
        uint256 stakeDeadline
    )
    public
    onlyManagerOrOwner
    onlyNewRounds(tournamentID, roundID)
    onlyUint128(stakeDeadline)
    {
        Tournament storage tournament = tournaments[tournamentID];
        Round storage round = tournament.rounds[roundID];

        require(tournament.creationTime > 0, "This tournament must be initialized");
        require(round.creationTime == 0, "This round must not be initialized");

        tournament.roundIDs.push(roundID);
        round.creationTime = uint128(block.timestamp);
        round.stakeDeadline = uint128(stakeDeadline);

        emit RoundCreated(tournamentID, roundID, stakeDeadline);
    }

    /// @notice Internal function to stake on Erasure agreement
    ///         Can only be called by Numerai
    ///         This function is intended as a bridge to allow for our custodied user accounts
    ///         (ie. the first million addresses), to stake in an Erasure agreement. Erasure
    ///         agreements assume an ERC-20 token, and the way we did custody doesn't quite fit
    ///         in the normal ERC-20 way of doing things. Ideally, we would be able to call
    ///         `changeApproval` on behalf of our custodied accounts, but that is unfortunately
    ///         not possible.
    ///         Instead what we have to do is `withdraw` the NMR into this contract and then call
    ///         `changeApproval` on this contract before calling `increaseStake` on the Erasure
    ///         agreement. The NMR is then taken from this contract to increase the stake.
    /// @param agreement The address of the agreement contract. Must conform to IErasureStake interface
    /// @param staker The address of the staker
    /// @param currentStake The amount of NMR in wei already staked on the agreement
    /// @param stakeAmount The amount of NMR in wei to incease the stake with this agreement
    function increaseStakeErasure(address agreement, address staker, uint256 currentStake, uint256 stakeAmount) public onlyManagerOrOwner {
        require(stakeAmount > 0, "Cannot stake zero NMR");

        uint256 oldBalance = INMR(_TOKEN).balanceOf(address(this));

        require(IRelay(_RELAY).withdraw(staker, address(this), stakeAmount), "Failed to withdraw");

        uint256 oldAllowance = INMR(_TOKEN).allowance(address(this), agreement);
        uint256 newAmount = oldAllowance.add(stakeAmount);
        require(INMR(_TOKEN).changeApproval(agreement, oldAllowance, newAmount), "Failed to approve");

        IErasureStake(agreement).increaseStake(currentStake, stakeAmount);

        uint256 newBalance = INMR(_TOKEN).balanceOf(address(this));
        require(oldBalance == newBalance, "Balance before/after did not match");

        emit IncreaseStakeErasure(agreement, staker, currentStake, stakeAmount);
    }

    //////////////////////
    // Getter Functions //
    //////////////////////

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

    /// @notice Get the address of the relay contract
    /// @return The address of the relay contract
    function relay() external pure returns (address) {
        return _RELAY;
    }

    /// @notice Get the address of the NMR token contract
    /// @return The address of the NMR token contract
    function token() external pure returns (address) {
        return _TOKEN;
    }

    ////////////////////////
    // Internal Functions //
    ////////////////////////

    /// @dev Internal function to handle stake logic
    ///      stakeAmount must fit in a uint128
    ///      confidence must fit in a uint32
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param tag The UTF8 character string used to identify the submission
    /// @param stakeAmount The amount of NMR in wei to stake with this submission
    /// @param confidence The confidence threshold to submit with this submission
    function _stake(
        uint256 tournamentID,
        uint256 roundID,
        address staker,
        bytes32 tag,
        uint256 stakeAmount,
        uint256 confidence
    ) internal onlyUint128(stakeAmount) {
        Tournament storage tournament = tournaments[tournamentID];
        Round storage round = tournament.rounds[roundID];
        Stake storage stakeObj = round.stakes[staker][tag];

        uint128 currentStake = stakeObj.amount;
        uint32 currentConfidence = stakeObj.confidence;

        require(tournament.creationTime > 0, "This tournament must be initialized");
        require(round.creationTime > 0, "This round must be initialized");
        require(
            uint256(round.stakeDeadline) > block.timestamp,
            "Cannot stake after stake deadline"
        );
        require(stakeAmount > 0 || currentStake > 0, "Cannot stake zero NMR");
        require(confidence <= 1000000000, "Confidence is capped at 9 decimal places");
        require(currentConfidence <= confidence, "Confidence can only be increased");

        stakeObj.amount = uint128(currentStake.add(stakeAmount));
        stakeObj.confidence = uint32(confidence);

        totalStaked = totalStaked.add(stakeAmount);

        emit Staked(tournamentID, roundID, staker, tag, stakeObj.amount, confidence);
    }

    /// @notice Internal helper function to burn NMR
    /// @dev If before the token upgrade, sends the tokens to address 0
    ///      If after the token upgrade, calls the repurposed mint function to burn
    /// @param _value The amount of NMR in wei
    function _burn(uint256 _value) internal {
        if (INMR(_TOKEN).contractUpgradable()) {
            require(INMR(_TOKEN).transfer(address(0), _value));
        } else {
            require(INMR(_TOKEN).mint(_value), "burn not successful");
        }
    }
}
