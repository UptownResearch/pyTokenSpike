pragma solidity ^0.5.1;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";
import "./pytokenFactory.sol";
import "./pyoracle.sol";


/// @dev Test ERC20 asset contract. When live this will have been deployed by a third party.
contract Collateral is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
    }
}


/// @dev Test ERC20 asset contract. When live this will been deployed by a third party.
contract Underlying is ERC20 {
    function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
    }
}

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


/// @dev Perpetual Yield Token for an ERC20 token pair.
contract pyToken is ERC20 {
    // definitions
    uint short = 10**18; // Used for currency amounts
    uint long = 10**27; // Used for mathematical variables

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

    // Interest Rate variables - are these all long?
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
        uint256 id; //ID of oracle session
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
        rateAccumulator = long;
        debtAccumulator = long;
        lastBlockInterest = long;
        lastUpdate = now;
        lastRateUpdate = now;
        debtRate = long;

        _creator = msg.sender;
    }

    /// @dev Set the address for the reverse pyToken contract
    function setPairPyToken(address _pyToken) public {
        require(msg.sender == _creator, "setPairPyToken/only-callable-by-factory");
        pairPyToken = _pyToken;
    }

    // Math functions
    /// @dev Compounds interest for a number of periods using the binomial approximation 
    function compoundInterestRate(uint rate, uint periods, uint unit) public returns(uint256) { // Rename exponent to periods?
        return unit + (rate * periods);
    }

    /// @dev Overflow protected multiplication
    function mul(uint x, uint y) public pure returns (uint z) {
        require(y == 0 || (z = x * y) / y == x);
    }

    /// @dev Overflow protected fixed point multiplication with parameterized unit.
    function fmul(uint x, uint y, uint unit) public pure returns (uint z) {
        z = mul(x, y) / unit;
    }

    /// @dev Divide and round up. Remove in the future--not used. 
    function preciseDiv(uint256 value, uint256 precision, uint256 divisor) public pure returns (uint z){
        z = ((value + precision/2) * precision)/divisor;
    }

    // Transfer functions
    function transferUnderlying(address sender, address recipient, uint256 amount) public {
    }

    // view functions - all return currency amounts.
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
    /// @dev Take underlying tokens from user, and mint pyTokens in exchange.
    function mint(uint256 amount) public returns (bool) {
        //accrueInterest();
        //updateRates();
        require(ERC20(underlying).transferFrom(msg.sender, address(this), amount), "mint/failed-transfer");
        uint256 normalizedAmount = (amount * long)/rateAccumulator;
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
        uint256 normalizedAmount = (amount * long)/rateAccumulator;
        _burn(msg.sender, normalizedAmount);
        require(ERC20(underlying).transfer(msg.sender, amount), "redeem/failed-transfer");
        underlyingHeld -= amount;
    }

    /// @dev Update the accrued interest and related variables, according to the number of seconds since the previous update.
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

    /// @dev Update the rate at which interest is accrued
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

    // This approach is out of date.
    /// @dev Why is borrowing forbidden for an hour after updating prices?
    function startBorrow() public { // If access is not restricted, this will be open to DoS attacks.
        Oracle(oracle).startTWAP();
        startBorrowTime = now;
    }

    /// @dev Setup or update a Repurchase Agreement
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

    /// @dev Let's move this one out of the contract.
    function mathTest(uint256 value) public {
        uint256 normalizedAmount = (value * long)/rateAccumulator;
        console.log("Normalized Amount '%i' Requested value '%i'", normalizedAmount, value);
    }

    /// @dev Cancel part or all of a repo debt by burning pyTokens
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

    /// @dev Unlocking collateral to use in a repo needs the underlying asset prices.
    function startUnlock() public {
        Oracle(oracle).startTWAP();
        startUnlockTime = now;
    }

    /// @dev Unlock collateral to use in a repo.
    function completeUnlock(uint256 collateralToUnLock) public {
        uint256 twapPrice = Oracle(oracle).endTWAP();
        require(
            now - startBorrowTime > ONE_HOUR, // I think we mean startUnlockTime
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

    /// @dev Initiate liquidation of a repo
   function startLiquidation(address userToLiquidate) public {
        require(repos[userToLiquidate].normalizedDebt > 0, "startLiquidiation/repo-has-no-debt");
        liquidations[userToLiquidate].id = pyOracle().startUniqueRead(); //force an oracle update, if not currently up to date. 
        liquidations[userToLiquidate].lockedForLiquidation = true;
        liquidations[userToLiquidate].lockedBy = msg.sender;
        //TODO: Lock Funds
    }

    /// @dev Complete liquidation of a repo by sending it to auction or by removing from liquidation
    function completeLiquidation(address userToLiquidate) public {
        // TODO: require startLiquidation has been called
        uint26 period = 3600;
        uint256 price = pyOracle().endUniqueRead(liquidations[userToLiquidate], period);
        uint256 debt = fmul(repos[userToLiquidate].normalizedDebt, debtAccumulator, long) + amountToBorrow;
        uint256 liquidationPrice = debt * collateralizationRatio / repos[msg.sender].lockedCollateral;
        if (price < liquidationPrice) {
            // kick the vault into liquidiation
            address liquidations;
            Liquidations(liquidations).startAuction(
                                            collateral,
                                            repos[userToLiquidate].lockedCollateral
                                            address(this),
                                            debt
                                        );

        } else {
            // liquidation is inappropriate
        }
    }
}
