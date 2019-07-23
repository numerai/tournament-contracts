pragma solidity >=0.5.0 <0.6.0;

interface IRelay {

    /// @notice Transfer NMR on behalf of a Numerai user
    ///         Can only be called by Manager or Owner
    /// @dev Can only be used on the first 1 million ethereum addresses
    /// @param _from The user address
    /// @param _to The recipient address
    /// @param _value The amount of NMR in wei
    function withdraw(address _from, address _to, uint256 _value) external returns (bool ok);

    /// @notice Burn the NMR sent to address 0 and burn address
    function burnZeroAddress() external;

    /// @notice Permanantly disable the relay contract
    ///         Can only be called by Owner
    function disable() external;

    /// @notice Permanantly disable token upgradability
    ///         Can only be called by Owner
    function disableTokenUpgradability() external;

    /// @notice Upgrade the token delegate logic.
    ///         Can only be called by Owner
    /// @param _newDelegate Address of the new delegate contract
    function changeTokenDelegate(address _newDelegate) external;

    /// @notice Upgrade the token delegate logic using the UpgradeDelegate
    ///         Can only be called by Owner
    /// @dev must be called after UpgradeDelegate is set as the token delegate
    /// @param _multisig Address of the multisig wallet address to receive NMR and ETH
    /// @param _delegateV3 Address of NumeraireDelegateV3
    function executeUpgradeDelegate(address _multisig, address _delegateV3) external;

    /// @notice Burn stakes during initialization phase
    ///         Can only be called by Manager or Owner
    /// @dev must be called after UpgradeDelegate is set as the token delegate
    /// @param tournamentID The index of the tournament
    /// @param roundID The index of the tournament round
    /// @param staker The address of the user
    /// @param tag The UTF8 character string used to identify the submission
    function destroyStake(uint256 tournamentID, uint256 roundID, address staker, bytes32 tag) external;

}
