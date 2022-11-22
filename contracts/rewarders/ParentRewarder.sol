// SPDX-License-Identifier: MIT

pragma solidity ^0.8.17;

import "./ChildRewarder.sol";
import "openzeppelin-contracts/contracts/utils/structs/EnumerableSet.sol";
import "openzeppelin-contracts/contracts/access/AccessControlEnumerable.sol";

/// Extension to the SingleAssetRewarder contract that allows managing multiple reward tokens via access control and
/// enumerable children contracts.
contract ParentRewarder is SingleAssetRewarder, AccessControlEnumerable {

    using EnumerableSet for EnumerableSet.AddressSet;

    EnumerableSet.AddressSet private childrenRewarders;

    bytes32 private constant REWARD_SETTER = keccak256("REWARD_SETTER");
    bytes32 private constant CHILD_SETTER = keccak256("CHILD_SETTER");

    event LogRewardMultiplier(uint rewardMultiplier);
    event ChildCreated(address indexed child, address indexed token);
    event ChildRemoved(address indexed child);

    /// @notice Contructor called on deployment of this contract
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _reliquary Address of Reliquary this rewarder will read state from
    constructor(
        uint _rewardMultiplier,
        IERC20 _rewardToken,
        IReliquary _reliquary
    ) SingleAssetRewarder(_rewardMultiplier, _rewardToken, _reliquary) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @notice Set the rewardMultiplier to a new value and emit a logging event.
    /// Separate role from who can add/remove children
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    function setRewardMultiplier(uint _rewardMultiplier) external onlyRole(REWARD_SETTER) {
        rewardMultiplier = _rewardMultiplier;
        emit LogRewardMultiplier(_rewardMultiplier);
    }

    /// @notice Deploys a ChildRewarder contract and adds it to the childrenRewarders set
    /// @param _rewardToken Address of token rewards are distributed in
    /// @param _rewardMultiplier Amount to multiply reward by, relative to BASIS_POINTS
    /// @param owner Address to transfer ownership of the ChildRewarder contract to
    /// @return Address of the new ChildRewarder
    function createChild(
        IERC20 _rewardToken,
        uint _rewardMultiplier,
        address owner
    ) external onlyRole(CHILD_SETTER) returns (address) {
        ChildRewarder child = new ChildRewarder(_rewardMultiplier, _rewardToken, reliquary);
        Ownable(address(child)).transferOwnership(owner);
        childrenRewarders.add(address(child));
        emit ChildCreated(address(child), address(_rewardToken));
        return address(child);
    }

    /// @notice Removes a ChildRewarder from the childrenRewarders set
    /// @param childRewarder Address of the ChildRewarder contract to remove
    function removeChild(address childRewarder) external onlyRole(CHILD_SETTER) {
        if(!childrenRewarders.remove(childRewarder))
            revert("That is not my child rewarder!");
        emit ChildRemoved(childRewarder);
    }

    /// @dev WARNING: This operation will copy the entire childrenRewarders storage to memory, which can be quite
    /// expensive. This is designed to mostly be used by view accessors that are queried without any gas fees.
    /// Developers should keep in mind that this function has an unbounded cost, and using it as part of a state-
    /// changing function may render the function uncallable if the set grows to a point where copying to memory
    /// consumes too much gas to fit in a block.
    function getChildrenRewarders() external view returns (address[] memory) {
        return childrenRewarders.values();
    }

    /// @notice Called by Reliquary harvest or withdrawAndHarvest function
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    /// @param to Address to send rewards to
    function onReward(
        uint relicId,
        uint rewardAmount,
        address to
    ) external override onlyReliquary {
        super._onReward(relicId, rewardAmount, to);

        uint length = childrenRewarders.length();
        for(uint i; i < length;) {
            IRewarder(childrenRewarders.at(i)).onReward(relicId, rewardAmount, to);
            unchecked {++i;}
        }
    }

    /// @notice Returns the amount of pending tokens for a position from this rewarder
    /// @param rewardAmount Amount of reward token owed for this position from the Reliquary
    function pendingTokens(
        uint relicId,
        uint rewardAmount
    ) external view override returns (IERC20[] memory rewardTokens, uint[] memory rewardAmounts) {
        uint length = childrenRewarders.length() + 1;
        rewardTokens = new IERC20[](length);
        rewardTokens[0] = rewardToken;

        rewardAmounts = new uint[](length);
        rewardAmounts[0] = pendingToken(relicId, rewardAmount);

        for (uint i = 1; i < length;) {
            ChildRewarder rewarder = ChildRewarder(childrenRewarders.at(i - 1));
            rewardTokens[i] = rewarder.rewardToken();
            rewardAmounts[i] = rewarder.pendingToken(relicId, rewardAmount);
            unchecked {++i;}
        }
    }
}
