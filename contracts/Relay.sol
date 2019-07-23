pragma solidity >=0.5.0 <0.6.0;

import "./Manageable.sol";
import "./interfaces/INMR.sol";

contract Relay is Manageable {

    bool public active = true;
    bool private _upgraded;

    // set NMR token, 1M address, null address, burn address as constants
    address private constant _TOKEN = address(
        0x1776e1F26f98b1A5dF9cD347953a26dd3Cb46671
    );
    address private constant _ONE_MILLION_ADDRESS = address(
        0x00000000000000000000000000000000000F4240
    );
    address private constant _NULL_ADDRESS = address(
        0x0000000000000000000000000000000000000000
    );
    address private constant _BURN_ADDRESS = address(
        0x000000000000000000000000000000000000dEaD
    );

    /// @dev Throws if the address does not match the required conditions.
    modifier isUser(address _user) {
        require(
            _user <= _ONE_MILLION_ADDRESS
            && _user != _NULL_ADDRESS
            && _user != _BURN_ADDRESS
            , "_from must be a user account managed by Numerai"
        );
        _;
    }

    /// @dev Throws if called after the relay is disabled.
    modifier onlyActive() {
        require(active, "User account relay has been disabled");
        _;
    }

    /// @notice Contructor function called at time of deployment
    /// @param _owner The initial owner and manager of the relay
    constructor(address _owner) public {
        require(
            address(this) == address(0xB17dF4a656505570aD994D023F632D48De04eDF2),
            "incorrect deployment address - check submitting account & nonce."
        );

        Manageable.initialize(_owner);
    }

    /// @notice Transfer NMR on behalf of a Numerai user
    ///         Can only be called by Manager or Owner
    /// @dev Can only be used on the first 1 million ethereum addresses
    /// @param _from The user address
    /// @param _to The recipient address
    /// @param _value The amount of NMR in wei
    function withdraw(address _from, address _to, uint256 _value) public onlyManagerOrOwner onlyActive isUser(_from) returns (bool ok) {
        require(INMR(_TOKEN).withdraw(_from, _to, _value));
        return true;
    }

    /// @notice Burn the NMR sent to address 0 and burn address
    function burnZeroAddress() public {
        uint256 amtZero = INMR(_TOKEN).balanceOf(_NULL_ADDRESS);
        uint256 amtBurn = INMR(_TOKEN).balanceOf(_BURN_ADDRESS);
        require(INMR(_TOKEN).withdraw(_NULL_ADDRESS, address(this), amtZero));
        require(INMR(_TOKEN).withdraw(_BURN_ADDRESS, address(this), amtBurn));
        uint256 amtThis = INMR(_TOKEN).balanceOf(address(this));
        _burn(amtThis);
    }

    /// @notice Permanantly disable the relay contract
    ///         Can only be called by Owner
    function disable() public onlyOwner onlyActive {
        active = false;
    }

    /// @notice Permanantly disable token upgradability
    ///         Can only be called by Owner
    function disableTokenUpgradability() public onlyOwner onlyActive {
        require(INMR(_TOKEN).createRound(uint256(0),uint256(0),uint256(0),uint256(0)));
    }

    /// @notice Upgrade the token delegate logic.
    ///         Can only be called by Owner
    /// @param _newDelegate Address of the new delegate contract
    function changeTokenDelegate(address _newDelegate) public onlyOwner onlyActive {
        require(INMR(_TOKEN).createTournament(uint256(_newDelegate)));
    }

    /// @notice Get the address of the NMR token contract
    /// @return The address of the NMR token contract
    function token() external pure returns (address) {
        return _TOKEN;
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
