/**
 * votar.js — Etapa 5
 * Demonstra o fluxo completo de governança na DAO:
 *   1. Cria proposta de alteração de parâmetro
 *   2. Vota na proposta
 *   3. Finaliza a proposta (após expiração, simulado via proposta de disputa)
 *
 * Execução:
 *   npx hardhat run scripts/votar.js --network sepolia
 *
 * Pré-requisito:
 *   - Ter pelo menos 1000 REPAIR em staking no Escrow (MIN_TOKENS_PROPOSTA)
 *   - Rode scripts/stake.js antes
 */

require("dotenv").config();
const hre = require("hardhat");

const ESCROW_ABI = [
  "function stakes(address staker) external view returns (uint256 valor, uint256 depositadoEm)",
];

const DAO_ABI = [
  "function proporAlteracaoParametro(string calldata descricao, string calldata parametro, uint256 novoValor) external returns (uint256)",
  "function votar(uint256 propostaId, bool aFavor) external",
  "function finalizarProposta(uint256 propostaId) external",
  "function propostas(uint256 id) external view returns (address proponente, string descricao, uint8 tipo, uint8 status, uint256 votosAFavor, uint256 votosContra, uint256 criadaEm, uint256 expiraEm)",
  "function poderDeVoto(address votante) external view returns (uint256)",
  "function totalPropostas() external view returns (uint256)",
  "function jaVotou(uint256 propostaId, address votante) external view returns (bool)",
];

const STATUS = ["Ativa", "Aprovada", "Rejeitada", "Executada"];

async function main() {
  const [votante] = await hre.ethers.getSigners();

  console.log("=".repeat(60));
  console.log("  RepairDAO — Etapa 5: Governança e Votação");
  console.log("=".repeat(60));
  console.log(`Votante: ${votante.address}`);
  console.log("");

  const escrow = new hre.ethers.Contract(process.env.ESCROW_ADDRESS, ESCROW_ABI, votante);
  const dao    = new hre.ethers.Contract(process.env.DAO_ADDRESS,    DAO_ABI,    votante);

  // 1. Verificar poder de voto
  const poder = await dao.poderDeVoto(votante.address);
  console.log(`[ 1 ] Poder de voto (stake no Escrow): ${hre.ethers.formatEther(poder)} REPAIR`);

  const MIN_PROPOSTA = hre.ethers.parseEther("1000");
  if (poder < MIN_PROPOSTA) {
    console.error(`      ERRO: mínimo de 1000 REPAIR em stake para propor.`);
    console.error(`      Execute scripts/stake.js primeiro.`);
    process.exitCode = 1;
    return;
  }
  console.log(`      Poder suficiente para criar proposta.`);
  console.log("");

  // 2. Criar proposta de alteração de parâmetro
  console.log(`[ 2 ] Criando proposta de alteração de parâmetro...`);
  const proporTx = await dao.proporAlteracaoParametro(
    "Aumentar taxa de protocolo de 2% para 3% para sustentar o tesouro",
    "TAXA_PROTOCOLO_BPS",
    300 // novo valor: 3%
  );
  await proporTx.wait();
  console.log(`      TX: ${proporTx.hash}`);

  const propostaId = await dao.totalPropostas();
  console.log(`      ID da proposta: ${propostaId}`);

  // 3. Consultar proposta criada
  const proposta = await dao.propostas(propostaId);
  const expiraEm = new Date(Number(proposta.expiraEm) * 1000).toLocaleString("pt-BR");
  console.log(`\n[ 3 ] Detalhes da proposta #${propostaId}:`);
  console.log(`      Proponente: ${proposta.proponente}`);
  console.log(`      Descrição:  ${proposta.descricao}`);
  console.log(`      Status:     ${STATUS[proposta.status]}`);
  console.log(`      Expira em:  ${expiraEm}`);
  console.log(`      Votos a favor: ${hre.ethers.formatEther(proposta.votosAFavor)} REPAIR`);
  console.log(`      Votos contra:  ${hre.ethers.formatEther(proposta.votosContra)} REPAIR`);

  // 4. Votar a favor
  console.log(`\n[ 4 ] Votando a FAVOR da proposta #${propostaId}...`);
  const votarTx = await dao.votar(propostaId, true);
  await votarTx.wait();
  console.log(`      TX: ${votarTx.hash}`);

  // 5. Consultar resultado atualizado
  const propostaAtualizada = await dao.propostas(propostaId);
  console.log(`\n[ 5 ] Resultado após votação:`);
  console.log(`      Votos a favor: ${hre.ethers.formatEther(propostaAtualizada.votosAFavor)} REPAIR`);
  console.log(`      Votos contra:  ${hre.ethers.formatEther(propostaAtualizada.votosContra)} REPAIR`);
  console.log(`      Status:        ${STATUS[propostaAtualizada.status]}`);

  console.log(`\n      A proposta pode ser finalizada após ${expiraEm}`);
  console.log(`      chamando: dao.finalizarProposta(${propostaId})`);

  // ----------------------------------------------------------------
  // OPCIONAL: descomente para finalizar (só funciona após 3 dias)
  // ----------------------------------------------------------------
  // console.log(`\n[ 6 ] Finalizando proposta...`);
  // const finalizarTx = await dao.finalizarProposta(propostaId);
  // await finalizarTx.wait();
  // const propostaFinal = await dao.propostas(propostaId);
  // console.log(`      Status final: ${STATUS[propostaFinal.status]}`);

  console.log("");
  console.log("=".repeat(60));
  console.log("  Etapa 5 — votação concluída com sucesso!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exitCode = 1;
});
