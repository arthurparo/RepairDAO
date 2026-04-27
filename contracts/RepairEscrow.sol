// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

interface IRepairToken {
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function mintReward(address to, uint256 amount) external;
}

interface IRepairNFT {
    function registrarServico(address tecnico, uint256 avaliacao) external;
}

/**
 * @title RepairEscrow
 * @notice Contrato central do RepairDAO.
 *         Gerencia pagamentos em escrow, staking de técnicos,
 *         recompensas ajustadas por oráculo e repasse ao tesouro da DAO.
 */
contract RepairEscrow is ReentrancyGuard, Ownable {

    // ---------------------------------------------------------------
    // Interfaces externas
    // ---------------------------------------------------------------

    IRepairToken public repairToken;
    IRepairNFT   public repairNFT;
    AggregatorV3Interface public priceFeed; // Feed ETH/USD da Chainlink

    // ---------------------------------------------------------------
    // Parâmetros do protocolo
    // ---------------------------------------------------------------

    // Taxa de protocolo: 2% (200 pontos base de 10000)
    uint256 public constant TAXA_PROTOCOLO_BPS = 200;
    uint256 public constant BPS_DENOMINADOR     = 10_000;

    // Taxa base de recompensa anual para stakers: 10%
    uint256 public constant RECOMPENSA_BASE_BPS = 1_000;

    // Endereço do tesouro da DAO
    address public tesouroDaDAO;

    // ---------------------------------------------------------------
    // Estrutura de serviço
    // ---------------------------------------------------------------

    enum StatusServico { Aberto, Concluido, Disputado, Cancelado }

    struct Servico {
        address cliente;
        address tecnico;
        uint256 valorREPAIR;   // Valor depositado em REPAIR
        uint256 valorUSD;      // Valor equivalente em USD (8 decimais, padrão Chainlink)
        StatusServico status;
        uint256 criadoEm;
    }

    uint256 public totalServicos;
    mapping(uint256 => Servico) public servicos;

    // ---------------------------------------------------------------
    // Staking
    // ---------------------------------------------------------------

    struct Stake {
        uint256 valor;
        uint256 depositadoEm;
    }

    mapping(address => Stake) public stakes;
    uint256 public totalStaked;

    // Tesouro acumulado disponível para distribuição aos stakers
    uint256 public tesouroPendente;

    // ---------------------------------------------------------------
    // Eventos
    // ---------------------------------------------------------------

    event ServicoCriado(uint256 indexed id, address cliente, address tecnico, uint256 valor);
    event ServicoConcluido(uint256 indexed id, uint256 valorTecnico, uint256 taxa);
    event ServicoDisputado(uint256 indexed id);
    event ServicoCancelado(uint256 indexed id);
    event StakeDepositado(address indexed staker, uint256 valor);
    event StakeRetirado(address indexed staker, uint256 valor, uint256 recompensa);
    event TesouroDefined(address indexed tesouro);

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    constructor(
        address initialOwner,
        address _repairToken,
        address _repairNFT,
        address _priceFeed,
        address _tesouro
    ) Ownable(initialOwner) {
        require(_repairToken != address(0), "Escrow: token invalido");
        require(_repairNFT   != address(0), "Escrow: NFT invalido");
        require(_priceFeed   != address(0), "Escrow: oracle invalido");
        require(_tesouro     != address(0), "Escrow: tesouro invalido");

        repairToken = IRepairToken(_repairToken);
        repairNFT   = IRepairNFT(_repairNFT);
        priceFeed   = AggregatorV3Interface(_priceFeed);
        tesouroDaDAO = _tesouro;
    }

    // ---------------------------------------------------------------
    // Oráculo Chainlink
    // ---------------------------------------------------------------

    /**
     * @notice Retorna o preço atual do ETH em USD (8 decimais).
     */
    function getPrecoETH() public view returns (uint256) {
        (
            ,
            int256 price,
            ,
            ,
        ) = priceFeed.latestRoundData();
        require(price > 0, "Escrow: preco invalido do oraculo");
        return uint256(price);
    }

    /**
     * @notice Converte um valor em REPAIR para USD usando o preço do ETH.
     *         Assumimos 1 REPAIR = 1 unidade da cotação ETH/USD como referência.
     *         Em produção, usaria um feed REPAIR/USD dedicado.
     */
    function converterParaUSD(uint256 valorREPAIR) public view returns (uint256) {
        uint256 precoETH = getPrecoETH(); // 8 decimais
        // valorREPAIR tem 18 decimais; precoETH tem 8 decimais
        // resultado em USD com 8 decimais
        return (valorREPAIR * precoETH) / 1e18;
    }

    // ---------------------------------------------------------------
    // Fluxo de serviço
    // ---------------------------------------------------------------

    /**
     * @notice Cliente cria um serviço e deposita REPAIR no escrow.
     * @param tecnico      Endereço do técnico contratado
     * @param valorREPAIR  Valor acordado em tokens REPAIR (com 18 decimais)
     */
    function criarServico(address tecnico, uint256 valorREPAIR)
        external
        nonReentrant
    {
        require(tecnico != address(0) && tecnico != msg.sender, "Escrow: tecnico invalido");
        require(valorREPAIR > 0, "Escrow: valor deve ser maior que zero");

        // Transfere tokens do cliente para este contrato (escrow)
        bool ok = repairToken.transferFrom(msg.sender, address(this), valorREPAIR);
        require(ok, "Escrow: transferencia falhou");

        uint256 valorUSD = converterParaUSD(valorREPAIR);

        totalServicos++;
        servicos[totalServicos] = Servico({
            cliente:      msg.sender,
            tecnico:      tecnico,
            valorREPAIR:  valorREPAIR,
            valorUSD:     valorUSD,
            status:       StatusServico.Aberto,
            criadoEm:     block.timestamp
        });

        emit ServicoCriado(totalServicos, msg.sender, tecnico, valorREPAIR);
    }

    /**
     * @notice Cliente confirma a conclusão do serviço e avalia o técnico.
     *         Libera o pagamento, desconta a taxa e atualiza o NFT de reputação.
     * @param servicoId  ID do serviço
     * @param avaliacao  Nota de 1 a 5
     */
    function confirmarServico(uint256 servicoId, uint256 avaliacao)
        external
        nonReentrant
    {
        Servico storage s = servicos[servicoId];
        require(msg.sender == s.cliente, "Escrow: apenas o cliente confirma");
        require(s.status == StatusServico.Aberto, "Escrow: servico nao esta aberto");
        require(avaliacao >= 1 && avaliacao <= 5, "Escrow: avaliacao invalida");

        s.status = StatusServico.Concluido;

        // Calcula taxa de protocolo (2%)
        uint256 taxa = (s.valorREPAIR * TAXA_PROTOCOLO_BPS) / BPS_DENOMINADOR;
        uint256 valorTecnico = s.valorREPAIR - taxa;

        // Repassa taxa ao tesouro da DAO
        tesouroPendente += taxa;
        bool okTesouro = repairToken.transfer(tesouroDaDAO, taxa);
        require(okTesouro, "Escrow: repasse ao tesouro falhou");

        // Paga o técnico
        bool okTecnico = repairToken.transfer(s.tecnico, valorTecnico);
        require(okTecnico, "Escrow: pagamento ao tecnico falhou");

        // Registra serviço e atualiza NFT de reputação
        repairNFT.registrarServico(s.tecnico, avaliacao);

        emit ServicoConcluido(servicoId, valorTecnico, taxa);
    }

    /**
     * @notice Cliente abre uma disputa para arbitragem pela DAO.
     */
    function abrirDisputa(uint256 servicoId) external {
        Servico storage s = servicos[servicoId];
        require(msg.sender == s.cliente, "Escrow: apenas o cliente abre disputa");
        require(s.status == StatusServico.Aberto, "Escrow: servico nao esta aberto");
        s.status = StatusServico.Disputado;
        emit ServicoDisputado(servicoId);
    }

    /**
     * @notice Owner (DAO) resolve uma disputa definindo o vencedor.
     * @param servicoId      ID do serviço em disputa
     * @param favorDoTecnico true = técnico recebe; false = cliente recebe reembolso
     */
    function resolverDisputa(uint256 servicoId, bool favorDoTecnico)
        external
        onlyOwner
        nonReentrant
    {
        Servico storage s = servicos[servicoId];
        require(s.status == StatusServico.Disputado, "Escrow: servico nao esta em disputa");

        s.status = StatusServico.Concluido;

        address destinatario = favorDoTecnico ? s.tecnico : s.cliente;
        bool ok = repairToken.transfer(destinatario, s.valorREPAIR);
        require(ok, "Escrow: transferencia da disputa falhou");

        if (favorDoTecnico) {
            repairNFT.registrarServico(s.tecnico, 3); // nota neutra em disputa
        }
    }

    // ---------------------------------------------------------------
    // Staking
    // ---------------------------------------------------------------

    /**
     * @notice Deposita tokens REPAIR em staking para receber recompensas.
     */
    function depositar(uint256 valor) external nonReentrant {
        require(valor > 0, "Escrow: valor invalido");

        // Se já tem stake, coleta recompensa antes de adicionar mais
        if (stakes[msg.sender].valor > 0) {
            _coletarRecompensa(msg.sender);
        }

        bool ok = repairToken.transferFrom(msg.sender, address(this), valor);
        require(ok, "Escrow: transferencia falhou");

        stakes[msg.sender].valor += valor;
        stakes[msg.sender].depositadoEm = block.timestamp;
        totalStaked += valor;

        emit StakeDepositado(msg.sender, valor);
    }

    /**
     * @notice Retira tokens em staking junto com as recompensas acumuladas.
     */
    function retirar() external nonReentrant {
        Stake storage s = stakes[msg.sender];
        require(s.valor > 0, "Escrow: nenhum stake encontrado");

        uint256 recompensa = _calcularRecompensa(msg.sender);
        uint256 valorStake = s.valor;

        totalStaked -= valorStake;
        s.valor = 0;
        s.depositadoEm = 0;

        // Devolve o stake original
        bool okStake = repairToken.transfer(msg.sender, valorStake);
        require(okStake, "Escrow: devolucao do stake falhou");

        // Minta a recompensa (tokens novos, controlados pelo token contract)
        if (recompensa > 0) {
            repairToken.mintReward(msg.sender, recompensa);
        }

        emit StakeRetirado(msg.sender, valorStake, recompensa);
    }

    /**
     * @notice Calcula a recompensa acumulada de um staker.
     *         A taxa base (10% ao ano) é multiplicada pelo preço do ETH
     *         para ajustar em períodos de alta volatilidade.
     */
    function _calcularRecompensa(address staker) internal view returns (uint256) {
        Stake memory s = stakes[staker];
        if (s.valor == 0) return 0;

        uint256 tempoStaked = block.timestamp - s.depositadoEm; // em segundos
        uint256 precoETH = getPrecoETH(); // 8 decimais

        // Multiplicador baseado no preço do ETH:
        // Se ETH > $2000, multiplicador = 1.5x; senão = 1x
        uint256 multiplicador = precoETH > 200_000_000_000 ? 150 : 100; // base 100

        // Recompensa = valor * taxa_base * tempo / (1 ano em segundos) * multiplicador
        uint256 recompensa = (s.valor * RECOMPENSA_BASE_BPS * tempoStaked * multiplicador)
            / (BPS_DENOMINADOR * 365 days * 100);

        return recompensa;
    }

    function _coletarRecompensa(address staker) internal {
        uint256 recompensa = _calcularRecompensa(staker);
        stakes[staker].depositadoEm = block.timestamp;
        if (recompensa > 0) {
            repairToken.mintReward(staker, recompensa);
        }
    }

    // ---------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------

    function recompensaPendente(address staker) external view returns (uint256) {
        return _calcularRecompensa(staker);
    }

    function consultarServico(uint256 servicoId)
        external
        view
        returns (Servico memory)
    {
        return servicos[servicoId];
    }
}
