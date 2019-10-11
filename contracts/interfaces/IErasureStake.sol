pragma solidity >=0.5.0 <0.6.0;

interface IErasureStake {
    function increaseStake(uint256 currentStake, uint256 amountToAdd) external;
    function reward(uint256 currentStake, uint256 amountToAdd) external;
    function punish(uint256 currentStake, uint256 punishment, bytes calldata message) external returns (uint256 cost);
    function releaseStake(uint256 currentStake, uint256 amountToRelease) external;
}
