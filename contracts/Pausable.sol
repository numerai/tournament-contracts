pragma solidity >=0.5.0 <0.6.0;

import "./Manageable.sol";
import "./helpers/zos-lib/Initializable.sol";

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 *      Modified from openzeppelin Pausable to simplify access control.
 */
contract Pausable is Initializable, Manageable {
    event Paused(address account);
    event Unpaused(address account);

    bool private _paused;

    /// @notice Initializer function called at time of deployment
    /// @param sender The address of the wallet to handle permission control
    function initialize(address sender) public initializer {
        Manageable.initialize(sender);
        _paused = false;
    }

    /**
     * @return true if the contract is paused, false otherwise.
     */
    function paused() public view returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     */
    modifier whenNotPaused() {
        require(!_paused);
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     */
    modifier whenPaused() {
        require(_paused);
        _;
    }

    /**
     * @dev called by the owner to pause, triggers stopped state
     */
    function pause() public onlyManagerOrOwner whenNotPaused {
        _paused = true;
        emit Paused(msg.sender);
    }

    /**
     * @dev called by the owner to unpause, returns to normal state
     */
    function unpause() public onlyOwner whenPaused {
        _paused = false;
        emit Unpaused(msg.sender);
    }

    uint256[50] private ______gap;
}
