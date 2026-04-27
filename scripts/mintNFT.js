/**
 * mintNFT.js — Etapa 5
 * Demonstra o fluxo completo que resulta no mint do NFT de reputação:
 *   1. Cliente aprova tokens para o Escrow
 *   2. Cliente cria o serviço (criarServico)
 *   3. Cliente confirma o serviço com avaliação (confirmarServico)
 *   4. Escrow paga o técnico e chama registrarServico → NFT é mintado
 *
 * Execução:
 *   npx hardhat run scripts/mintNFT.js --network sepolia
 *
 * Pré-requisitos:
 *   - TECNICO_ADDRESS no .env com um endereço diferente do cliente
 *   - Cliente deve ter saldo de REPAIR tokens
 */

require("dotenv").config();
const hre = require("hardhat");

const TOKEN_ABI = [
  "function approve(address spender, uint256 amount) external returns (bool)",
  "function balanceOf(address account) external view returns (uint256)",
];

const ESCROW_ABI = [
  "function criarServico(address tecnico, uint256 valorREPAIR) external",
  "function confirmarServico(uint256 servicoId, uint256 avaliacao) external",
  "function totalServicos() external view returns (uint256)",
];

const NFT_ABI = [
  "function tokenDoTecnico(address tecnico) external view returns (uint256)",
  "function reputacaoPorToken(uint256 tokenId) external view returns (uint256 totalServicos, uint256 somaAvaliacoes, uint256 dataPrimeiroServico)",
  "function mediaAvaliacoes(address tecnico) external view returns (uint256)",
];

async function main() {
  const [cliente] = await hre.ethers.getSigners();

  // Endereço do técnico — deve ser diferente do cliente
  // Defina TECNICO_ADDRESS no .env ou substitua abaixo
  const tecnico = process.env.TECNICO_ADDRESS;
  if (!tecnico) {
    console.error("ERRO: defina TECNICO_ADDRESS no .env (endereço diferente do cliente)");
    process.exitCode = 1;
    return;
  }

  console.log("=".repeat(60));
  console.log("  RepairDAO — Etapa 5: Fluxo de Serviço + Mint de NFT");
  console.log("=".repeat(60));
  console.log(`Cliente:  ${cliente.address}`);
  console.log(`Técnico:  ${tecnico}`);
  console.log("");

  const token  = new hre.ethers.Contract(process.env.TOKEN_ADDRESS,  TOKEN_ABI,  cliente);
  const escrow = new hre.ethers.Contract(process.env.ESCROW_ADDRESS, ESCROW_ABI, cliente);
  const nft    = new hre.ethers.Contract(process.env.NFT_ADDRESS,    NFT_ABI,    cliente);

  const valorServico = hre.ethers.parseEther("10"); // 10 REPAIR

  // 1. Verificar saldo
  const saldo = await token.balanceOf(cliente.address);
  console.log(`[ 1 ] Saldo do cliente: ${hre.ethers.formatEther(saldo)} REPAIR`);
  if (saldo < valorServico) {
    console.error("      ERRO: saldo insuficiente (mínimo 10 REPAIR).");
    process.exitCode = 1;
    return;
  }

  // 2. Aprovar tokens para o Escrow
  console.log(`[ 2 ] Aprovando 10 REPAIR para o Escrow...`);
  const approveTx = await token.approve(process.env.ESCROW_ADDRESS, valorServico);
  await approveTx.wait();
  console.log(`      TX: ${approveTx.hash}`);

  // 3. Criar serviço
  console.log(`[ 3 ] Criando serviço...`);
  const criarTx = await escrow.criarServico(tecnico, valorServico);
  await criarTx.wait();
  console.log(`      TX: ${criarTx.hash}`);

  const servicoId = await escrow.totalServicos();
  console.log(`      ID do serviço: ${servicoId}`);

  // 4. Confirmar serviço com avaliação 5 estrelas
  console.log(`[ 4 ] Confirmando serviço #${servicoId} com avaliação 5/5...`);
  const confirmarTx = await escrow.confirmarServico(servicoId, 5);
  await confirmarTx.wait();
  console.log(`      TX: ${confirmarTx.hash}`);

  // 5. Verificar NFT mintado
  console.log(`[ 5 ] Verificando NFT de reputação do técnico...`);
  const tokenId = await nft.tokenDoTecnico(tecnico);
  if (tokenId > 0n) {
    const rep   = await nft.reputacaoPorToken(tokenId);
    const media = await nft.mediaAvaliacoes(tecnico);
    console.log(`      Token ID:         ${tokenId}`);
    console.log(`      Total serviços:   ${rep.totalServicos}`);
    console.log(`      Média avaliações: ${media}/5`);
  } else {
    console.log("      NFT não encontrado para este técnico.");
  }

  console.log("");
  console.log("=".repeat(60));
  console.log("  Etapa 5 — mintNFT concluído com sucesso!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
