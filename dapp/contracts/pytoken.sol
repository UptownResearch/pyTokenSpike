pragma solidity ^0.5.1;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";
import "./pytokenFactory.sol";
import "./pyoracle.sol";


contract Collateral is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
    }
}


contract Underlying is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
    }
}


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


contract pyToken is ERC20 {
    // definitions
    uint short = 10**18;
    uint long = 10**27;

    // Token information
    string public name = "pyToken";
    string public symbol = "pY";
    // uint8 public decimals = 18;

    // Associated contracts
    address public underlying;
    address public collateral;
    address public oracle;
    address public pairPyToken;
    address private _creator;

    // interest parameters
    uint256 public interestUpdateAmount;
    uint256 public collateralizationRatio;
    uint256 public liquidityTarget;
    uint256 public adjustmentFreeWindow;
    uint256 public debtRateLimit;
    uint256 public borrowFee;

    // Interest Rate variables
    uint256 public rateAccumulator;
    uint256 public debtAccumulator;
    uint256 public debtRate;
    uint256 public normalizedDebt;
    uint256 public bonus;

    uint256 public totalFeeIncome;
    uint256 public lastBlockInterest;
    uint256 public lastBlockInterestPeriods;
    uint256 public lastUpdate;
    uint256 public lastRateUpdate;

    // value held in contract
    uint256 public underlyingHeld;

    //repos
    struct Repo {
        uint256 userCollateral;
        uint256 lockedCollateral;
        uint256 normalizedDebt;
        bool lockedForLiquidation;
    }

    struct Liquidation {
        bool lockedForLiquidation;
        address lockedBy;
    }

    mapping(address => Repo) public repos;
    mapping(address => Liquidation) public liquidations;

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
        rateAccumulator = long;
        debtAccumulator = long;
        lastBlockInterest = long;
        lastUpdate = now;
        lastRateUpdate = now;
        debtRate = long;

        _creator = msg.sender;
    }

    function setPairPyToken(address _pyToken) public {
        require(msg.sender == _creator, "setPairPyToken/only-callable-by-factory");
        pairPyToken = _pyToken;
    }

    // Math functions
    function simpleInterest(uint rate, uint exponent, uint unit) public returns(uint256) {
        //uint256 half = unit / 2;
        //return unit + rate * exponent + half*rate*rate*exponent*(exponent - 1)/(unit*unit);
        return unit + (rate * exponent);
    }

    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    function fmul(uint x, uint y, uint unit) public pure returns (uint z) {
        z = mul(x, y) / unit;
    }

    function preciseDiv(uint256 value, uint256 precision, uint256 divisor) public pure returns (uint z){
        z = ((value + precision/2) * precision)/divisor;
    }

    // Transfer functions
    function transferUnderlying(address sender, address recipient, uint256 amount) public {
    }

    // view functions
    function totalSupplyUnderlying() public view returns (uint256) {
        return fmul(totalSupply(), rateAccumulator, long);
    }

    function balanceOfUnderlying(address account) public view returns (uint){
        return fmul(balanceOf(account), rateAccumulator, long);
    }

    function getTotalDebt() public view returns (uint256) {
        return fmul(normalizedDebt, debtAccumulator, long);
    }

    function debtInUnderlying(address usr) public view returns (uint256){
        return fmul(repos[usr].normalizedDebt, debtAccumulator, long);
    }

    function getCollateralBalance(address user) public view returns (uint256){
        return repos[user].userCollateral;
    }

    function getReserveRatio() public view returns (uint256) {
        if (underlyingHeld <= 0){
            return 0;
        }
        return (underlyingHeld * short) / (getTotalDebt() + underlyingHeld);
    }

    // pyToken creation and redemption
    function mint(uint256 amount) public returns (bool) {
        //accrueInterest();
        //updateRates();
        require(ERC20(underlying).transferFrom(msg.sender, address(this), amount), "mint/failed-transfer");
        uint256 normalizedAmount = (amount * long)/rateAccumulator;
        _mint(msg.sender, normalizedAmount);

        underlyingHeld += amount;
        return true;
    }

    function redeem(uint256 amount) public returns (bool) {
        //accrueInterest();
        //updateRates();
        require(amount >= 0, "redeem/cannot-redeem-negative amount");
        require(underlyingHeld >= amount, "redeem/cannot-redeem-more-than-reserves");
        require(balanceOfUnderlying(msg.sender) >= amount, "redeem/amount-exceeds-funds");
        uint256 normalizedAmount = (amount * long)/rateAccumulator;
        _burn(msg.sender, normalizedAmount);
        require(ERC20(underlying).transfer(msg.sender, amount), "redeem/failed-transfer");
        underlyingHeld -= amount;
    }

    function accrueInterest() public {
        if (lastUpdate >= now || totalSupply() == 0) return;
        console.log("debtRate '%i'", debtRate);
        console.log("Time");
        uint256 periods = now - lastUpdate;
        console.log(periods);
        uint256 accumulatedDebtInterestMultiplier = simpleInterest(debtRate - long, periods, long);
        console.log("ADIMs '%i'", accumulatedDebtInterestMultiplier);
        console.log("DebtAccumulator    '%i'", debtAccumulator);
        // uint256 oldDebtAccumulator = debtAccumulator;
        debtAccumulator = fmul(accumulatedDebtInterestMultiplier, debtAccumulator, long);
        console.log("DebtAccumulator    '%i'", debtAccumulator);
        uint256 allDebt = fmul(normalizedDebt, debtAccumulator, short);
        console.log("All Debt    '%i'", allDebt);
        uint256 newDebt = fmul(accumulatedDebtInterestMultiplier - long, allDebt, long);
        console.log("New Debt    '%i'", newDebt);
        // uint256 newDebt2 = fmul(debtAccumulator - oldDebtAccumulator, normalizedDebt, short);
        console.log("New Debt 2    '%i'", newDebt);
        uint256 feeIncome = fmul(newDebt, borrowFee, short);
        totalFeeIncome += feeIncome;
        console.log("Fee Income '%i'", feeIncome);
        uint256 totalPyTokens = fmul(totalSupply(), rateAccumulator, short);
        console.log("Total pyTokens '%i'", totalPyTokens);
        rateAccumulator = (((newDebt - feeIncome) + totalPyTokens)*long) / fmul(totalSupply(), long, short);
        console.log("Total Supply '%i'", totalSupply());
        console.log("Rate Accumulator '%i'", rateAccumulator);
        lastBlockInterest = (((newDebt - feeIncome) + totalPyTokens)*long) / totalPyTokens;
        lastBlockInterestPeriods = periods;
        console.log("Last Block Interest '%i'", lastBlockInterest);
        lastUpdate = now;
    }

    function updateRates() public {
        if (lastRateUpdate >= now || totalSupply() == 0) return;
        uint256 imbalance = getReserveRatio();
        int256 updateRate;
        if (imbalance > liquidityTarget)            updateRate = -int(interestUpdateAmount);
        else if (imbalance < liquidityTarget) updateRate = int(interestUpdateAmount);
        else updateRate = 0;
        console.log("Update Rate");
        console.logInt(updateRate);
        debtRate = fmul(debtRate, uint256(int(long) + updateRate), long);
        console.log("debtRate '%i'", debtRate);
        if (debtRate < long) debtRate = long;     // debtRate must not go below 1.0
        if (debtRate > debtRateLimit) debtRate = debtRateLimit;
        if (normalizedDebt == 0) debtRate = long;
        console.log("debtRate '%i'", debtRate);
        lastRateUpdate = now;
    }

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

    // borrow by pointing to a valid repo with a lower liquidation price
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
        uint256 finalDebt = fmul(repos[msg.sender].normalizedDebt, debtAccumulator, long) + amountToBorrow;
        uint256 usrRatio = finalDebt/availableCollateral;
        uint256 compRatio = fmul(repos[comparisonRepo].normalizedDebt, debtAccumulator, long) / repos[comparisonRepo].lockedCollateral;
        require(usrRatio < compRatio, "borrowCompare/comparison-to-comparison-repo-not-successful");
        repos[msg.sender].normalizedDebt = repos[msg.sender].normalizedDebt + amountToBorrow/debtAccumulator;
        repos[msg.sender].lockedCollateral += collateralToLock;
        repos[msg.sender].userCollateral -= collateralToLock;
        uint256 normalizedAmount = (amountToBorrow * long)/rateAccumulator;
        _mint(msg.sender, normalizedAmount);
        normalizedDebt += normalizedAmount;
    }

    function startBorrow() public {
        Oracle(oracle).startTWAP();
        startBorrowTime = now;
    }

    function completeBorrow(address usr, uint256 amountToBorrow, uint256 collateralToLock) public {
        uint256 twapPrice = Oracle(oracle).endTWAP();
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
        uint256 finalDebt = fmul(repos[msg.sender].normalizedDebt, debtAccumulator, long) + amountToBorrow;
        uint256 collateralNeeded = finalDebt * collateralizationRatio / twapPrice;
        console.log("collateralNeeded '%i' availableCollateral '%i'", collateralNeeded, availableCollateral);
        require(collateralNeeded <= availableCollateral, "completeBorrow/insufficient-collateral-for-new-debt");
        repos[msg.sender].normalizedDebt = repos[msg.sender].normalizedDebt + (amountToBorrow * long)/debtAccumulator;
        repos[msg.sender].lockedCollateral += collateralToLock;
        repos[msg.sender].userCollateral -= collateralToLock;
        uint256 normalizedAmount = (amountToBorrow * long)/rateAccumulator;
        //console.log("Normalized tokens '%i' Requested tokens '%i'", normalizedAmount, amountToBorrow);
        _mint(msg.sender, normalizedAmount);
        normalizedDebt += normalizedAmount;
    }

    function mathTest(uint256 value) public {
        uint256 normalizedAmount = (value * long)/rateAccumulator;
        console.log("Normalized Amount '%i' Requested value '%i'", normalizedAmount, value);
    }

    function repay(address usr, uint256 amountToPayback) public {
        uint256 normalizedPayback = (amountToPayback * long)/rateAccumulator;
        //console.log("Normalized payback '%i' Requested tokens '%i' BalanceOf '%i", normalizedPayback, amountToPayback, balanceOf(msg.sender));
        require(
            balanceOf(msg.sender) >= normalizedPayback,
            "repay/insufficient-funds-to-repay"
        );
        _burn(msg.sender, normalizedPayback);
        uint256 debtCancelled = (amountToPayback * long) / debtAccumulator;
        require(
            repos[usr].normalizedDebt >= debtCancelled,
            "repay/cannot-repay-more-than-debt"
        );
        repos[usr].normalizedDebt -= debtCancelled;
    }

    function startUnlock() public {
        Oracle(oracle).startTWAP();
        startUnlockTime = now;
    }

    function completeUnlock(uint256 collateralToUnLock) public {
        uint256 twapPrice = Oracle(oracle).endTWAP();
        require(
            now - startBorrowTime > ONE_HOUR,
            "completeUnlock/must-wait-an-hour-before-calling-completeUnlock"
        );
        uint256 availableCollateral = repos[msg.sender].lockedCollateral - collateralToUnLock;
        uint256 finalDebt = fmul(repos[msg.sender].normalizedDebt, debtAccumulator, long);
        uint256 collateralNeeded = finalDebt * collateralizationRatio / twapPrice;
        console.log("finalDebt '%i' collateralNeeded '%i'", finalDebt, collateralNeeded);
        require(availableCollateral >= collateralNeeded, "completeUnlock/insufficient-collateral-to-complete-unlock");
        repos[msg.sender].lockedCollateral -= collateralToUnLock;
        repos[msg.sender].userCollateral += collateralToUnLock;
    }

    /**
    function startLiquidation(address userToLiquidate) public {
        require(repos[user].normalizedDebt > 0, "startLiquidiation/repo-has-no-debt");
        pyOracle().read()
        liquidations[user].lockedForLiquidation = true;
        liquidations[user].lockedBy = msg.sender;
        //TODO: Lock Funds
    }

    function completeLiquidation(address userToLiquidate) public {

        uint256 price = pyOracle().read()
        uint256 debt = fmul(repos[userToLiquidate].normalizedDebt, debtAccumulator, long) + amountToBorrow;
        uint256 collateralNeeded = debt * collateralizationRatio / repos[msg.sender].lockedCollateral;
        if (price < liquidationPrice) {
        }
    }
    */
}
