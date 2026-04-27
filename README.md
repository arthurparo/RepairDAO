# RepairDAO ⚙️

> Protocolo Web3 descentralizado para marketplace de serviços técnicos com reputação portável via NFT, escrow automatizado e governança DAO na blockchain Ethereum.

![Solidity](https://img.shields.io/badge/Solidity-0.8.28-363636?logo=solidity)
![Hardhat](https://img.shields.io/badge/Hardhat-2.22-yellow?logo=ethereum)
![OpenZeppelin](https://img.shields.io/badge/OpenZeppelin-v5-4E5EE4?logo=openzeppelin)
![Network](https://img.shields.io/badge/Network-Sepolia-blue)
![License](https://img.shields.io/badge/License-MIT-green)

---

## Visão Geral

O **RepairDAO** resolve três problemas estruturais das plataformas centralizadas de serviços (como GetNinjas):

| Problema | Solução |
|---|---|
| Técnico paga sem garantia de recebimento | Pagamento em escrow liberado só após confirmação |
| Reputação presa na plataforma | NFT ERC-721 soulbound portável, de propriedade do técnico |
| Taxas e regras unilaterais | Governança DAO com votação proporcional ao stake |

---

## Contratos

| Contrato | Padrão | Endereço (Sepolia) |
|---|---|---|
| `RepairToken` | ERC-20 | [`0xc57A...ff7`](https://sepolia.etherscan.io/address/0xc57AFe0D023c016a00fAAaC1F4E4068b39891ff7) |
| `RepairNFT` | ERC-721 Soulbound | [`0xF40F...bc7`](https://sepolia.etherscan.io/address/0xF40F843aabB16f7781be1090594A157C32A10bc7) |
| `RepairEscrow` | — | [`0xD0c9...b55`](https://sepolia.etherscan.io/address/0xD0c9f72a98d28eF6259541e4cDb8ccc2Fb29ab55) |
| `RepairDAO` | — | [`0x44ad...eC`](https://sepolia.etherscan.io/address/0x44ad016590bf6873E2cf89eA98bd1424cF7854eC) |

---

## Arquitetura
