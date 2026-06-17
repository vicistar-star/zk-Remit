// Build complete test data for the zkremit compliance circuit
// Uses pre-computed poseidon2 values from Noir

import { secp256k1 } from '@noble/curves/secp256k1.js';
import { poseidon2 } from 'poseidon-lite';
import { writeFileSync } from 'fs';

// Output from Noir hash helper (as negative-positive BN254 field elements)
// BN254 field modulus
const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function toFieldHex(n) {
  const val = n < 0n ? P + n : n;
  return '0x' + val.toString(16).padStart(64, '0');
}

function toFieldString(n) {
  const val = n < 0n ? P + n : n;
  return '"' + val.toString() + '"';  // Will use decimal string for Field
}

// Pre-computed poseidon2 hashes from Noir
const credentialHash = -4402511220242691388006346689087889783404163369740921854167015185592014871560n;
const credentialMsg = -3877856754960847370737454949585186066356095934866944696566545921286626159182n;
const nullifier = 1357950050555029929921390988943786518908957045138448594399398990097994072485n;
const issuerPubkeyHash = 2336791372758744260233576627453690259513827693686905825560323877274125089771n;
const jurisdictionLeaf = 8744438042687900322886356860697131572612840012928336951975962661506324136404n;

console.log('=== Hash Outputs ===');
console.log('credential_hash:', toFieldHex(credentialHash));
console.log('credential_msg:', toFieldHex(credentialMsg));
console.log('nullifier:', toFieldHex(nullifier));
console.log('issuer_pubkey_hash:', toFieldHex(issuerPubkeyHash));
console.log('jurisdiction_leaf:', toFieldHex(jurisdictionLeaf));

// Convert credential_msg Field to 32 bytes big-endian for signing
function fieldToBytes32(field) {
  const val = field < 0n ? P + field : field;
  const hex = val.toString(16).padStart(64, '0');
  return new Uint8Array(hex.match(/.{2}/g).map(b => parseInt(b, 16)));
}

const msgBytes = fieldToBytes32(credentialMsg);
console.log('\n=== Message bytes for signing ===');
console.log('0x' + Buffer.from(msgBytes).toString('hex'));

// Generate deterministic secp256k1 keypair using a fixed seed
const PRIVATE_KEY = new Uint8Array(32);
// Use a fixed seed for determinism
const seed = new Uint8Array([0x6b, 0x8d, 0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e,
                             0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e,
                             0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e,
                             0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e, 0x6c, 0x0e]);

// Harden the seed into a valid private key
const privateKey = secp256k1.utils.normPrivateKeyToScalar(seed);
const pubKey = secp256k1.getPublicKey(privateKey, false); // Uncompressed: 0x04 || X || Y
const pubKeyX = pubKey.slice(1, 33); // bytes 1-32
const pubKeyY = pubKey.slice(33, 65); // bytes 33-64

console.log('\n=== Keypair ===');
console.log('private_key_hex:', Buffer.from(privateKey).toString('hex'));
console.log('pubkey_x:', '[' + [...pubKeyX].join(', ') + ']');
console.log('pubkey_y:', '[' + [...pubKeyY].join(', ') + ']');

// Sign the credential message (prehash=false: sign msgBytes directly, not SHA256(msgBytes))
// Noir's ecdsa_secp256k1::verify_signature uses the message hash as-is (no internal hashing)
const sigBytes = secp256k1.sign(msgBytes, privateKey, { prehash: false, lowS: true });
const sigR = BigInt('0x' + Buffer.from(sigBytes.slice(0, 32)).toString('hex'));
const sigS = BigInt('0x' + Buffer.from(sigBytes.slice(32, 64)).toString('hex'));

console.log('\n=== Signature ===');
console.log('signature_r:', '0x' + sigR.toString(16).padStart(64, '0'));
console.log('signature_s:', '0x' + sigS.toString(16).padStart(64, '0'));
console.log('signature bytes [' + [...sigBytes].join(', ') + ']');

// Verify the signature (prehash=false: verify msgBytes directly)
const verified = secp256k1.verify(sigBytes, msgBytes, pubKey, { prehash: false });
console.log('Signature verified:', verified);

// Build jurisdiction Merkle tree
// We have 16 leaves: leaf[0] = jurisdiction_leaf, leaf[1..15] = 0
function poseidon2Hash(fields) {
  // Pad to 4 elements if needed
  const padded = [...fields];
  while (padded.length < 4) padded.push(0n);
  return poseidon2(padded);
}

const leaves = new Array(16).fill(0n);
leaves[0] = jurisdictionLeaf;

// Build depth-4 Merkle tree (16 leaves)
function buildLevel(input, size) {
  const out = [];
  for (let i = 0; i < size/2; i++) {
    out.push(poseidon2Hash([input[i*2], input[i*2+1]]));
  }
  return out;
}

let level = [...leaves];
let path = [];
let idx = 0; // leaf index

for (let depth = 0; depth < 4; depth++) {
  const siblingIdx = idx % 2 === 0 ? idx + 1 : idx - 1;
  path.push(level[siblingIdx]);
  level = buildLevel(level, level.length);
  idx = Math.floor(idx / 2);
}

// Pad path to depth 10
while (path.length < 10) path.push(0n);

const merkleRoot = level[0];
const merkleIndex = 0;

console.log('\n=== Merkle Tree ===');
console.log('jurisdiction_root_hex:', '0x' + merkleRoot.toString(16).padStart(64, '0'));
console.log('jurisdiction_root_field:', merkleRoot.toString());
console.log('merkle_path:', path.map(v => '"' + v.toString() + '"').join(', '));

// Write Prover.toml
const proverTomlContent = `# Prover.toml - Test inputs for zkremit compliance circuit
# Scenario: Alice (Lagos, Nigeria) sends 500 USDC to Maria in Manila
# POSEYDO2 hashes computed using Noir stdlib

# Private inputs
credential_secret = "${toFieldHex(0x12345678n)}"
credential_hash = "${toFieldHex(credentialHash)}"
issuer_signature = [${[...sigBytes].join(', ')}]
issuer_pubkey_x = [${[...pubKeyX].join(', ')}]
issuer_pubkey_y = [${[...pubKeyY].join(', ')}]
user_pubkey_hash = "${toFieldHex(0xabcdef01n)}"
amount = 500
jurisdiction_code = 566
credential_expiry = 9999999999
current_timestamp = 1748000000
allowed_jurisdictions_path = [${path.map(v => '"' + (v < 0n ? P + v : v).toString() + '"').join(', ')}]
allowed_jurisdictions_index = "0"

# Public inputs
nullifier = "${toFieldHex(nullifier)}"
issuer_pubkey_hash = "${toFieldHex(issuerPubkeyHash)}"
payment_asset = "${toFieldHex(0xdeadbeefn)}"
aml_threshold = 10000
corridor_id = "${toFieldHex(0xcafebaben)}"
allowed_jurisdictions_root = "${toFieldHex(merkleRoot)}"
`;

writeFileSync('/home/escelit/Desktop/vicistar-star/zk-Remit/circuits/Prover.toml', proverTomlContent);
console.log('\n=== Prover.toml written ===');
