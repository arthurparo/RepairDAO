require("dotenv").config();
const hre = require("hardhat");
async function main() {
  const [s] = await hre.ethers.getSigners();
  const token  = new hre.ethers.Contract(process.env.TOKEN_ADDRESS,  ["function approve(address,uint256) returns (bool)"], s);
  const escrow = new hre.ethers.Contract(process.env.ESCROW_ADDRESS, ["function depositar(uint256) external", "function stakes(address) view returns (uint256,uint256)"], s);
  const valor = hre.ethers.parseEther("900");
  console.log("Aprovando 900 REPAIR...");
  await (await token.approve(process.env.ESCROW_ADDRESS, valor)).wait();
  console.log("Depositando 900 REPAIR...");
  await (await escrow.depositar(valor)).wait();
  const [stakeAtual] = await escrow.stakes(s.address);
  console.log("Stake total agora:", hre.ethers.formatEther(stakeAtual), "REPAIR");
}
main().catch(console.error);
