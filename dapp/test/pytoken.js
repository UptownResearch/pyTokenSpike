const pyToken = artifacts.require("pyToken");
const MockContract = artifacts.require("./MockContract");
// const Collateral = artifacts.require("Collateral");
// const Underlying = artifacts.require("Underlying");
// const Oracle = artifacts.require("Oracle");

const helper = require('ganache-time-traveler');
// const SECONDS_IN_DAY = 86400;

const ethers = require('ethers');
utils = ethers.utils;

/* const timestamp = (block = "latest", web3) => {
    return new Promise((resolve, reject) => {
        web3.eth.getBlock(block, false, (err, { timestamp }) => {
            if (err) {
                return reject(err);
            } else {
                resolve(timestamp);
            }
        })
    })
} */

// Traditional Truffle test
contract("pyToken", accounts => {
    const owner = accounts[0];
    const user1 = accounts[1];
    const user2 = accounts[2];
    
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
            
            const interestUpdateAmount = "3162157215564487"
            const collateralizationRatio = web3.utils.toWei("1.5");
            const debtRateLimit = "2000000000000000000000000000";
            const liquidityTarget = web3.utils.toWei("0.3");
            const adjustmentFreeWindow = web3.utils.toWei("0.1");
            const borrowFee = web3.utils.toWei("0.001");

            pytokenInstance = await pyToken.new( 
                underlying.address,
                collateral.address,
                oracle.address,
                interestUpdateAmount,
                collateralizationRatio,
                debtRateLimit,
                liquidityTarget,
                adjustmentFreeWindow,
                borrowFee,
            ); 
        })
    
        it("Should mint 1", async function() {
            // MockContract removes the need for owner to approve the transferring of underlying
            await pytokenInstance.mint(web3.utils.toWei("1"), { from: owner });
            
            const balance = web3.utils.fromWei((await pytokenInstance.balanceOf(owner)));
            assert(balance == 1, "balance not equal to 1");

            // Use an ERC20 and approve the transfer of underlying to test this.
            // const underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
        });
            
        it("should redeem half", async function() {
            // var underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
            await pytokenInstance.redeem(web3.utils.toWei("0.5"), { from: owner });
            
            const balance = web3.utils.fromWei((await pytokenInstance.balanceOf(owner)));
            assert(balance == 0.5, "balance not equal to .5");
        });

        it("should add collateral", async function() {
            await pytokenInstance.addCollateral(owner, web3.utils.toWei("20"), { from: owner });
            const balance = web3.utils.fromWei((await pytokenInstance.getCollateralBalance(owner)));
            assert(balance == 20, "balance not equal to 20");
        });

        it("should withdraw collateral", async function() {
            await pytokenInstance.withdrawCollateral(owner, web3.utils.toWei("10"), { from: owner });
            const balance = web3.utils.fromWei((await pytokenInstance.getCollateralBalance(owner)));
            assert(balance == 10, "balance not equal to 10");
        });

        /* it("should advance in time", async function() {
            var currentTimeStamp = await timestamp("latest", web3);
            //console.log("Current Time ", currentTimeStamp);
            //console.log("Later Time ", currentTimeStamp + SECONDS_IN_DAY);
            // var number = await web3.eth.getBlockNumber()
            //console.log("Block Number ", number);
            await helper.advanceBlockAndSetTime(currentTimeStamp + SECONDS_IN_DAY);
            await helper.advanceTime(SECONDS_IN_DAY);
            await helper.advanceBlock();
            // var number = await web3.eth.getBlockNumber()
            //console.log("Block Number ", number);
            // var currentTimeStamp2 = await timestamp("latest", web3);
            //console.log("Current Time ", currentTimeStamp2);

        }); */

        it("should borrow pyTokens", async function() {
            await pytokenInstance.addCollateral(user1, web3.utils.toWei("20"),{ from: user1 });
            await pytokenInstance.startBorrow({ from: user1 });
            await helper.advanceTime(60*60);
            await helper.advanceBlock();
            await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
            await pytokenInstance.completeBorrow(
                user1, 
                web3.utils.toWei("5"), 
                web3.utils.toWei("10"), 
                { from: user1 },
            );
            const balance = web3.utils.fromWei((await pytokenInstance.balanceOf(user1)));
            // console.log("Balance after borrow: ", balance);
            assert(balance == 5, "balance not equal to 5");

            // Move the logs below to their own asserts
            const underlyingHeld = web3.utils.fromWei((await pytokenInstance.underlyingHeld()));
            console.log("underlying Held ", underlyingHeld);
            const totalDebt = web3.utils.fromWei((await pytokenInstance.getTotalDebt()));
            console.log("total Debt ", totalDebt);
            const reserves = web3.utils.fromWei((await pytokenInstance.getReserveRatio()));
            console.log("Reserve ratio ", reserves);
        });

        it("should update rates", async function() {
            await pytokenInstance.updateRates();
            // Move the logs below to their own asserts
            const rateAccumulator = (await pytokenInstance.rateAccumulator()).toString();
            console.log("rateAccumulator ", rateAccumulator);
            const debtAccumulator = (await pytokenInstance.debtAccumulator()).toString();
            console.log("debtAccumulator ", debtAccumulator);
        });

        it("should accrueInterest", async function() {
            await pytokenInstance.accrueInterest();
            // Move the logs below to their own asserts
            const rateAccumulator = (await pytokenInstance.rateAccumulator()).toString();
            console.log("rateAccumulator ", rateAccumulator);
            const lastBlockInterest = (await pytokenInstance.lastBlockInterest()).toString();
            console.log("lastBlockInterest", rateAccumulator);
        });

        it("should borrow and repay pyTokens", async function() {
            await pytokenInstance.addCollateral(user2, web3.utils.toWei("20"),{ from: user2 });
            await pytokenInstance.startBorrow({ from: user2 });
            await helper.advanceTime(60*60);
            await helper.advanceBlock();
            await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
            await pytokenInstance.completeBorrow(
                user2, 
                web3.utils.toWei("5"), 
                web3.utils.toWei("10"), 
                { from: user2 },
            );
            
            // assert or remove
            const balance = (await pytokenInstance.balanceOf(user2));
            console.log("pyTokens after borrow: ", web3.utils.fromWei(balance));
            // var rateAccumulator = (await pytokenInstance.rateAccumulator());
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
            await pytokenInstance.repay(user2, web3.utils.toWei("5"), { from: user2 });
            const debt = web3.utils.fromWei((await pytokenInstance.debtInUnderlying(user2)));
            console.log("Debt after repay: ", debt);
            assert(debt == 0, "debt not equal to 0");
        });

        it("should unlock pyTokens", async function() {
            await pytokenInstance.startUnlock({ from: user2 });
            await helper.advanceTime(60*60);
            await helper.advanceBlock();
            await oracle.givenAnyReturnUint(web3.utils.toWei("2"));
            userCollateral = (await pytokenInstance.repos(user2))['userCollateral'];
            console.log("User Collateral", userCollateral.toString());
            // assert or remove
            lockedCollateral = (await pytokenInstance.repos(user2))['lockedCollateral'];
            console.log("Locked Collateral", lockedCollateral.toString());
            await pytokenInstance.completeUnlock(web3.utils.toWei("10"), { from: user2 });
            userCollateralAfter = (await pytokenInstance.repos(user2))['userCollateral'];
            // assert or remove
            lockedCollateralAfter = (await pytokenInstance.repos(user2))['lockedCollateral'];
            // result = await pytokenInstance.repos(user2);
            // console.log(result);
            // console.log((userCollateralAfter - userCollateral).toString());
            // console.log(web3.utils.toWei("10"));
            assert((userCollateralAfter - userCollateral).toString() == web3.utils.toWei("10") , "Collateral not correctly unlocked");
        });

    })
});
    