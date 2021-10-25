import { run } from "hardhat";

const verify = async () => {
  const implementation = `0x11154fc9de55DBCf8670bC7c72cBf78781F3Df08`;

  console.log("Verifying ", implementation);

  await run("verify:verify", {
    address: implementation,
    constructorArguments: [
      '0x0d2497c1eCB40F77BFcdD99f04AC049c9E9d83F7',
      '0x105aE5e940f157D93187082CafCCB27e1941B505',
      '0x58b744ff6Ed0A47925b431c58d842817C9e82DB4',
      '0x74bC67ed6948f0a4C387C353975F142Dc640537a'
    ]
  });
};

verify()
  .then(() => process.exit(0))
  .catch((error) => {
    console.log("Error: ", error);
    process.exit(1);
  });
