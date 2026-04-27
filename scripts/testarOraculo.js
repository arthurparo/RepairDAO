/**
 * testarOraculo.js
 * Etapa 4 — Demonstração da integração com o oráculo Chainlink ETH/USD
 *
 * Execução (sem contrato deployado):
 *   npx hardhat run scripts/testarOraculo.js --network sepolia
 *
 * Execução (com contrato deployado):
 *   ESCROW_ADDRESS=0x... npx hardhat run scripts/testarOraculo.js --network sepolia
 */

require("dotenv").config();
const hre = require("hardhat");

// Endereço do feed Chainlink ETH/USD na Sepolia
const CHAINLINK_FEED = "0x694AA1769357215DE4FAC081bf1f309aDC325306";

// ABI mínima do AggregatorV3Interface
const AGGREGATOR_ABI = [
  "function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)",
  "function decimals() external view returns (uint8)",
  "function description() external view returns (string)",
];

// ABI mínima do RepairEscrow (funções do oráculo)
const ESCROW_ABI = [
  "function getPrecoETH() external view returns (uint256)",
  "function converterParaUSD(uint256 valorREPAIR) external view returns (uint256)",
  "function recompensaPendente(address staker) external view returns (uint256)",
];

async function main() {
  const [signer] = await hre.ethers.getSigners();
  const network = hre.network.name;

  console.log("=".repeat(60));
  console.log("  RepairDAO — Teste de Integração com Oráculo Chainlink");
  console.log("=".repeat(60));
  console.log(`Rede:     ${network}`);
  console.log(`Carteira: ${signer.address}`);
  console.log("");

  // ----------------------------------------------------------------
  // 1. Leitura direta do feed Chainlink
  // ----------------------------------------------------------------
  console.log("[ 1 ] Consultando feed Chainlink ETH/USD diretamente...");
  console.log(`      Endereço do feed: ${CHAINLINK_FEED}`);

  const feed = new hre.ethers.Contract(CHAINLINK_FEED, AGGREGATOR_ABI, signer);

  const decimals    = await feed.decimals();
  const description = await feed.description();
  const { answer, updatedAt, roundId } = await feed.latestRoundData();

  const precoETH    = Number(answer) / 10 ** Number(decimals);
  const atualizadoEm = new Date(Number(updatedAt) * 1000).toLocaleString("pt-BR");

  console.log(`      Descrição:  ${description}`);
  console.log(`      Round ID:   ${roundId}`);
  console.log(`      Preço ETH:  $ ${precoETH.toFixed(2)} USD`);
  console.log(`      Atualizado: ${atualizadoEm}`);
  console.log(`      Decimais:   ${decimals}`);
  console.log("");

  // ----------------------------------------------------------------
  // 2. Simulação da lógica de multiplicador do RepairEscrow
  // ----------------------------------------------------------------
  console.log("[ 2 ] Simulando lógica de recompensa do RepairEscrow...");

  const LIMIAR_USD    = 2000;
  const TAXA_BASE     = 10;  // 10% ao ano (RECOMPENSA_BASE_BPS = 1000 / BPS_DENOMINADOR = 10000)
  const MULTIPLICADOR = precoETH > LIMIAR_USD ? 1.5 : 1.0;
  const TAXA_EFETIVA  = TAXA_BASE * MULTIPLICADOR;

  console.log(`      Preço ETH > $${LIMIAR_USD}? ${precoETH > LIMIAR_USD ? "SIM → multiplicador 1.5x" : "NÃO → multiplicador 1.0x"}`);
  console.log(`      Taxa efetiva de staking:    ${TAXA_EFETIVA}% ao ano`);

  // Exemplo: 1000 REPAIR em stake por 30 dias
  const STAKE_EXEMPLO = 1000;
  const DIAS          = 30;
  const recompensa30d = STAKE_EXEMPLO * (TAXA_EFETIVA / 100) * (DIAS / 365);
  console.log(`\n      Exemplo: ${STAKE_EXEMPLO} REPAIR em stake por ${DIAS} dias`);
  console.log(`      → Recompensa estimada: ${recompensa30d.toFixed(4)} REPAIR`);
  console.log("");

  // ----------------------------------------------------------------
  // 3. Teste via contrato RepairEscrow deployado (opcional)
  // ----------------------------------------------------------------
  const escrowAddress = process.env.ESCROW_ADDRESS;

  if (escrowAddress) {
    console.log("[ 3 ] Testando via contrato RepairEscrow deployado...");
    console.log(`      Endereço: ${escrowAddress}`);

    const escrow = new hre.ethers.Contract(escrowAddress, ESCROW_ABI, signer);

    const precoOnchain = await escrow.getPrecoETH();
    console.log(`      getPrecoETH() raw:   ${precoOnchain.toString()}`);
    console.log(`      getPrecoETH() USD:   $ ${(Number(precoOnchain) / 1e8).toFixed(2)}`);

    // Converte 100 REPAIR (18 decimais) para USD
    const cemREPAIR = hre.ethers.parseEther("100");
    const valorUSD  = await escrow.converterParaUSD(cemREPAIR);
    console.log(`      converterParaUSD(100 REPAIR): ${valorUSD.toString()} (8 dec)`);
    console.log(`      = $ ${(Number(valorUSD) / 1e8).toFixed(4)} USD`);
  } else {
    console.log("[ 3 ] Contrato ainda não deployado.");
    console.log("      Após o deploy (Etapa 6), rode:");
    console.log("      $env:ESCROW_ADDRESS='0xSEU_ENDERECO'; npx hardhat run scripts/testarOraculo.js --network sepolia");
  }

  console.log("");
  console.log("=".repeat(60));
  console.log("  Etapa 4 concluída — oráculo Chainlink integrado e validado");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
