pragma solidity ^0.5.1;


/// @dev Oracles return the price of an asset. This is a mock version.
contract Oracle {
    uint256 public price;

    function updatePrice(uint256 newPrice) public{
        price = newPrice;
    }

    function startTWAP() public {}

    function endTWAP() public returns (uint256) {
        return price;
    }
}