import { ethers } from "hardhat";

async function main() {
  const plasma = await ethers.deployContract("Plasma", []);
  await plasma.waitForDeployment();
  console.log("Plasma contract deployed to:", plasma.target);
  
}

// We recommend this pattern to be able to use async/await everywhere
// and properly handle errors.
main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
