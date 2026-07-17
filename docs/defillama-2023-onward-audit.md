# DefiLlama hacks audit: 2023 onward

This port was reconciled against the official `https://api.llama.fi/hacks` dataset on 2026-07-17,
not against project names alone. The snapshot contained 295 Solidity/Vyper rows dated 2023 or later:
53 in 2023, 60 in 2024, 71 in 2025, and 111 in 2026.

## Scope boundary

An incident is in scope when its root cause is a permissionless EVM contract path that Foundry can
execute against historical state. The audit excludes stolen or leaked private keys, social
engineering and malware, compromised front ends, address poisoning, rugs or intentional owner
backdoors, and drains whose root cause is possession of an admin, signer, validator, or multisig
authority. A public transaction made with stolen authority does not turn that incident into a
permissionless smart-contract exploit.

EVM-compatible networks are included when an archive RPC can reproduce their contract execution.
Hedera is EVM-compatible. For Bonzo Lend, the standard EVM EIP-197 verifier flaw reproduces, while
the subsequent Hedera Token Service transfers use a native precompile that ordinary Foundry does
not emulate. zkSync EraVM-specific and other non-EVM execution paths are outside this Foundry port.

## Reproductions added

| Date | DefiLlama incident | Repo reproduction | Reproduced result |
| --- | --- | --- | --- |
| 2023-06-14 | Tropykus RSK | `src/test/2023-06/Tropykus_exp.sol` | 96,963.476976399313380169 DOC |
| 2024-02-22 | Tectonic | `src/test/2024-02/Tectonic_exp.sol` | 5,834.600835 USDC component |
| 2024-03-20 | Dolomite | `src/test/2024-03/Dolomite_exp.sol` | 1,158,297.126131 USDC |
| 2024-12-04 | Vestra DAO | `src/test/2024-12/VestraDAO_exp.sol` | 102.254469641874364934 ETH |
| 2024-12-29 | Fegex / FEG Bridge | `src/test/2024-12/FEGBridge_exp.sol` | 713.452420992235717355 BNB |
| 2025-04-14 | KiloEx | `src/test/2025-04/KiloEx_exp.sol` | 3,125,495.724597 USDC |
| 2025-04-22 | Bitcoin Mission | `src/test/2025-04/BitcoinMission_exp.sol` | 1,441.658811 USDT representative tx |
| 2025-05-26 | Dexodus Finance | `src/test/2025-05/Dexodus_exp.sol` | 113.428616237718218074 ETH |
| 2025-09-02 | Bunni V2 | `src/test/2025-09/BunniV2_exp.sol` | 2,550,934.394117 aUSDC/aUSDT representative tx |
| 2025-10-09 | Astera.fi | `src/test/2025-10/Astera_exp.sol` | 442,856.704 asUSD + 12.55M LINEA + 18.94 WETH |
| 2025-12-04 | USPD | `src/test/2025-12/USPD_exp.sol` | 302,908.856746 USDC component |
| 2025-12-16 | FutureSwap | `src/test/2025-12/FutureSwap_exp.sol` | same-tx snapshot vote and flash repayment |
| 2025-12-16 | Yearn Finance | `src/test/2025-12/YearnFulcrum_exp.sol` | 6,845.147604 USDC component |
| 2026-04-12 | Hyperbridge | `src/test/2026-04/Hyperbridge_exp.sol` | forged state proof changes admin and mints DOT |
| 2026-06-01 | Gnosis Pay | `src/test/2026-06/GnosisPay_exp.sol` | forged ERC-1271 authorization queues withdrawal |
| 2026-07-02 | Hinkal | `src/test/2026-07/Hinkal_exp.sol` | proofless deposit accepted |
| 2026-07-11 | Bonzo Lend | `src/test/2026-07/BonzoLend_exp.sol` | zero-signature oracle update accepted |
| 2026-07-13 | Chi Protocol | `src/test/2026-07/ChiProtocol_exp.sol` | reserve accounting inflated |
| 2026-07-14 | Drips Network | `src/test/2026-07/DripsNetwork_exp.sol` | signed-width math error reproduced |
| 2026-07-14 | BarnBridge | `src/test/2026-07/BarnBridge_exp.sol` | governance-controlled approval sweep reproduced |

The Bitcoin Mission source compiles and encodes the historical transaction, but its April 2025
Arbitrum state requires an archive endpoint; the public Arbitrum endpoints available during this
audit had already pruned that state. The other additions above were executed against their
historical forks.

## Name reconciliation examples

DefiLlama names frequently differ from this repository's filenames, so filename matching alone
overstates the gap. Examples confirmed during the audit include Arena SocialFi → `StarsArena_exp.sol`,
DEUS Finance → `DEI_exp.sol`, Super Sushi Samurai → `SSS_exp.sol`, Bungee →
`SocketGateway_exp.sol`, LeadBlock's Morpho Blue Market → `MorphoBlue_exp.sol`, Gamma →
`Gamma_exp.sol`, Convergence → `Convergence_exp.sol`, Dough → `DoughFina_exp.sol`, Sonne →
`Sonne_exp.sol`, PrismaLST → `Prisma_exp.sol`, Mobius → `MBUToken_exp.sol`, and GMX V1 Perps →
`gmx_exp.sol`.

## Representative exclusions

- Keep3r Network, RocketSwap Base, Poly Network, OKX DEX, Orbit Bridge, Seedify, and similar rows:
  private-key, signer, or multisig compromise.
- Florence Finance: address poisoning rather than a vulnerable contract path.
- Holograph, Nexera's BeaverTail incident, and other insider/malware authority takeovers: no
  permissionless exploit root cause.
- Ostium: the public PoC depends on authorized oracle signatures.
- Kelp: available PoCs emulate a trusted LayerZero settlement and do not reproduce the upstream
  root cause.
- EraLend and other EraVM-specific incidents: not executable by an ordinary Foundry EVM fork.
- LendHub on HECO: no usable historical archive endpoint was available for the required state.
