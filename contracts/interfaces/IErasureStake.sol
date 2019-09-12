pragma solidity >=0.5.0 <0.6.0;

interface IErasureStake {
    /// @notice Increase a stake
    /// @param currentStake The current stake amount
    /// @param amountToAdd The amount of stake to add
    function increaseStake(uint256 currentStake, uint256 amountToAdd) external;
}
