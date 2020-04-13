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

    event PyTokenDeployed(
        address indexed collateral,
        address indexed underlying,
        address pyToken
    );

    /// @dev Set variables common for all pyTokens deployed through this factory.
    constructor (
        uint256 _interestUpdateAmount,
        uint256 _collateralizationRatio,
        uint256 _debtRateLimit,
        uint256 _liquidityTarget,
        uint256 _adjustmentFreeWindow,
        uint256 _borrowFee,
        address _liquidationsContract
    ) public {
        interestUpdateAmount = _interestUpdateAmount;
        collateralizationRatio = _collateralizationRatio;
        debtRateLimit = _debtRateLimit;
        liquidityTarget = _liquidityTarget;
        adjustmentFreeWindow = _adjustmentFreeWindow;
        borrowFee = _borrowFee;
        liquidationsContract = _liquidationsContract;
    }

    /// @dev Create a pyToken contract for two target tokens, and its reverse pyToken contract.
    function createPyToken(address token1, address token2)
        public returns (address, address) {

        pyOracle oracle1 = new pyOracle(
            token1, token2
        );
        pyOracle oracle2 = new pyOracle(
            token2, token1
        );
        pyToken pytoken1 = new pyToken(
            token2,
            token1,
            address(oracle1),
            interestUpdateAmount,
            collateralizationRatio,
            debtRateLimit,
            liquidityTarget,
            adjustmentFreeWindow,
            borrowFee
        );
        emit PyTokenDeployed(token1, token2, address(pytoken1));
        pyToken pytoken2 = new pyToken(
            token1,
            token2,
            address(oracle2),
            interestUpdateAmount,
            collateralizationRatio,
            debtRateLimit,
            liquidityTarget,
            adjustmentFreeWindow,
            borrowFee
        );
        emit PyTokenDeployed(token2, token1, address(pytoken2));
        getPyToken[token1][token2] = address(pytoken1);
        getPyToken[token2][token1] = address(pytoken2);
        return(address(pytoken1), address(pytoken2));
    }
}