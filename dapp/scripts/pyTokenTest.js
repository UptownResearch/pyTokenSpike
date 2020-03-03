// We require the Buidler Runtime Environment explicitly here. This is optional
// when running the script with `buidler run <script>`: you'll find the Buidler
// Runtime Environment's members available as global variable in that case.
const env = require("@nomiclabs/buidler");

async function main() {
  // You can run Buidler tasks from a script.
  // For example, we make sure everything is compiled by running "compile"
  //await env.run("compile");

  // We require the artifacts once our contracts are compiled
  //const Greeter = env.artifacts.require("Greeter");
  //const greeter = await Greeter.new("Hello, world!");

  //console.log("Greeter address:", greeter.address);
  const pyToken = env.artifacts.require("pyToken");
  const Collateral = env.artifacts.require("Collateral");
  const Underlying = env.artifacts.require("Underlying");
  const Oracle = env.artifacts.require("Oracle");

  collateral = await Collateral.new();
  underlying = await Underlying.new();
  oracle = await Oracle.new();
  pytokenInstance = await pyToken.new( 
    collateral.address,
    underlying.address,
    oracle.address,
    "3162157215564487",
    web3.utils.toWei("1.5"),
    "2000000000000000000000000000",
    web3.utils.toWei("0.3"),
    web3.utils.toWei("0.1"),
    web3.utils.toWei("0.001")
  ); 
  console.log("Collateral address:", collateral.address);
  console.log("Underlying address:", underlying.address);
  console.log("Oracle address:", oracle.address);
  console.log("pyToken address:", pytokenInstance.address);
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
