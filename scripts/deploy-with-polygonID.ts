import { ethers } from "hardhat";

async function main() {
  const groth16Verifier = await ethers.deployContract("Groth16Verifier", []);
  await groth16Verifier.waitForDeployment();
  console.log("Groth16Verifier contract deployed to:", groth16Verifier.target);
  const plasma = await ethers.deployContract("PlasmaPolygon", [groth16Verifier.target]);
  await plasma.waitForDeployment();
  console.log("Plasma contract deployed to:", plasma.target);
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
