// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title RepairToken
 * @notice Token ERC-20 do protocolo RepairDAO.
 *         Usado como moeda de pagamento, staking e voto na governança.
 */
contract RepairToken is ERC20, Ownable {

    // Endereço do contrato de Escrow — único autorizado a mintar recompensas
    address public escrowContract;

    // Supply máximo: 10 milhões de tokens
    uint256 public constant MAX_SUPPLY = 10_000_000 * 10 ** 18;

    // Evento emitido quando o endereço do escrow é definido
    event EscrowContractSet(address indexed escrow);

    // ---------------------------------------------------------------
    // Constructor
    // ---------------------------------------------------------------

    /**
     * @param initialOwner  Endereço do dono inicial (quem faz o deploy)
     * @param initialSupply Quantidade mintada para o dono no deploy
     *                      (em tokens inteiros, ex: 1000000 = 1 milhão)
     */
    constructor(
        address initialOwner,
        uint256 initialSupply
    ) ERC20("RepairToken", "REPAIR") Ownable(initialOwner) {
        require(
            initialSupply * 10 ** 18 <= MAX_SUPPLY,
            "RepairToken: supply inicial excede o maximo"
        );
        // Minta o supply inicial para o dono
        _mint(initialOwner, initialSupply * 10 ** 18);
    }

    // ---------------------------------------------------------------
    // Configuração
    // ---------------------------------------------------------------

    /**
     * @notice Define o endereço do contrato de Escrow.
     *         Só pode ser chamado pelo owner e apenas uma vez.
     */
    function setEscrowContract(address _escrow) external onlyOwner {
        require(_escrow != address(0), "RepairToken: endereco invalido");
        require(escrowContract == address(0), "RepairToken: escrow ja definido");
        escrowContract = _escrow;
        emit EscrowContractSet(_escrow);
    }

    // ---------------------------------------------------------------
    // Mint controlado
    // ---------------------------------------------------------------

    /**
     * @notice Minta tokens de recompensa para stakers.
     *         Só pode ser chamado pelo contrato de Escrow.
     */
    function mintReward(address to, uint256 amount) external {
        require(
            msg.sender == escrowContract,
            "RepairToken: apenas o escrow pode mintar"
        );
        require(
            totalSupply() + amount <= MAX_SUPPLY,
            "RepairToken: mintaria acima do supply maximo"
        );
        _mint(to, amount);
    }
}
