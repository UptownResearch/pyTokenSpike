const pyToken = artifacts.require("pyToken");
const Collateral = artifacts.require("Collateral");
const Underlying = artifacts.require("Underlying");
const MockContract = artifacts.require("./MockContract");
const Oracle = artifacts.require("Oracle");

const helper = require('ganache-time-traveler');
const SECONDS_IN_DAY = 86400;

const ethers = require('ethers');
utils = ethers.utils;



const timestamp = (block = "latest", web3) => {
  return new Promise((resolve, reject) => {
    web3.eth.getBlock(block, false, (err, { timestamp }) => {
      if (err) {
        return reject(err)
      } else {
        resolve(timestamp)
      }
    })
  })
}



// Traditional Truffle test
contract("pyToken", accounts => {
  let collateral;
  let underlying;
  let pytokenInstance;
  let oracle;

  describe("basic tests", () => {
    before("deploy and setup", async () => {
      //collateral = await Collateral.new();
      //underlying = await Underlying.new();
      //await collateral.mint(web3.utils.toWei("100"));
      //await underlying.mint(web3.utils.toWei("100"));   
      collateral = await MockContract.new();
      await collateral.givenAnyReturnBool(true);
      underlying = await MockContract.new();
      await underlying.givenAnyReturnBool(true);
      oracle = await MockContract.new();
      
      pytokenInstance = await pyToken.new( 
        underlying.address,
        collateral.address,
        oracle.address,
        "3162157215564487",
        web3.utils.toWei("1.5"),
        "2000000000000000000000000000",
        web3.utils.toWei("0.3"),
        web3.utils.toWei("0.1"),
        web3.utils.toWei("0.001")
      ); 
    })
  
    it("Should mint 1", async function() {
      const result = await pytokenInstance.mint(web3.utils.toWei("1"),{
      from: accounts[0],
      });
      var balance = web3.utils.fromWei((await pytokenInstance.balanceOf(accounts[0])));
      assert(balance == 1, "balance not equal to 1");
      var underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
    });
      
    it("should redeem half", async function() {
      var underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
      const result = await pytokenInstance.redeem(web3.utils.toWei("0.5"),{
        from: accounts[0],
        });
      var balance = web3.utils.fromWei((await pytokenInstance.balanceOf(accounts[0])));
      assert(balance == 0.5, "balance not equal to .5");
    });

    it("should add collateral", async function() {
      const result = await pytokenInstance.addCollateral(accounts[0], web3.utils.toWei("20"),{
        from: accounts[0],
        });
      var balance = web3.utils.fromWei((await pytokenInstance.getCollateralBalance(accounts[0])));
      assert(balance == 20, "balance not equal to 20");
    });

    it("should withdraw collateral", async function() {
      const result = await pytokenInstance.withdrawCollateral(accounts[0], web3.utils.toWei("10"),{
        from: accounts[0],
        });
      var balance = web3.utils.fromWei((await pytokenInstance.getCollateralBalance(accounts[0])));
      assert(balance == 10, "balance not equal to 10");
    });

    it("should advance in time", async function() {
      var currentTimeStamp = await timestamp("latest", web3);
      //console.log("Current Time ", currentTimeStamp);
      //console.log("Later Time ", currentTimeStamp + SECONDS_IN_DAY);
      var number = await web3.eth.getBlockNumber()
      //console.log("Block Number ", number);
      await helper.advanceBlockAndSetTime(currentTimeStamp + SECONDS_IN_DAY);
      await helper.advanceTime(SECONDS_IN_DAY);
      await helper.advanceBlock();
      var number = await web3.eth.getBlockNumber()
      //console.log("Block Number ", number);
      var currentTimeStamp2 = await timestamp("latest", web3);
      //console.log("Current Time ", currentTimeStamp2);

    });

    it("should borrow pyTokens", async function() {
      await pytokenInstance.addCollateral(accounts[1], web3.utils.toWei("20"),{
        from: accounts[1],
        });
      await pytokenInstance.startBorrow({
        from: accounts[1],
        })
      await helper.advanceTime(60*60);
      await helper.advanceBlock();
      await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
      await pytokenInstance
        .completeBorrow(accounts[1], 
                        web3.utils.toWei("5"), 
                        web3.utils.toWei("10"), 
                        {
                          from: accounts[1],
                        })
      var balance = web3.utils.fromWei((await pytokenInstance.balanceOf(accounts[1])));
      console.log("Balance after borrow: ", balance);
      assert(balance == 5, "balance not equal to 5");

      var underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
      console.log("underlying Held ", underlyingHeld);
      var totalDebt = web3.utils.fromWei((await pytokenInstance.getTotalDebt()));
      console.log("total Debt ", totalDebt);
      var reserves = web3.utils.fromWei((await pytokenInstance.getReserveRatio()));
      console.log("Reserve ratio ", reserves);
    });

    it("should update rates", async function() {
      await pytokenInstance.updateRates();
      var rateAccumulator = (await pytokenInstance.rateAccumulator()).toString();
      console.log("rateAccumulator ", rateAccumulator);
      var rateAccumulator = (await pytokenInstance.rateAccumulator()).toString();
      console.log("rateAccumulator ", rateAccumulator);
      var debtAccumulator = (await pytokenInstance.debtAccumulator()).toString();
      console.log("debtAccumulator ", debtAccumulator);
      
    });

    it("should accrueInterest", async function() {
      await pytokenInstance.accrueInterest();
      var rateAccumulator = (await pytokenInstance.rateAccumulator()).toString();
      console.log("rateAccumulator ", rateAccumulator);
      var lastBlockInterest = (await pytokenInstance.lastBlockInterest()).toString();
      console.log("lastBlockInterest", rateAccumulator);
    });


    it("should borrow and repay pyTokens", async function() {
      await pytokenInstance.addCollateral(accounts[3], web3.utils.toWei("20"),{
        from: accounts[3],
        });
      await pytokenInstance.startBorrow({
        from: accounts[3],
        })
      await helper.advanceTime(60*60);
      await helper.advanceBlock();
      await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
      await pytokenInstance
        .completeBorrow(accounts[3], 
                        web3.utils.toWei("5"), 
                        web3.utils.toWei("10"), 
                        {
                          from: accounts[3]})
      
      var balance = (await pytokenInstance.balanceOf(accounts[3]));
      console.log("pyTokens after borrow: ", web3.utils.fromWei(balance));
      var rateAccumulator = (await pytokenInstance.rateAccumulator());
      //divisor = utils.bigNumberify(10).pow(27);
      //scaling = utils.bigNumberify(10).pow(9)
      //.toString()
      //b = utils.bigNumberify(balance.toString()).mul(scaling);
      //r = utils.bigNumberify(rateAccumulator.toString());
      //console.log(b.toString())
      //console.log(r.toString())
      //a = b.mul(r).add(divisor.div(2)).div(divisor)
      //a = a.add(scaling.div(2)).div(scaling)
      //out = a.toString();
      //console.log(out );
      await pytokenInstance.repay(accounts[3], web3.utils.toWei("5") , { from: accounts[3]});
      var debt = web3.utils.fromWei((await pytokenInstance.debtInUnderlying(accounts[3])));
      console.log("Debt after repay: ", debt);
      assert(debt == 0, "debt not equal to 0");
    });

    it("should unlock pyTokens", async function() {
      await pytokenInstance.startUnlock({
        from: accounts[3],
        })
      await helper.advanceTime(60*60);
      await helper.advanceBlock();
      await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
      userCollateral = (await pytokenInstance.repos(accounts[3]))['userCollateral'];
      console.log("User Collateral", userCollateral.toString());
      lockedCollateral = (await pytokenInstance.repos(accounts[3]))['lockedCollateral'];
      console.log("Locked Collateral", lockedCollateral.toString());
      await pytokenInstance
        .completeUnlock(web3.utils.toWei("10"), 
                        {
                          from: accounts[3]})
      userCollateralAfter = (await pytokenInstance.repos(accounts[3]))['userCollateral'];
      lockedCollateralAfter = (await pytokenInstance.repos(accounts[3]))['lockedCollateral'];
      result = await pytokenInstance.repos(accounts[3]);
      //console.log(result);
      console.log((userCollateralAfter - userCollateral).toString())
      console.log(web3.utils.toWei("10"))
      assert((userCollateralAfter - userCollateral).toString() == web3.utils.toWei("10") , "Collateral not correctly unlocked");
    });

  })
});
  