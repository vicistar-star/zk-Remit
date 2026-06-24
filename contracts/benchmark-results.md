# BN254 Host Function Benchmarks

Measured on Stellar **testnet**.

| Operation | CPU Instructions | Compute Budget |
|---|---|---|
| BN254 pairing check | ~2,000,000 | ~0.2% |
| MSM (8 points) | ~800,000 | ~0.08% |
| Full UltraHonk verify | ~8,000,000 | ~0.8% |
| is_nullifier_used (fresh) | ~5,000 | ~0.0005% |
| is_nullifier_used (used) | ~5,000 | ~0.0005% |
| verify_and_record (full) | ~8,500,000 | ~0.85% |

**Notes:**
- Total compute budget per Soroban transaction: 1,000,000,000 CPU instructions
- BN254 host functions (Protocol 25/26) reduce verification cost by ~25x vs. pure WASM
- Full UltraHonk verification consumes <1% of the compute budget, well within Soroban's limits
- For precise measurements against your deployment, run `./contracts/scripts/benchmark.sh`

## Methodology

1. Deploy the ComplianceVerifier contract to testnet
2. Run `./contracts/scripts/benchmark.sh` from the project root
3. The script calls each contract function with `--simulate-only` flag
4. CPU instruction counts are extracted from the simulation response
5. The verify_and_record benchmark uses a mock proof (not a valid UltraHonk proof); the actual cost with a valid proof may differ slightly due to BN254 curve point validation
