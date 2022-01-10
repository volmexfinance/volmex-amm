import { run } from "hardhat";

const verify = async () => {
  const implementation = process.env.IMPLEMENTATION;

  console.log("Verifying ", implementation);

  await run("verify:verify", {
    address: implementation,
    constructorArguments: [
      /**
       * Place constructor arguments here
       */
    ],
  });
};

verify()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log("Error: ", error);
    process.exit(1);
  });
