pragma solidity ^0.5.1;


/// @dev Oracles return the price of an asset.
interface IOracle {
    function updatePrice(uint256 newPrice) external;

    function startTWAP() external;

    function endTWAP() external returns (uint256);
}