// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

interface IRepairToken {
    function balanceOf(address account) external view returns (uint256);
}

interface IRepairEscrow {
    function stakes(address staker) external view returns (uint256 valor, uint256 depositadoEm);
    function resolverDisputa(uint256 servicoId, bool favorDoTecnico) external;
}

/**
 * @title RepairDAO
 * @notice Governança simplificada do protocolo RepairDAO.
 *         Holders de REPAIR em staking propõem e votam em:
 *         - Alterações de parâmetros do protocolo
 *         - Resolução de disputas entre cliente e técnico
 *         O peso do voto é proporcional ao saldo em staking.
 */
contract RepairDAO is Ownable, ReentrancyGuard {

    // ---------------------------------------------------------------
    // Interfaces externas
    // ---------------------------------------------------------------

    IRepairToken  public repairToken;
    IRepairEscrow public repairEscrow;

    // ---------------------------------------------------------------
    // Parâmetros de governança
    // ---------------------------------------------------------------

    uint256 public constant DURACAO_VOTACAO      = 3 days;
    uint256 public constant MIN_TOKENS_PROPOSTA  = 1_000 * 10 ** 18;

    // ---------------------------------------------------------------
    // Enums
    // ---------------------------------------------------------------

    enum TipoProposta   { AlterarParametro, ResolverDisputa }
    enum StatusProposta { Ativa, Aprovada, Rejeitada, Executada }

    // ---------------------------------------------------------------
    // Structs separadas para evitar "stack too deep"
    // ---------------------------------------------------------------

    // Dados gerais da proposta
    struct PropostaBase {
        address proponente;
        string  descricao;
        TipoProposta  tipo;
        StatusProposta status;
        uint256 votosAFavor;
        uint256 votosContra;
        uint256 criadaEm;
        uint256 expiraEm;
    }

    // Dados específicos por tipo de proposta
    struct PropostaDetalhe {
        // Para ResolverDisputa
        uint256 servicoId;
        bool    favorDoTecnico;
        // Para AlterarParametro
        string  parametro;
        uint256 novoValor;
    }

    uint256 public totalPropostas;
    mapping(uint256 => PropostaBase)    public propostas;
    mapping(uint256 => PropostaDetalhe) public propostasDetalhe;

    // propostaId → endereço → já votou?
    mapping(uint256 => mapping(address => bool)) public jaVotou;

    // ---------------------------------------------------------------
    // Eventos
    // ---------------------------------------------------------------

    event PropostaCriada(
        uint256 indexed id,
        address proponente,
        TipoProposta tipo,
        string descricao
    );
    event VotoRegistrado(
        uint256 indexed propostaId,
        address votante,
        bool aFavor,
        uint256 peso
    );
    event PropostaFinalizada(uint256 indexed id, StatusProposta status);
    event PropostaExecutada(uint256 indexed id);

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    constructor(
        address initialOwner,
        address _repairToken,
        address _repairEscrow
    ) Ownable(initialOwner) {
        require(_repairToken  != address(0), "DAO: token invalido");
        require(_repairEscrow != address(0), "DAO: escrow invalido");
        repairToken  = IRepairToken(_repairToken);
        repairEscrow = IRepairEscrow(_repairEscrow);
    }

    // ---------------------------------------------------------------
    // Modificadores
    // ---------------------------------------------------------------

    modifier propostaAtiva(uint256 propostaId) {
        require(
            propostas[propostaId].status == StatusProposta.Ativa,
            "DAO: proposta nao esta ativa"
        );
        require(
            block.timestamp <= propostas[propostaId].expiraEm,
            "DAO: votacao encerrada"
        );
        _;
    }

    // ---------------------------------------------------------------
    // Poder de voto
    // ---------------------------------------------------------------

    /**
     * @notice Retorna o poder de voto: saldo de REPAIR em staking no Escrow.
     */
    function poderDeVoto(address votante) public view returns (uint256) {
        (uint256 valor, ) = repairEscrow.stakes(votante);
        return valor;
    }

    // ---------------------------------------------------------------
    // Criação de propostas
    // ---------------------------------------------------------------

    /**
     * @notice Cria uma proposta de alteração de parâmetro do protocolo.
     */
    function proporAlteracaoParametro(
        string calldata descricao,
        string calldata parametro,
        uint256 novoValor
    ) external returns (uint256) {
        require(
            poderDeVoto(msg.sender) >= MIN_TOKENS_PROPOSTA,
            "DAO: tokens em staking insuficientes"
        );

        totalPropostas++;

        propostas[totalPropostas] = PropostaBase({
            proponente:  msg.sender,
            descricao:   descricao,
            tipo:        TipoProposta.AlterarParametro,
            status:      StatusProposta.Ativa,
            votosAFavor: 0,
            votosContra: 0,
            criadaEm:    block.timestamp,
            expiraEm:    block.timestamp + DURACAO_VOTACAO
        });

        propostasDetalhe[totalPropostas] = PropostaDetalhe({
            servicoId:      0,
            favorDoTecnico: false,
            parametro:      parametro,
            novoValor:      novoValor
        });

        emit PropostaCriada(totalPropostas, msg.sender, TipoProposta.AlterarParametro, descricao);
        return totalPropostas;
    }

    /**
     * @notice Cria uma proposta de resolução de disputa.
     */
    function proporResolucaoDisputa(
        string calldata descricao,
        uint256 servicoId,
        bool favorDoTecnico
    ) external returns (uint256) {
        require(
            poderDeVoto(msg.sender) >= MIN_TOKENS_PROPOSTA,
            "DAO: tokens em staking insuficientes"
        );
        require(servicoId > 0, "DAO: servicoId invalido");

        totalPropostas++;

        propostas[totalPropostas] = PropostaBase({
            proponente:  msg.sender,
            descricao:   descricao,
            tipo:        TipoProposta.ResolverDisputa,
            status:      StatusProposta.Ativa,
            votosAFavor: 0,
            votosContra: 0,
            criadaEm:    block.timestamp,
            expiraEm:    block.timestamp + DURACAO_VOTACAO
        });

        propostasDetalhe[totalPropostas] = PropostaDetalhe({
            servicoId:      servicoId,
            favorDoTecnico: favorDoTecnico,
            parametro:      "",
            novoValor:      0
        });

        emit PropostaCriada(totalPropostas, msg.sender, TipoProposta.ResolverDisputa, descricao);
        return totalPropostas;
    }

    // ---------------------------------------------------------------
    // Votação
    // ---------------------------------------------------------------

    /**
     * @notice Registra o voto de um participante em uma proposta ativa.
     *         O peso do voto é o saldo em staking no momento da votação.
     */
    function votar(uint256 propostaId, bool aFavor)
        external
        propostaAtiva(propostaId)
    {
        require(!jaVotou[propostaId][msg.sender], "DAO: ja votou nesta proposta");

        uint256 peso = poderDeVoto(msg.sender);
        require(peso > 0, "DAO: nenhum token em staking para votar");

        jaVotou[propostaId][msg.sender] = true;

        if (aFavor) {
            propostas[propostaId].votosAFavor += peso;
        } else {
            propostas[propostaId].votosContra += peso;
        }

        emit VotoRegistrado(propostaId, msg.sender, aFavor, peso);
    }

    // ---------------------------------------------------------------
    // Finalização e execução
    // ---------------------------------------------------------------

    /**
     * @notice Finaliza uma proposta após o período de votação.
     *         Qualquer pessoa pode chamar após a expiração.
     */
    function finalizarProposta(uint256 propostaId) external {
        PropostaBase storage p = propostas[propostaId];
        require(p.status == StatusProposta.Ativa, "DAO: proposta nao esta ativa");
        require(block.timestamp > p.expiraEm, "DAO: votacao ainda em andamento");

        bool aprovada = p.votosAFavor > p.votosContra && p.votosAFavor > 0;
        p.status = aprovada ? StatusProposta.Aprovada : StatusProposta.Rejeitada;

        emit PropostaFinalizada(propostaId, p.status);
    }

    /**
     * @notice Executa uma proposta aprovada.
     *         Para disputas: chama resolverDisputa no Escrow.
     */
    function executarProposta(uint256 propostaId)
        external
        onlyOwner
        nonReentrant
    {
        PropostaBase storage p = propostas[propostaId];
        require(p.status == StatusProposta.Aprovada, "DAO: proposta nao aprovada");

        p.status = StatusProposta.Executada;

        if (p.tipo == TipoProposta.ResolverDisputa) {
            PropostaDetalhe memory d = propostasDetalhe[propostaId];
            repairEscrow.resolverDisputa(d.servicoId, d.favorDoTecnico);
        }

        emit PropostaExecutada(propostaId);
    }

    // ---------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------

    /**
     * @notice Retorna o resultado atual de uma proposta.
     */
    function resultadoProposta(uint256 propostaId)
        external
        view
        returns (
            uint256 aFavor,
            uint256 contra,
            StatusProposta status,
            bool expirada
        )
    {
        PropostaBase memory p = propostas[propostaId];
        return (
            p.votosAFavor,
            p.votosContra,
            p.status,
            block.timestamp > p.expiraEm
        );
    }

    /**
     * @notice Lista os IDs de todas as propostas ativas no momento.
     */
    function propostasAtivas() external view returns (uint256[] memory) {
        uint256 count = 0;
        for (uint256 i = 1; i <= totalPropostas; i++) {
            if (
                propostas[i].status == StatusProposta.Ativa &&
                block.timestamp <= propostas[i].expiraEm
            ) count++;
        }

        uint256[] memory ids = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 1; i <= totalPropostas; i++) {
            if (
                propostas[i].status == StatusProposta.Ativa &&
                block.timestamp <= propostas[i].expiraEm
            ) ids[idx++] = i;
        }
        return ids;
    }
}
