pragma solidity ^0.5.1;

import "openzeppelin-solidity/contracts/token/ERC20/ERC20.sol";
import "@nomiclabs/buidler/console.sol";

contract Token is ERC20 {
  string public name = "TutorialToken";
  string public symbol = "TT";
  uint8 public decimals = 2;
  uint public INITIAL_SUPPLY = 12000;

  function rpow(uint x, uint n, uint base) public pure returns (uint z) {
      assembly {
  switch x case 0 {switch n case 0 {z := base} default {z := 0}}
  default {
    switch mod(n, 2)
            case 0 { z := base }
            default { z := x }
      let half := div(base, 2) // Used for rounding.
              for { n := div(n, 2) } n { n := div(n,2) } {
        let xx := mul(x, x)
              if iszero(eq(div(xx, x), x)) { revert(0,0) }
        let xxRound := add(xx, half) if lt(xxRound, xx) { revert(0,0) }
        x := div(xxRound, base)
            if mod(n,2) {
                    let zx := mul(z, x)
                if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0,0) }
                let zxRound := add(zx, half) if lt(zxRound, zx) { revert(0,0) }
          z := div(zxRound, base)
                  }
              }
        }
      }
  }

  function simpleInterest(uint rate, uint exponent, uint base) public returns(uint256) {
    uint256 half = base / 2;
    return base + rate * exponent + half*rate*rate*exponent*(exponent - 1)/(base*base); 
  }


  function mint(uint amount) public {
        _mint(msg.sender, amount);
        console.log("Minting '%i' tokens", amount);
  }


  function tryITold() public {
    uint256 number = 1 ether; 
    console.log("Value '%i'", number);
    uint256 number2 = number ** 10;
    console.log("Value '%i'", number2);
    uint base = 10**27;
    assert(rpow(0, 3, base) == 0);
    assert(rpow(0, 0, base) == base);
    console.log("Exp '%i'", rpow(number, 10, 1 ether));
    // 10% a year rate per block
    uint256 rate = 1000000003014008422;
    console.log("One year '%i'", rpow(rate, 31622400, 1 ether));
    uint256 justRate = 3014008422;
    console.log("simpleInterest '%i'", simpleInterest(justRate, 31622400, 1 ether));
  }

  function mul(uint x, uint y) internal pure returns (uint z) {
    require(y == 0 || (z = x * y) / y == x);
  }

  function fmul(uint x, uint y, uint ONE) internal pure returns (uint z) {
    z = mul(x, y) / ONE;
  }

  function doIT() public {
    uint256 snumber = 12345 * 10**15; //12.345
    uint256 enumber = 34567 * 10**23; //3.4567
    uint256 result = fmul(snumber, enumber, 10**27);
    console.log("Result '%i'", result);
  }


  function tryIT() public {
  
  }

}
