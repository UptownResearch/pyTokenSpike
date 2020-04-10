pragma solidity ^0.5.1;

import "./pytoken.sol";
import "./pyoracle.sol";

contract pyTokenFactory {

    uint256 public interestUpdateAmount;
    uint256 public collateralizationRatio;
    uint256 public liquidityTarget;
    uint256 public adjustmentFreeWindow;
    uint256 public debtRateLimit;
    uint256 public borrowFee;

    address public liquidationsContract; 

    mapping(address => mapping(address => address)) public getPyToken;

    event PyTokenDeployed(address indexed collateral, address indexed underlying, address pyToken);

    constructor ( 
            uint256 _interestUpdateAmount,
            uint256 _collateralizationRatio,
            uint256 _debtRateLimit,
            uint256 _liquidityTarget,
            uint256 _adjustmentFreeWindow,
            uint256 _borrowFee,
            address _liquidationsContract 
            ) public 
    {
        interestUpdateAmount = _interestUpdateAmount;
        collateralizationRatio = _collateralizationRatio;
        debtRateLimit = _debtRateLimit;
        liquidityTarget = _liquidityTarget;
        adjustmentFreeWindow = _adjustmentFreeWindow;
        borrowFee = _borrowFee;
        liquidationsContract = _liquidationsContract;
    }

    function createPyToken(address Token1, address Token2) public returns (address, address) {

        pyOracle oracle1 = new pyOracle(
            Token1, Token2
        );

        pyOracle oracle2 = new pyOracle(
            Token2, Token1
        );
        pyToken pytoken1 = new pyToken(
            Token2,
            Token1,
            address(oracle1),
            interestUpdateAmount,
            collateralizationRatio,
            debtRateLimit,
            liquidityTarget,
            adjustmentFreeWindow,
            borrowFee 
        );
        emit PyTokenDeployed(Token1, Token2, address(pytoken1));
        pyToken pytoken2 = new pyToken(
            Token1,
            Token2,
            address(oracle2),
            interestUpdateAmount,
            collateralizationRatio,
            debtRateLimit,
            liquidityTarget,
            adjustmentFreeWindow,
            borrowFee 
        );
        emit PyTokenDeployed(Token2, Token1, address(pytoken2));
        getPyToken[Token1][Token2] = address(pytoken1);
        getPyToken[Token2][Token1] = address(pytoken2);
        return(address(pytoken1), address(pytoken2));

    }

}