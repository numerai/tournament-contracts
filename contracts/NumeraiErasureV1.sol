pragma solidity >=0.5.0 <0.6.0;

import "./Pausable.sol";
import "./interfaces/IRelay.sol";
import "./interfaces/INMR.sol";
import "./interfaces/IErasureStake.sol";
import "./helpers/zos-lib/Initializable.sol";
import "./helpers/openzeppelin-solidity/math/SafeMath.sol";
import "./erasure/modules/iFactory.sol";

contract NumeraiErasureV1 is Initializable, Pausable {
    using SafeMath for uint256;
    using SafeMath for uint128;

    event CreateStake(
        address indexed agreement,
        address indexed staker,
        uint256 amount
    );

    event IncreaseStake(
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

    /// @notice Initializer function called at time of deployment
    /// @param _owner The address of the wallet to handle permission control
    function initialize(
        address _owner
    ) public initializer {
        // initialize the contract's ownership.
        Pausable.initialize(_owner);
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
    function increaseStake(
        address agreement, address staker, uint256 currentStake, uint256 stakeAmount
    ) public onlyManagerOrOwner whenNotPaused {
        require(stakeAmount > 0, "Cannot stake zero NMR");

        uint256 oldBalance = INMR(_TOKEN).balanceOf(address(this));

        require(IRelay(_RELAY).withdraw(staker, address(this), stakeAmount), "Failed to withdraw");

        uint256 oldAllowance = INMR(_TOKEN).allowance(address(this), agreement);
        uint256 newAmount = oldAllowance.add(stakeAmount);
        require(INMR(_TOKEN).changeApproval(agreement, oldAllowance, newAmount), "Failed to approve");

        IErasureStake(agreement).increaseStake(currentStake, stakeAmount);

        uint256 newBalance = INMR(_TOKEN).balanceOf(address(this));
        require(oldBalance == newBalance, "Balance before/after did not match");

        emit IncreaseStake(agreement, staker, currentStake, stakeAmount);
    }

    /// @notice Internal function to create a an Erasure agreement stake
    /// @param factory The address of the agreement factory. Must conform to iFactory interface
    /// @param agreement The address of the agreement contract that will be created. Get this value by running factory.getSaltyInstance(...)
    /// @param staker The address of the staker
    /// @param stakeAmount The amount of NMR in wei to incease the stake with this agreement
    /// @param callData The callData used to create the agreement
    /// @param salt The salt used to create the agreement
    function createStake(
        address factory, address agreement, address staker, uint256 stakeAmount, bytes memory callData, bytes32 salt
    ) public onlyManagerOrOwner whenNotPaused {
        require(stakeAmount > 0, "Cannot stake zero NMR");

        require(iFactory(factory).createSalty(callData, salt) == agreement, "Unexpected agreement address");

        increaseStake(agreement, staker, 0, stakeAmount);

        emit CreateStake(agreement, staker, stakeAmount);
    }
}
