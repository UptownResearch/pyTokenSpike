// We require the Buidler Runtime Environment explicitly here. This is optional
// when running the script with `buidler run <script>`: you'll find the Buidler
// Runtime Environment's members available as global variable in that case.
const env = require("@nomiclabs/buidler");
var fs = require("fs");

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
    underlying.address,
    collateral.address,
    oracle.address,
    "9162157215564487",
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
  var addresses = {
    collateral: collateral.address,
    underlying: underlying.address,
    oracle: oracle.address,
    pytoken: pytokenInstance.address
  };
  console.log(JSON.stringify(addresses, null, 4));
  fs.writeFileSync("./artifacts/addresses.json", JSON.stringify(addresses, null, 4), (err) => {
    if (err) {
        console.error(err);
        return;
    };
    console.log("Addresses file has been writted to ./artifacts/addresses.json");
  });

}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
