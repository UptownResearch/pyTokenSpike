const pyTokenFactory = artifacts.require("pyTokenFactory");
const pyToken = artifacts.require("pyToken");
const MockContract = artifacts.require("./MockContract");

// Traditional Truffle test
contract("pyTokenFactory", accounts => {
    let token2;
    let token1;
    // let pytokenInstance;
    // let oracle;
    let liquidations; 

    describe("Factory tests", () => {
        before("deploy and setup", async () => { 
            token2 = await MockContract.new();
            await token2.givenAnyReturnBool(true);
            token1 = await MockContract.new();
            await token1.givenAnyReturnBool(true);
            oracle = await MockContract.new();
            liquidations = await MockContract.new();
            
            const interestUpdateAmount = "3162157215564487";
            const collateralizationRatio = web3.utils.toWei("1.5");
            const debtRateLimit = "2000000000000000000000000000";
            const liquidityTarget = web3.utils.toWei("0.3");
            const adjustmentFreeWindow = web3.utils.toWei("0.1");
            const borrowFee = web3.utils.toWei("0.001");

            pytokenFactoryInstance = await pyTokenFactory.new(
                interestUpdateAmount,
                collateralizationRatio,
                debtRateLimit,
                liquidityTarget,
                adjustmentFreeWindow,
                borrowFee,
                liquidations.address,
            ); 
        })
    
        it("Should deploy new pyTokens", async function() {
            await pytokenFactoryInstance.createPyToken(token2.address, token1.address);
            const deployed1 = await pytokenFactoryInstance.getPyToken(token2.address, token1.address);
            let pytokeninstance1 = await pyToken.at(deployed1);
            const underlyingAddress1 = await pytokeninstance1.underlying();
            assert(underlyingAddress1 == token1.address, "pyToken has incorrect underlying");
            const deployed2 = await pytokenFactoryInstance.getPyToken(token1.address, token2.address);
            let pytokeninstance2 = await pyToken.at(deployed2);
            const underlyingAddress2 = await pytokeninstance2.underlying();
            assert(underlyingAddress2 == token2.address, "pyToken has incorrect underlying");
        });
    })
})    