const pyTokenFactory = artifacts.require("pyTokenFactory");
const Collateral = artifacts.require("Collateral");
const Underlying = artifacts.require("Underlying");
const MockContract = artifacts.require("./MockContract");



// Traditional Truffle test
contract("pyTokenFactory", accounts => {
    let collateral;
    let underlying;
    let pytokenInstance;
    let oracle;
  
    describe("Factory tests", () => {
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
        
        pytokenFactoryInstance = await pyTokenFactory.new( 
        ); 
      })
    
      it("Should deploy new pyToken", async function() {
      });
    })
})  