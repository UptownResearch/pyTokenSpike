pragma solidity ^0.5.1;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";

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
  function startTWAP() public {}
  function endTWAP() public returns (uint256) {}
}

contract pyToken is ERC20 {
  // definitions
  uint short = 10**18;
  uint long = 10**27;
  
  // Token information
  string public name = "pyToken";
  string public symbol = "pY";
  // uint8 public decimals = 18;


  // ERC-20 parameters
  address public underlying;
  address public collateral; 
  address public oracle; 

  // interest parameters
  uint256 public interestUpdateAmount;
  uint256 public collateralizationRatio;
  uint256 public reservesTarget;
  uint256 public adjustmentFreeWindow;
  uint256 public debtRateLimit;

  // Interest Rate variables
  uint256 public rateAccumulator;  
  uint256 public debtAccumulator;
  uint256 public debtRate;
  uint256 public normalizedDebt;
  uint256 public bonus;
  uint256 public borrowFee;
  uint256 public totalFeeIncome;
  uint256 public lastBlockInterest;
  uint256 public lastUpdate;
  uint256 public lastRateUpdate;

  // value held in contract
  uint256 public underlyingHeld;

  //repos 
  struct Repo {
    uint256 userCollateral;
    uint256 lockedCollateral;
    uint256 normalisedDebt;
    bool    lockedForLiquidation;
  }  
  mapping(address => Repo)  public repos;

  //Oracle
  uint256 startBorrowTime; 
  uint256 ONE_HOUR = 60*60;

  constructor ( 
                address _underlying,
                address _collateral,
                address _oracle,
                uint256 _interestUpdateAmount,
                uint256 _collateralizationRatio,
                uint256 _debtRateLimit,
                uint256 _reservesTarget,
                uint256 _adjustmentFreeWindow,
                uint256 _borrowFee 
              )  public {
      underlying = _underlying;
      collateral = _collateral;
      oracle     = _oracle;
      interestUpdateAmount = _interestUpdateAmount;
      collateralizationRatio = _collateralizationRatio;
      debtRateLimit = _debtRateLimit;
      reservesTarget = _reservesTarget;
      adjustmentFreeWindow = _adjustmentFreeWindow;
      borrowFee = _borrowFee;

      totalFeeIncome = 0;
      rateAccumulator = long;
      debtAccumulator = long;
      lastBlockInterest = 0;
      lastUpdate = now;
      lastRateUpdate = now;
      debtRate = long;

  }

  // Math functions
  function simpleInterest(uint rate, uint exponent, uint ONE) public returns(uint256) {
    uint256 half = ONE / 2;
    //return ONE + rate * exponent + half*rate*rate*exponent*(exponent - 1)/(ONE*ONE); 
    return ONE + (rate * exponent); 
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x);
  }

  function fmul(uint x, uint y, uint ONE) internal pure returns (uint z) {
    z = mul(x, y) / ONE;
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
    require(ERC20(underlying).transferFrom(address(this), msg.sender, amount), "redeem/failed-transfer");
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
    debtAccumulator = fmul(accumulatedDebtInterestMultiplier, debtAccumulator, long);
    uint256 allDebt = fmul(normalizedDebt, debtAccumulator, long);
    uint256 newDebt = fmul(accumulatedDebtInterestMultiplier - long, allDebt, long);
    uint256 feeIncome = fmul(newDebt, borrowFee, long);
    totalFeeIncome += feeIncome;
    uint256 totalPyTokens = fmul(totalSupply(), rateAccumulator, short);
    rateAccumulator = ((newDebt - feeIncome) + totalPyTokens) / fmul(totalSupply(), long, short);
    lastBlockInterest = ((newDebt - feeIncome) + totalPyTokens) / totalPyTokens;
    lastUpdate = now; 
  }

  function updateRates() public {
    if (lastRateUpdate >= now || totalSupply() == 0) return;
    uint256 imbalance = getReserveRatio();
    int256 updateRate;
    if (imbalance > reservesTarget)      updateRate = -int(interestUpdateAmount);
    else if (imbalance < reservesTarget) updateRate =  int(interestUpdateAmount);
    else updateRate = 0; 
    console.log("Update Rate");
    console.logInt(updateRate);
    debtRate = fmul(debtRate, uint256(int(long) + updateRate), long);
    console.log("debtRate '%i'", debtRate);
    if (debtRate < long) debtRate = long;   // debtRate must not go below 1.0
    if (debtRate > debtRateLimit) debtRate = debtRateLimit;
    if (normalizedDebt == 0) debtRate = long;
    console.log("debtRate '%i'", debtRate);
    lastRateUpdate = now; 
  }


  function addCollateral(address user, uint256 amount) public {
    //accrueInterest();
    //updateRates();
    require(int(amount) >= 0, "addCollateral/overflow");
    require(ERC20(collateral).transferFrom(msg.sender, address(this), amount), "addCollateral/failed-transfer");
    repos[user].userCollateral += amount;
  }

  function withdrawCollateral(address user, uint256 amount) public {
    //accrueInterest();
    //updateRates();
    require(amount <= 2 ** 255, "withdrawCollateral/overflow");
    repos[msg.sender].userCollateral -= amount;
    require(ERC20(collateral).transferFrom( address(this), msg.sender, amount), "withdrawCollateral/failed-transfer");
  }

  // borrow by pointing to a valid repo with a lower liquidation price
  function borrowCompare(address comparisonRepo, address usr, uint256 amountToBorrow, uint256 collateralToLock) public {
    require(repos[comparisonRepo].lockedForLiquidation == false, "borrowCompare/comparisonRepo-is-locked-for-liquidation");
    require(repos[msg.sender].userCollateral >= collateralToLock, "borrowCompare/collateralToLock-is-greater-than-userCollateral");
    // how are we handling collateral decimals?
    uint256 availableCollateral = repos[msg.sender].lockedCollateral + collateralToLock;
    uint256 finalDebt = fmul(repos[msg.sender].normalisedDebt, debtAccumulator, long) + amountToBorrow;
    uint256 usrRatio = finalDebt/availableCollateral;
    uint256 compRatio = fmul(repos[comparisonRepo].normalisedDebt, debtAccumulator, long) / repos[comparisonRepo].lockedCollateral;
    require(usrRatio < compRatio, "borrowCompare/comparison-to-comparison-repo-not-successful");
    repos[msg.sender].normalisedDebt = repos[msg.sender].normalisedDebt + amountToBorrow/debtAccumulator;
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
    require(now - startBorrowTime > ONE_HOUR, "completeBorrow/must-wait-an-hour-before-calling-completeBorrow");
    require(repos[msg.sender].userCollateral >= collateralToLock, "completeBorrow/collateralToLock-is-greater-than-userCollateral");
    // how are we handling collateral decimals?
    uint256 availableCollateral = repos[msg.sender].lockedCollateral + collateralToLock;
    uint256 finalDebt = fmul(repos[msg.sender].normalisedDebt, debtAccumulator, long) + amountToBorrow;
    uint256 collateralNeeded = fmul(finalDebt, collateralizationRatio, short) / twapPrice; 
    require(collateralNeeded < availableCollateral, "completeBorrow/insufficient-collateral-for-new-debt");
    repos[msg.sender].normalisedDebt = repos[msg.sender].normalisedDebt + amountToBorrow/debtAccumulator;
    repos[msg.sender].lockedCollateral += collateralToLock;
    repos[msg.sender].userCollateral -= collateralToLock;
    uint256 normalizedAmount = (amountToBorrow * long)/rateAccumulator;
    //console.log("Normalized tokens '%i' Requested tokens '%i'", normalizedAmount, amountToBorrow);
    _mint(msg.sender, normalizedAmount);
    normalizedDebt += normalizedAmount;
  }



}
