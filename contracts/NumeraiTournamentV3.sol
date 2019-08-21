pragma solidity >=0.5.0 <0.6.0;

import "./Pausable.sol";
import "./interfaces/IRelay.sol";
import "./interfaces/INMR.sol";
import "./helpers/zos-lib/Initializable.sol";
import "./erasure/agreements/OneWayGriefingNoCountdown.sol";


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
        // left for compatibility purposes. don't double-store because we are storing stake amount on agreement
        uint128 amount; 
        uint32 confidence;
        uint128 burnAmount;
        bool resolved;
        address agreement;
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

    /// @notice constructor function, used to enforce implementation address
    constructor() public {
        require(
            address(this) == address(0x9959666590F01cA989E21175179Df9D2141B2819),
            "incorrect deployment address - check submitting account & nonce."
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
    /// @param callData ABI-encoded byte string of parameters
    function batchStakeOnBehalf(bytes calldata callData) external {
        (
            uint256[] memory tournamentID,
            uint256[] memory roundID,
            address[] memory staker,
            bytes32[] memory tag,
            uint256[] memory stakeAmount,
            uint256[] memory confidence,
            address[] memory agreement
        ) = abi.decode(callData, (uint256[], uint256[], address[], bytes32[], uint256[], uint256[], address[]));

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
            stakeOnBehalf(tournamentID[i], roundID[i], staker[i], tag[i], stakeAmount[i], confidence[i], agreement[i]);
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
        uint256 confidence,
        address agreement
    ) public onlyManagerOrOwner whenNotPaused {
        _stake(tournamentID, roundID, staker, tag, stakeAmount, confidence, agreement);
        IRelay(_RELAY).withdraw(staker, address(this), stakeAmount);
    }

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
        uint256 confidence,
        address agreement
    ) public whenNotPaused {
        _stake(tournamentID, roundID, msg.sender, tag, stakeAmount, confidence, agreement);
        require(INMR(_TOKEN).transferFrom(msg.sender, address(this), stakeAmount),
            "Stake was not successfully transfered");
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

        address agreementAddress = stakeObj.agreement;
        OneWayGriefingNoCountdown agreement = OneWayGriefingNoCountdown(agreementAddress);

        // TO FIX
        // possible downcast since we're storing as uint256 in agreement
        uint128 originalStakeAmount = uint128(agreement.getStake(staker));

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

        stakeObj.amount = 0; // just reset to 0, even though amount is not updated
        stakeObj.burnAmount = uint128(burnAmount);
        stakeObj.resolved = true;

        // punish then release the remaining stake amount to the staker
        require(_punishErasure(agreementAddress, burnAmount), "punish on agreement contract failed");

        require(_releaseStakeErasure(agreementAddress), "releaseStake on agreement contract failed");

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

    /// @notice Reward an agreement
    /// @dev Calls agreement.reward
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    function rewardAgreement(
        uint256 tournamentID,
        uint256 roundID,
        address staker,
        bytes32 tag,
        uint256 rewardAmount
    )
    public
    onlyManagerOrOwner
    {
        Stake storage stakeObj = tournaments[tournamentID].rounds[roundID].stakes[staker][tag];

        OneWayGriefingNoCountdown agreement = OneWayGriefingNoCountdown(stakeObj.agreement);

        uint256 currentStake = agreement.getStake(staker);
        
        agreement.reward(currentStake, rewardAmount);
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
        uint256 confidence,
        address agreement
    ) internal onlyUint128(stakeAmount) {
        Tournament storage tournament = tournaments[tournamentID];
        Round storage round = tournament.rounds[roundID];
        Stake storage stakeObj = round.stakes[staker][tag];
        uint32 currentConfidence = stakeObj.confidence;

        require(tournament.creationTime > 0, "This tournament must be initialized");
        require(round.creationTime > 0, "This round must be initialized");
        require(
            uint256(round.stakeDeadline) > block.timestamp,
            "Cannot stake after stake deadline"
        );
        require(confidence <= 1000000000, "Confidence is capped at 9 decimal places");
        require(currentConfidence <= confidence, "Confidence can only be increased");

        stakeObj.confidence = uint32(confidence);
        stakeObj.agreement = agreement;
        require(_increaseStakeErasure(agreement, staker, stakeAmount), "increaseStake in agreement contract failed");

        emit Staked(tournamentID, roundID, staker, tag, stakeObj.amount, confidence);
    }

    /// @notice Internal function to stake on Erasure agreement
    /// @param agreement The address of the agreement contract
    /// @param staker The address of the staker
    /// @param stakeAmount The amount of NMR in wei to stake with this submission
    function _increaseStakeErasure(address agreement, address staker, uint256 stakeAmount) internal returns (bool) {
        OneWayGriefingNoCountdown griefingAgreement = OneWayGriefingNoCountdown(agreement);
        uint256 currentStake = griefingAgreement.getStake(staker);

        require(stakeAmount > 0 || currentStake > 0, "Cannot stake zero NMR");
        griefingAgreement.increaseStake(currentStake, stakeAmount);
        return true;
    }

    /// @notice Internal function to punish the staker in the agreement contract
    /// @param agreement The address of the agreement contract
    /// @param punishment The amount of punishment the staker will receive
    function _punishErasure(address agreement, uint256 punishment) internal returns (bool) {
        OneWayGriefingNoCountdown(agreement).punish(address(this), punishment, "");
        return true;
    }

    function _releaseStakeErasure(address agreement) internal returns (bool) {
        OneWayGriefingNoCountdown(agreement).releaseStake();
        return true;
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
