pragma solidity ^0.5.1;

import "./pytoken.sol";


contract pyTokenFactory {


    mapping(address => mapping(address => address)) public getPair;

    function createPyToken(address Token1, address Token2) public returns (address, address) {


    }

}