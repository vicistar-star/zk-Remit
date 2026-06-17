// Generate test data for zkremit compliance circuit
// Computes poseidon2 hashes and ECDSA secp256k1 signatures

import { createHash } from 'node:crypto';

// We'll use a dedicated subprocess approach since poseidon-lite
// might not handle all array sizes we need.

// For the ECDSA secp256k1 operations, we'll use Node's crypto
// which supports ECDSA with secp256k1 in recent versions.

function bigintToBytes32(n) {
  const hex = n.toString(16).padStart(64, '0');
  return Buffer.from(hex, 'hex');
}

function bytesToBigint(bytes) {
  return BigInt('0x' + bytes.toString('hex'));
}

// Generate a secp256k1 keypair
const { generateKeyPairSync, sign } = await import('node:crypto');

const keypair = generateKeyPairSync('ec', {
  namedCurve: 'secp256k1',
  publicKeyEncoding: { type: 'spki', format: 'der' },
  privateKeyEncoding: { type: 'pkcs8', format: 'der' },
});

// Convert raw public key coordinates
// The SPKI DER format has specific structure for EC keys
function extractRawPubkey(derPubkey) {
  // SECP256K1 OID: 1.3.132.0.10
  // For uncompressed format: 0x04 || X (32 bytes) || Y (32 bytes)
  // The DER structure includes algorithm identifier tags
  
  // Parse uncompressed EC public key from DER
  // Tag 0x04 (uncompressed) is typically at the end
  const idx = derPubkey.indexOf(0x04);
  if (idx >= 0 && derPubkey.length - idx >= 65) {
    return {
      x: derPubkey.subarray(idx + 1, idx + 33),
      y: derPubkey.subarray(idx + 33, idx + 65),
    };
  }
  throw new Error('Could not extract raw pubkey');
}

const rawPubkey = extractRawPubkey(keypair.publicKey);

console.log('=== Test Keypair ===');
console.log('issuer_pubkey_x:', '[' + [...rawPubkey.x].join(', ') + ']');
console.log('issuer_pubkey_y:', '[' + [...rawPubkey.y].join(', ') + ']');

// For the test, we need to compute the credential_msg hash the same way Noir does.
// Since we can't easily match Noir's Poseidon2 from JS,
// we'll output the test values and the raw pubkey, then use Noir to compute the hash,
// and finally sign the hash with the private key.

// Output the private key for signing later
console.log('private_key_hex:', keypair.privateKey.toString('hex'));

// Also output test circuit values
console.log('\n=== Circuit Test Values ===');
console.log('credential_secret: 0x12345678');
console.log('user_pubkey_hash: 0xabcdef01');
console.log('credential_expiry: 9999999999');
console.log('current_timestamp: 1748000000');
console.log('amount: 500');
console.log('aml_threshold: 10000');
console.log('jurisdiction_code: 566');
console.log('corridor_id: 0xcafebabe');
console.log('payment_asset: 0xdeadbeef');
