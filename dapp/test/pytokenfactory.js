const pyTokenFactory = artifacts.require("pyTokenFactory");
const pyToken = artifacts.require("pyToken");
const MockContract = artifacts.require("./MockContract");



// Traditional Truffle test
contract("pyTokenFactory", accounts => {
    let Token2;
    let Token1;
    let pytokenInstance;
    let oracle;
    let liquidations; 
  
    describe("Factory tests", () => {
      before("deploy and setup", async () => { 
        Token2 = await MockContract.new();
        await Token2.givenAnyReturnBool(true);
        Token1 = await MockContract.new();
        await Token1.givenAnyReturnBool(true);
        oracle = await MockContract.new();
        liquidations = await MockContract.new();
        
        pytokenFactoryInstance = await pyTokenFactory.new(
            "3162157215564487",
            web3.utils.toWei("1.5"),
            "2000000000000000000000000000",
            web3.utils.toWei("0.3"),
            web3.utils.toWei("0.1"),
            web3.utils.toWei("0.001") ,
            liquidations.address
        ); 
      })
    
      it("Should deploy new pyTokens", async function() {
        const result = await pytokenFactoryInstance.createPyToken(Token2.address, Token1.address);
        const deployed1 = await pytokenFactoryInstance.getPyToken(Token2.address, Token1.address);
        let pytokeninstance1 = await pyToken.at(deployed1);
        const underlyingAddress1 = await pytokeninstance1.underlying();
        assert(underlyingAddress1==Token1.address, "pyToken has incorrect underlying");
        const deployed2 = await pytokenFactoryInstance.getPyToken( Token1.address, Token2.address);
        let pytokeninstance2 = await pyToken.at(deployed2);
        const underlyingAddress2 = await pytokeninstance2.underlying();
        assert(underlyingAddress2==Token2.address, "pyToken has incorrect underlying");
      });


    })
})  