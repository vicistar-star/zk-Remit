import { secp256k1 } from '@noble/curves/secp256k1.js';
import { writeFileSync } from 'fs';

const P = 21888242871839275222246405745257275088548364400416034343698204186575808495617n;

function toFieldHex(n) {
  const val = n < 0n ? P + n : n;
  return '0x' + val.toString(16).padStart(64, '0');
}

function toFieldStr(n) {
  const val = n < 0n ? P + n : n;
  return '"' + val.toString() + '"';
}

function fieldToBytes(n) {
  const val = n < 0n ? P + n : n;
  const hex = val.toString(16).padStart(64, '0');
  const bytes = new Uint8Array(32);
  for (let i = 0; i < 32; i++) {
    bytes[i] = parseInt(hex.substring(i * 2, i * 2 + 2), 16);
  }
  return bytes;
}

// Values from Noir data_gen output
const credentialHash = -4402511220242691388006346689087889783404163369740921854167015185592014871560n;
const credentialMsg = -3877856754960847370737454949585186066356095934866944696566545921286626159182n;
const nullifier = 1357950050555029929921390988943786518908957045138448594399398990097994072485n;
const issuerPubkeyHash = 2336791372758744260233576627453690259513827693686905825560323877274125089771n;
const jurisdictionLeaf = 8744438042687900322886356860697131572612840012928336951975962661506324136404n;
const depth10Root = -8881767614040893614153278186630552963409414355825709208117692311661281736872n;
const path1 = 5151499478991301833156025595048985053689893395646836724335623777508747990769n; // zero = hash([0,0], 2)
const path2 = 6425444215191838285069835781607981895589384041954338275956759438530131468944n; // zero_parent
const path3 = -6521813983988080564073403751227159684658863940099230709884484501240195282401n; // zero_gp (negative)

console.log('=== Computed Values ===');
console.log('credential_hash:', toFieldHex(credentialHash));
console.log('credential_msg:', toFieldHex(credentialMsg));
console.log('nullifier:', toFieldHex(nullifier));
console.log('issuer_pubkey_hash:', toFieldHex(issuerPubkeyHash));
console.log('jurisdiction_leaf:', toFieldHex(jurisdictionLeaf));
console.log('depth10_root:', toFieldHex(depth10Root));

// Generate keypair with deterministic private key
const privateKey = new Uint8Array(32);
privateKey[31] = 1; // Valid secp256k1 scalar
const pubKey = secp256k1.getPublicKey(privateKey, false);
const pubKeyX = [...pubKey.slice(1, 33)];
const pubKeyY = [...pubKey.slice(33, 65)];

console.log('\npubkey_x:', pubKeyX.join(', '));
console.log('pubkey_y:', pubKeyY.join(', '));

// Sign credential_msg (prehash=false: sign msgBytes directly, not SHA256(msgBytes))
// Noir's ecdsa_secp256k1::verify_signature uses the message hash as-is (no internal hashing)
const msgBytes = fieldToBytes(credentialMsg);
console.log('\nmsg bytes for signing:', Buffer.from(msgBytes).toString('hex'));
const sigBytes = [...secp256k1.sign(msgBytes, privateKey, { prehash: false, lowS: true })];
console.log('signature:', sigBytes.join(', '));
const verified = secp256k1.verify(new Uint8Array(sigBytes), msgBytes, pubKey, { prehash: false });
console.log('verified:', verified);

// Build path: [0, zero, zero_parent, zero_gp, 0, 0, 0, 0, 0, 0]
const path = [
  toFieldStr(0n),
  toFieldStr(path1),
  toFieldStr(path2),
  toFieldStr(path3),
  ...Array(6).fill('"0"'),
];

// Write Prover.toml
const content = `credential_secret = "${toFieldHex(0x12345678n)}"
credential_hash = "${toFieldHex(credentialHash)}"
issuer_signature = [${sigBytes.join(', ')}]
issuer_pubkey_x = [${pubKeyX.join(', ')}]
issuer_pubkey_y = [${pubKeyY.join(', ')}]
user_pubkey_hash = "${toFieldHex(0xabcdef01n)}"
amount = 500
jurisdiction_code = 566
credential_expiry = 9999999999
current_timestamp = 1748000000
allowed_jurisdictions_path = [${path.join(', ')}]
allowed_jurisdictions_index = "0"
nullifier = "${toFieldHex(nullifier)}"
issuer_pubkey_hash = "${toFieldHex(issuerPubkeyHash)}"
payment_asset = "${toFieldHex(0xdeadbeefn)}"
aml_threshold = 10000
corridor_id = "${toFieldHex(0xcafebaben)}"
allowed_jurisdictions_root = "${toFieldHex(depth10Root)}"
`;

writeFileSync('/home/escelit/Desktop/vicistar-star/zk-Remit/circuits/Prover.toml', content);
console.log('\n=== Prover.toml written to circuits/Prover.toml ===');
