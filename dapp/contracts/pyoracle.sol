pragma solidity ^0.5.1;



contract pyOracle {

    address public underlying;
    address public collateral;
    constructor ( 
            address _underlying,
            address _collateral
    ) public {
        underlying = _underlying;
        collateral = _collateral;
    }



}