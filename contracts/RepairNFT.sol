// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RepairNFT
 * @notice NFT ERC-721 de reputação do protocolo RepairDAO.
 *         Cada técnico recebe exatamente um NFT ao concluir seu primeiro serviço.view
 *         O NFT é atualizado a cada novo serviço confirmado — nunca transferível.
 */
contract RepairNFT is ERC721, Ownable {

    // Próximo ID a ser mintado
    uint256 private _nextTokenId;

    // Endereço do contrato de Escrow — único autorizado a mintar e atualizar
    address public escrowContract;

    // Estrutura que armazena a reputação de cada técnico
    struct Reputacao {
        uint256 totalServicos;    // Quantidade de serviços concluídos
        uint256 somaAvaliacoes;   // Soma de todas as notas recebidas (1–5)
        uint256 dataPrimeiroServico; // Timestamp do primeiro serviço
    }

    // tokenId → dados de reputação
    mapping(uint256 => Reputacao) public reputacaoPorToken;

    // endereço do técnico → tokenId (0 = não tem NFT ainda)
    mapping(address => uint256) public tokenDoTecnico;

    // Eventos
    event NFTEmitido(address indexed tecnico, uint256 tokenId);
    event ReputacaoAtualizada(
        address indexed tecnico,
        uint256 tokenId,
        uint256 totalServicos,
        uint256 mediaAvaliacoes
    );
    event EscrowContractSet(address indexed escrow);

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    constructor(address initialOwner)
        ERC721("RepairDAO Reputation", "REPNFT")
        Ownable(initialOwner)
    {}

    // ---------------------------------------------------------------
    // Modificadores
    // ---------------------------------------------------------------

    modifier apenasEscrow() {
        require(
            msg.sender == escrowContract,
            "RepairNFT: apenas o escrow pode chamar"
        );
        _;
    }

    // ---------------------------------------------------------------
    // Configuração
    // ---------------------------------------------------------------

    /**
     * @notice Define o endereço do contrato de Escrow.
     *         Só pode ser chamado pelo owner e apenas uma vez.
     */
    function setEscrowContract(address _escrow) external onlyOwner {
        require(_escrow != address(0), "RepairNFT: endereco invalido");
        require(escrowContract == address(0), "RepairNFT: escrow ja definido");
        escrowContract = _escrow;
        emit EscrowContractSet(_escrow);
    }

    // ---------------------------------------------------------------
    // Mint e atualização (apenas Escrow)
    // ---------------------------------------------------------------

    /**
     * @notice Registra a conclusão de um serviço para um técnico.
     *         Se for o primeiro serviço, emite o NFT automaticamente.
     *         Caso contrário, apenas atualiza a reputação existente.
     * @param tecnico   Endereço do técnico
     * @param avaliacao Nota dada pelo cliente (1 a 5)
     */
    function registrarServico(address tecnico, uint256 avaliacao)
        external
        apenasEscrow
    {
        require(avaliacao >= 1 && avaliacao <= 5, "RepairNFT: avaliacao invalida");

        uint256 tokenId = tokenDoTecnico[tecnico];

        // Primeiro serviço: minta o NFT
        if (tokenId == 0) {
            _nextTokenId++;
            tokenId = _nextTokenId;
            tokenDoTecnico[tecnico] = tokenId;
            _mint(tecnico, tokenId);

            reputacaoPorToken[tokenId] = Reputacao({
                totalServicos: 0,
                somaAvaliacoes: 0,
                dataPrimeiroServico: block.timestamp
            });

            emit NFTEmitido(tecnico, tokenId);
        }

        // Atualiza reputação
        reputacaoPorToken[tokenId].totalServicos += 1;
        reputacaoPorToken[tokenId].somaAvaliacoes += avaliacao;

        uint256 media = reputacaoPorToken[tokenId].somaAvaliacoes
            / reputacaoPorToken[tokenId].totalServicos;

        emit ReputacaoAtualizada(tecnico, tokenId, reputacaoPorToken[tokenId].totalServicos, media);
    }

    // ---------------------------------------------------------------
    // Consultas
    // ---------------------------------------------------------------

    /**
     * @notice Retorna a média de avaliações de um técnico (0 se não tiver NFT).
     */
    function mediaAvaliacoes(address tecnico) external view returns (uint256) {
        uint256 tokenId = tokenDoTecnico[tecnico];
        if (tokenId == 0) return 0;
        Reputacao memory r = reputacaoPorToken[tokenId];
        if (r.totalServicos == 0) return 0;
        return r.somaAvaliacoes / r.totalServicos;
    }

    /**
     * @notice Retorna o total de serviços concluídos por um técnico.
     */
    function totalServicos(address tecnico) external view returns (uint256) {
        uint256 tokenId = tokenDoTecnico[tecnico];
        if (tokenId == 0) return 0;
        return reputacaoPorToken[tokenId].totalServicos;
    }

    // ---------------------------------------------------------------
    // Bloqueio de transferência
    // ---------------------------------------------------------------

    /**
     * @notice Impede qualquer transferência do NFT.
     *         A reputação é intransferível — pertence ao técnico para sempre.
     */
    function transferFrom(address, address, uint256)
        public
        pure
        override
    {
        revert("RepairNFT: NFT de reputacao e intransferivel");
    }

    function safeTransferFrom(address, address, uint256, bytes memory)
        public
        pure
        override
    {
        revert("RepairNFT: NFT de reputacao e intransferivel");
    }
}
