pragma solidity ^0.5.1;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@hq20/contracts/contracts/math/DecimalMath.sol";
import "@nomiclabs/buidler/console.sol";
import "./pytokenFactory.sol";
import "./pyoracle.sol";
import "./IOracle.sol";

/// @dev Perpetual Yield Token for an ERC20 token pair.
contract pyToken is ERC20 {
    using DecimalMath for uint256;
    using DecimalMath for uint8;

    // definitions
    uint8 short = 18; // Used for currency amounts
    uint256 shortUnit = 1000000000000000000;
    uint8 long = 27; // Used for mathematical variables
    uint256 longUnit = 1000000000000000000000000000;

    // Token information
    string public name = "pyToken";
    string public symbol = "pY";
    // uint8 public decimals = 18; // There should be no issue using decimals

    // Associated contracts
    address public underlying;
    address public collateral;
    address public oracle;
    address public pairPyToken; // pyTokens are deployed in pairs: ETH-DAI and DAI-ETH, for example.
    address private _creator; // Let's use Ownable.

    // interest parameters - All are short
    uint256 public interestUpdateAmount;
    uint256 public collateralizationRatio;
    uint256 public liquidityTarget;
    uint256 public adjustmentFreeWindow;
    uint256 public debtRateLimit;
    uint256 public borrowFee;

    // Interest Rate variables - are these all long_unit?
    uint256 public rateAccumulator; //long
    uint256 public debtAccumulator; //long
    uint256 public debtRate; //short
    uint256 public normalizedDebt; //short

    uint256 public totalFeeIncome; // currency amount? yes, currency amounts are short
    uint256 public lastBlockInterest; // long - actually, i think this is short
    uint256 public lastBlockInterestPeriods; // integer number (not fixed point)
    uint256 public lastUpdate; // timestamp
    uint256 public lastRateUpdate; // timestamp

    // value held in contract
    uint256 public underlyingHeld; // currency amount

    //repos
    /// @dev Repurchase Agreement. userCollateral is transferred in exchange for lockedCollateral.
    /// The transfer can be undone afterwards but the userCollateral returned is interest discounted.
    struct Repo {
        uint256 userCollateral;
        uint256 lockedCollateral;
        uint256 normalizedDebt;
        bool lockedForLiquidation;
    }

    /// @dev User assets can be locked for liquidation, the proceedings from their forced sale used to pay outstanding debts.
    struct Liquidation {
        bool lockedForLiquidation;
        address lockedBy;
    }

    mapping(address => Repo) public repos; // Each user can have only one repo
    mapping(address => Liquidation) public liquidations; // All of an user's assets enter into liquidation.

    //Oracle
    uint256 constant ONE_HOUR = 60*60;
    uint256 startBorrowTime;
    uint256 startUnlockTime;

    constructor (
        address _underlying,
        address _collateral,
        address _oracle,
        uint256 _interestUpdateAmount,
        uint256 _collateralizationRatio,
        uint256 _debtRateLimit,
        uint256 _liquidityTarget,
        uint256 _adjustmentFreeWindow,
        uint256 _borrowFee
    ) public {
        underlying = _underlying;
        collateral = _collateral;
        oracle = _oracle;
        interestUpdateAmount = _interestUpdateAmount;
        collateralizationRatio = _collateralizationRatio;
        debtRateLimit = _debtRateLimit;
        liquidityTarget = _liquidityTarget;
        adjustmentFreeWindow = _adjustmentFreeWindow;
        borrowFee = _borrowFee;

        totalFeeIncome = 0;
        rateAccumulator = longUnit;
        debtAccumulator = longUnit;
        lastBlockInterest = longUnit;
        lastUpdate = now;
        lastRateUpdate = now;
        debtRate = longUnit;

        _creator = msg.sender;
    }

    /// @dev Set the address for the reverse pyToken contract
    function setPairPyToken(address _pyToken) public {
        require(msg.sender == _creator, "setPairPyToken/only-callable-by-factory");
        pairPyToken = _pyToken;
    }

    // Math functions
    /// @dev Compounds interest for a number of periods using the binomial approximation
    function compoundInterestRate(uint rate, uint periods, uint unit) public returns(uint256) {
        return unit + (rate * periods);
    }

    // Transfer functions
    function transferUnderlying(address sender, address recipient, uint256 amount) public {
    }

    // view functions - all return currency amounts.
    function totalSupplyUnderlying() public view returns (uint256) {
        // muld(a, b, long): Multiply a by b, assuming b is long. The result is the same format as a.
        return totalSupply().muld(rateAccumulator, long);
    }

    function balanceOfUnderlying(address account) public view returns (uint){
        return balanceOf(account).muld(rateAccumulator, long);
    }

    function getTotalDebt() public view returns (uint256) {
        return normalizedDebt.muld(debtAccumulator, long);
    }

    function debtInUnderlying(address usr) public view returns (uint256){
        return repos[usr].normalizedDebt.muld(debtAccumulator, long);
    }

    function getCollateralBalance(address user) public view returns (uint256){
        return repos[user].userCollateral;
    }

    function getReserveRatio() public view returns (uint256) {
        if (underlyingHeld <= 0){
            return 0;
        }
        // divd(a, b, short): Divide a by b, assuming b is short. The result is the same format as a.
        return underlyingHeld.divd(getTotalDebt() + underlyingHeld, short); // Should we convert to long for precision?
    }

    // pyToken creation and redemption
    /// @dev Take underlying tokens from user, and mint pyTokens in exchange.
    function mint(uint256 amount) public returns (bool) {
        //accrueInterest();
        //updateRates();
        require(ERC20(underlying).transferFrom(msg.sender, address(this), amount), "mint/failed-transfer");
        uint256 normalizedAmount = amount.divd(rateAccumulator, long);
        _mint(msg.sender, normalizedAmount);
        underlyingHeld += amount;
        return true;
    }

    /// @dev Burn pyTokens from user, and return underlying tokens in exchange.
    function redeem(uint256 amount) public returns (bool) {
        //accrueInterest();
        //updateRates();
        require(amount >= 0, "redeem/cannot-redeem-negative amount");
        require(underlyingHeld >= amount, "redeem/cannot-redeem-more-than-reserves");
        require(balanceOfUnderlying(msg.sender) >= amount, "redeem/amount-exceeds-funds");
        uint256 normalizedAmount = amount.divd(rateAccumulator, long);
        _burn(msg.sender, normalizedAmount);
        require(ERC20(underlying).transfer(msg.sender, amount), "redeem/failed-transfer");
        underlyingHeld -= amount;
    }

    /// @dev Update the accrued interest and related variables, according to the number of seconds since the previous update.
    function accrueInterest() public {
        if (lastUpdate >= now || totalSupply() == 0) return;
        uint256 periods = now - lastUpdate;
        uint256 accumulatedDebtInterestMultiplier = compoundInterestRate(debtRate - longUnit, periods, longUnit);
        debtAccumulator = accumulatedDebtInterestMultiplier.muld(debtAccumulator, long);
        uint256 allDebt = normalizedDebt.muld(debtAccumulator, short);
        uint256 newDebt = (accumulatedDebtInterestMultiplier - longUnit)
            .muld(allDebt, long);
        uint256 feeIncome = newDebt.muld(borrowFee, short);
        totalFeeIncome += feeIncome;
        uint256 totalPyTokens = totalSupply().muld(rateAccumulator, short);
        rateAccumulator = ((newDebt - feeIncome) + totalPyTokens)
            .divd(totalSupply()
            .muld(longUnit, short), long);
        lastBlockInterest = ((newDebt - feeIncome) + totalPyTokens)
            .divd(totalPyTokens, long);
        lastBlockInterestPeriods = periods;
        lastUpdate = now;
    }

    /// @dev Update the rate at which interest is accrued
    function updateRates() public {
        if (lastRateUpdate >= now || totalSupply() == 0) return;
        uint256 imbalance = getReserveRatio();
        int256 updateRate;
        if (imbalance > liquidityTarget)            updateRate = -int(interestUpdateAmount);
        else if (imbalance < liquidityTarget) updateRate = int(interestUpdateAmount);
        else updateRate = 0;
        console.logInt(updateRate);
        debtRate = debtRate.muld(uint256(int(longUnit) + updateRate), long);
        if (debtRate < longUnit) debtRate = longUnit;     // debtRate must not go below 1.0
        if (debtRate > debtRateLimit) debtRate = debtRateLimit;
        if (normalizedDebt == 0) debtRate = longUnit;
        lastRateUpdate = now;
    }

    /// @dev Allow user to store collateral in the pyToken contract
    function addCollateral(address user, uint256 amount) public {
        //accrueInterest();
        //updateRates();
        require(int(amount) >= 0, "addCollateral/overflow");
        require(
            ERC20(collateral).transferFrom(msg.sender, address(this), amount),
            "addCollateral/failed-transfer"
        );
        repos[user].userCollateral += amount;
    }

    /// @dev Allow user to withdraw collateral from the pyToken contract
    function withdrawCollateral(address user, uint256 amount) public {
        //accrueInterest();
        //updateRates();
        require(amount <= 2 ** 255, "withdrawCollateral/overflow");
        repos[msg.sender].userCollateral -= amount;
        require(
            ERC20(collateral).transferFrom(address(this), msg.sender, amount),
            "withdrawCollateral/failed-transfer"
        );
    }

    /**  Likely won't use this approach -- marking for future removal
    /// @dev Borrow by pointing to a valid repo with a lower liquidation price
    function borrowCompare(
        address comparisonRepo,
        address usr,
        uint256 amountToBorrow,
        uint256 collateralToLock
    ) public {
        require(
            repos[comparisonRepo].lockedForLiquidation == false,
            "borrowCompare/comparisonRepo-is-locked-for-liquidation"
        );
        require(
            repos[msg.sender].userCollateral >= collateralToLock,
            "borrowCompare/collateralToLock-is-greater-than-userCollateral"
        );
        // how are we handling collateral decimals?
        uint256 availableCollateral = repos[msg.sender].lockedCollateral + collateralToLock;
        uint256 finalDebt = repos[msg.sender].normalizedDebt.muld(debtAccumulator, long) + amountToBorrow;
        uint256 usrRatio = finalDebt/availableCollateral;
        uint256 compRatio = repos[comparisonRepo].normalizedDebt.muld(debtAccumulator, long) /
            repos[comparisonRepo].lockedCollateral;
        require(usrRatio < compRatio, "borrowCompare/comparison-to-comparison-repo-not-successful");
        repos[msg.sender].normalizedDebt = repos[msg.sender].normalizedDebt + amountToBorrow/debtAccumulator;
        repos[msg.sender].lockedCollateral += collateralToLock;
        repos[msg.sender].userCollateral -= collateralToLock;
        uint256 normalizedAmount = amountToBorrow.divd(rateAccumulator, long);
        _mint(msg.sender, normalizedAmount);
        normalizedDebt += normalizedAmount;
    }
    */

    // This approach is out of date.
    /// @dev Why is borrowing forbidden for an hour after updating prices?
    function startBorrow() public { // If access is not restricted, this will be open to DoS attacks.
        IOracle(oracle).startTWAP();
        startBorrowTime = now;
    }

    /// @dev Setup or update a Repurchase Agreement
    function completeBorrow(address usr, uint256 amountToBorrow, uint256 collateralToLock) public {
        uint256 twapPrice = IOracle(oracle).endTWAP();
        require(
            now - startBorrowTime > ONE_HOUR,
            "completeBorrow/must-wait-an-hour-before-calling-completeBorrow"
        );
        require(
            repos[msg.sender].userCollateral >= collateralToLock,
            "completeBorrow/collateralToLock-is-greater-than-userCollateral"
        );
        // how are we handling collateral decimals?
        uint256 availableCollateral = repos[msg.sender].lockedCollateral + collateralToLock;
        uint256 finalDebt = repos[msg.sender].normalizedDebt.muld(debtAccumulator, long) + amountToBorrow;
        uint256 collateralNeeded = finalDebt * collateralizationRatio / twapPrice;
        require(collateralNeeded <= availableCollateral, "completeBorrow/insufficient-collateral-for-new-debt");
        repos[msg.sender].normalizedDebt = repos[msg.sender].normalizedDebt +
            (amountToBorrow * longUnit)/debtAccumulator;
        repos[msg.sender].lockedCollateral += collateralToLock;
        repos[msg.sender].userCollateral -= collateralToLock;
        uint256 normalizedAmount = amountToBorrow.divd(rateAccumulator, long);
        _mint(msg.sender, normalizedAmount);
        normalizedDebt += normalizedAmount;
    }

    /// @dev Cancel part or all of a repo debt by burning pyTokens
    function repay(address usr, uint256 amountToPayback) public {
        uint256 normalizedPayback = amountToPayback.divd(rateAccumulator, long);
        require(
            balanceOf(msg.sender) >= normalizedPayback,
            "repay/insufficient-funds-to-repay"
        );
        _burn(msg.sender, normalizedPayback);
        uint256 debtCancelled = amountToPayback.divd(debtAccumulator, long);
        require(
            repos[usr].normalizedDebt >= debtCancelled,
            "repay/cannot-repay-more-than-debt"
        );
        repos[usr].normalizedDebt -= debtCancelled;
    }

    /// @dev Unlocking collateral to use in a repo needs the underlying asset prices.
    function startUnlock() public {
        IOracle(oracle).startTWAP();
        startUnlockTime = now;
    }

    /// @dev Unlock collateral to use in a repo.
    function completeUnlock(uint256 collateralToUnLock) public {
        uint256 twapPrice = IOracle(oracle).endTWAP();
        require(
            now - startUnlockTime > ONE_HOUR, // I think we mean startUnlockTime
            "completeUnlock/must-wait-an-hour-before-calling-completeUnlock"
        );
        uint256 availableCollateral = repos[msg.sender].lockedCollateral - collateralToUnLock;
        uint256 finalDebt = repos[msg.sender].normalizedDebt.muld(debtAccumulator, long);
        uint256 collateralNeeded = finalDebt * collateralizationRatio / twapPrice;
        require(availableCollateral >= collateralNeeded, "completeUnlock/insufficient-collateral-to-complete-unlock");
        repos[msg.sender].lockedCollateral -= collateralToUnLock;
        repos[msg.sender].userCollateral += collateralToUnLock;
    }
}
