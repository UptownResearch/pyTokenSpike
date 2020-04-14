pragma solidity ^0.5.1;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";

/// @dev Test ERC20 asset contract. When live this will been deployed by a third party.
contract Underlying is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
    }
}
