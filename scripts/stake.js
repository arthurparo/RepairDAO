/**
 * stake.js — Etapa 5
 * Demonstra o fluxo completo de staking:
 *   1. Aprova tokens para o Escrow
 *   2. Deposita tokens em staking (depositar)
 *   3. Consulta recompensa pendente
 *   4. Retira stake + recompensa (retirar)
 *
 * Execução:
 *   npx hardhat run scripts/stake.js --network sepolia
 */

require("dotenv").config();
const hre = require("hardhat");

const TOKEN_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
];

const ESCROW_ABI = [
  "function depositar(uint256 valor) external",
  "function retirar() external",
  "function stakes(address staker) external view returns (uint256 valor, uint256 depositadoEm)",
  "function recompensaPendente(address staker) external view returns (uint256)",
  "function totalStaked() external view returns (uint256)",
  "function getPrecoETH() external view returns (uint256)",
];

async function main() {
  const [staker] = await hre.ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  RepairDAO — Etapa 5: Staking");
  console.log("=".repeat(60));
  console.log(`Staker: ${staker.address}`);
  console.log("");

  const token  = new hre.ethers.Contract(process.env.TOKEN_ADDRESS,  TOKEN_ABI,  staker);
  const escrow = new hre.ethers.Contract(process.env.ESCROW_ADDRESS, ESCROW_ABI, staker);

  const valorStake = hre.ethers.parseEther("100"); // 100 REPAIR

  // 1. Verificar saldo
  const saldo = await token.balanceOf(staker.address);
  console.log(`[ 1 ] Saldo disponível: ${hre.ethers.formatEther(saldo)} REPAIR`);
  if (saldo < valorStake) {
    console.error("      ERRO: saldo insuficiente (mínimo 100 REPAIR).");
    process.exitCode = 1;
    return;
  }

  // 2. Consultar preço ETH (oráculo) — demonstra integração Etapa 4
  const precoETH = await escrow.getPrecoETH();
  const precoUSD = Number(precoETH) / 1e8;
  const multiplicador = precoUSD > 2000 ? "1.5x" : "1.0x";
  console.log(`[ 2 ] Preço ETH (Chainlink): $${precoUSD.toFixed(2)}`);
  console.log(`      Multiplicador de recompensa: ${multiplicador}`);
  console.log("");

  // 3. Verificar stake atual
  const stakeAtual = await escrow.stakes(staker.address);
  if (stakeAtual.valor > 0n) {
    console.log(`[ 3 ] Stake existente: ${hre.ethers.formatEther(stakeAtual.valor)} REPAIR`);
    const recompensa = await escrow.recompensaPendente(staker.address);
    console.log(`      Recompensa pendente: ${hre.ethers.formatEther(recompensa)} REPAIR`);
    console.log("");
  } else {
    console.log(`[ 3 ] Nenhum stake ativo ainda.`);
    console.log("");
  }

  // 4. Aprovar tokens
  console.log(`[ 4 ] Aprovando ${hre.ethers.formatEther(valorStake)} REPAIR para o Escrow...`);
  const approveTx = await token.approve(process.env.ESCROW_ADDRESS, valorStake);
  await approveTx.wait();
  console.log(`      TX: ${approveTx.hash}`);

  // 5. Depositar em staking
  console.log(`[ 5 ] Depositando ${hre.ethers.formatEther(valorStake)} REPAIR em staking...`);
  const depositarTx = await escrow.depositar(valorStake);
  await depositarTx.wait();
  console.log(`      TX: ${depositarTx.hash}`);

  // 6. Confirmar stake
  const stakeNovo = await escrow.stakes(staker.address);
  const totalStaked = await escrow.totalStaked();
  console.log(`\n[ 6 ] Stake confirmado:`);
  console.log(`      Valor em stake:  ${hre.ethers.formatEther(stakeNovo.valor)} REPAIR`);
  console.log(`      Total do pool:   ${hre.ethers.formatEther(totalStaked)} REPAIR`);

  // Nota sobre retirada
  console.log(`\n      Para retirar o stake + recompensa, descomente`);
  console.log(`      o bloco 'retirar' no final deste script e execute novamente.`);

  // ----------------------------------------------------------------
  // OPCIONAL: descomente para retirar stake + recompensa
  // ----------------------------------------------------------------
  // console.log(`\n[ 7 ] Retirando stake + recompensa...`);
  // const retirarTx = await escrow.retirar();
  // await retirarTx.wait();
  // console.log(`      TX: ${retirarTx.hash}`);
  // const saldoFinal = await token.balanceOf(staker.address);
  // console.log(`      Saldo final: ${hre.ethers.formatEther(saldoFinal)} REPAIR`);

  console.log("");
  console.log("=".repeat(60));
  console.log("  Etapa 5 — stake concluído com sucesso!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
