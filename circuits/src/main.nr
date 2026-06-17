use dep::std::hash::poseidon2::Poseidon2;
use dep::std::ecdsa_secp256k1;

// Poseidon2-based Merkle root computation (depth 10)
fn merkle_root(leaf: Field, index: Field, path: [Field; 10]) -> Field {
    let mut root = leaf;
    let mut idx = index as u64;
    for i in 0..10 {
        let bit = (idx >> i) & 1;
        if bit == 1 {
            root = Poseidon2::hash([path[i], root], 2);
        } else {
            root = Poseidon2::hash([root, path[i]], 2);
        }
    }
    root
}

fn main(
    credential_secret: Field,
    credential_hash: Field,
    issuer_signature: [u8; 64],
    issuer_pubkey_x: [u8; 32],
    issuer_pubkey_y: [u8; 32],
    user_pubkey_hash: Field,
    amount: u64,
    jurisdiction_code: u32,
    credential_expiry: u64,
    current_timestamp: u64,
    allowed_jurisdictions_path: [Field; 10],
    allowed_jurisdictions_index: Field,
    nullifier: pub Field,
    issuer_pubkey_hash: pub Field,
    payment_asset: pub Field,
    aml_threshold: pub u64,
    corridor_id: pub Field,
    allowed_jurisdictions_root: pub Field,
) {
    // 1. Issuer signature verification
    let credential_msg = Poseidon2::hash(
        [credential_hash, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );
    let credential_msg_bytes: [u8; 32] = credential_msg.to_be_bytes::<32>();
    let valid_sig = ecdsa_secp256k1::verify_signature(
        issuer_pubkey_x,
        issuer_pubkey_y,
        issuer_signature,
        credential_msg_bytes,
    );
    assert(valid_sig, "Invalid issuer signature");

    // 2. Credential expiry
    assert(current_timestamp < credential_expiry, "Credential expired");

    // 3. AML threshold
    assert(amount < aml_threshold, "Amount exceeds AML reporting threshold");

    // 4. Jurisdiction Merkle inclusion
    let jurisdiction_leaf = Poseidon2::hash([(jurisdiction_code as Field)], 1);
    let root = merkle_root(
        jurisdiction_leaf,
        allowed_jurisdictions_index,
        allowed_jurisdictions_path,
    );
    assert(
        root == allowed_jurisdictions_root,
        "Jurisdiction not eligible for this corridor",
    );

    // 5. Issuer public key match
    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let computed_issuer_hash = Poseidon2::hash(pubkey_fields, 64);
    assert(
        computed_issuer_hash == issuer_pubkey_hash,
        "Issuer public key mismatch",
    );

    // 6. Nullifier computation
    let computed_nullifier = Poseidon2::hash([credential_secret, corridor_id], 2);
    assert(computed_nullifier == nullifier, "Invalid nullifier");
}

// Helper: build full Merkle tree path for a given leaf index
// Returns (path, root) for a depth-10 tree with 16 leaves
fn build_merkle_path_and_root(
    leaves: [Field; 16],
    leaf_index: Field,
) -> ([Field; 10], Field) {
    let mut path: [Field; 10] = [0; 10];
    let mut idx = leaf_index as u64;

    // Level 0: 16 leaves -> 8 nodes
    let sibling_idx0 = if (idx % 2 == 0) { idx + 1 } else { idx - 1 };
    path[0] = leaves[sibling_idx0];
    let mut l1: [Field; 8] = [0; 8];
    for j in 0..8 {
        l1[j] = Poseidon2::hash([leaves[j * 2], leaves[j * 2 + 1]], 2);
    }
    idx = idx / 2;

    // Level 1: 8 nodes -> 4 nodes
    let sibling_idx1 = if (idx % 2 == 0) { idx + 1 } else { idx - 1 };
    path[1] = l1[sibling_idx1];
    let mut l2: [Field; 4] = [0; 4];
    for j in 0..4 {
        l2[j] = Poseidon2::hash([l1[j * 2], l1[j * 2 + 1]], 2);
    }
    idx = idx / 2;

    // Level 2: 4 nodes -> 2 nodes
    let sibling_idx2 = if (idx % 2 == 0) { idx + 1 } else { idx - 1 };
    path[2] = l2[sibling_idx2];
    let mut l3: [Field; 2] = [0; 2];
    for j in 0..2 {
        l3[j] = Poseidon2::hash([l2[j * 2], l2[j * 2 + 1]], 2);
    }
    idx = idx / 2;

    // Level 3: 2 nodes -> 1 root
    let sibling_idx3 = if (idx % 2 == 0) { idx + 1 } else { idx - 1 };
    path[3] = l3[sibling_idx3];
    let mut root = Poseidon2::hash([l3[0], l3[1]], 2);

    // Pad remaining 6 levels with zero siblings (for depth-10 tree)
    for i in 0..6 {
        path[4 + i] = 0;
        root = Poseidon2::hash([root, path[4 + i]], 2);
    }

    (path, root)
}

#[test]
fn test_happy_path() {
    let issuer_pubkey_x: [u8; 32] = [
        121, 190, 102, 126, 249, 220, 187, 172, 85, 160, 98, 149, 206, 135, 11, 7,
        2, 155, 252, 219, 45, 206, 40, 217, 89, 242, 129, 91, 22, 248, 23, 152,
    ];
    let issuer_pubkey_y: [u8; 32] = [
        72, 58, 218, 119, 38, 163, 196, 101, 93, 164, 251, 252, 14, 17, 8, 168,
        253, 23, 180, 72, 166, 133, 84, 25, 156, 71, 208, 143, 251, 16, 212, 184,
    ];

    let credential_secret: Field = 0x12345678;
    let user_pubkey_hash: Field = 0xabcdef01;
    let credential_expiry: u64 = 9999999999;
    let current_timestamp: u64 = 1748000000;
    let amount: u64 = 500;
    let aml_threshold: u64 = 10000;
    let jurisdiction_code: u32 = 566;
    let corridor_id: Field = 0xcafebabe;
    let payment_asset: Field = 0xdeadbeef;

    // Compute hashes
    let credential_hash = Poseidon2::hash(
        [credential_secret, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );

    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let issuer_pubkey_hash = Poseidon2::hash(pubkey_fields, 64);
    let nullifier = Poseidon2::hash([credential_secret, corridor_id], 2);

    // Build jurisdiction Merkle tree
    let jurisdiction_leaf = Poseidon2::hash([(jurisdiction_code as Field)], 1);
    let mut dummy_leaves: [Field; 16] = [0; 16];
    dummy_leaves[0] = jurisdiction_leaf;
    let (path, root) = build_merkle_path_and_root(dummy_leaves, 0);
    let allowed_jurisdictions_index: Field = 0;
    let allowed_jurisdictions_root: Field = root;

    // Compute signature message
    let credential_msg = Poseidon2::hash(
        [credential_hash, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );
    let credential_msg_bytes: [u8; 32] = credential_msg.to_be_bytes::<32>();

    let issuer_signature: [u8; 64] = [
        55, 103, 95, 49, 28, 44, 87, 82, 213, 215, 117, 27, 64, 201, 103, 121,
        179, 88, 166, 101, 139, 232, 237, 251, 85, 86, 169, 209, 209, 220, 53, 23,
        125, 61, 251, 68, 103, 77, 248, 190, 183, 223, 169, 158, 101, 23, 33, 147,
        228, 27, 204, 148, 196, 100, 243, 174, 169, 47, 2, 0, 182, 94, 254, 61,
    ];

    main(
        credential_secret,
        credential_hash,
        issuer_signature,
        issuer_pubkey_x,
        issuer_pubkey_y,
        user_pubkey_hash,
        amount,
        jurisdiction_code,
        credential_expiry,
        current_timestamp,
        path,
        allowed_jurisdictions_index,
        nullifier,
        issuer_pubkey_hash,
        payment_asset,
        aml_threshold,
        corridor_id,
        allowed_jurisdictions_root,
    );
}

#[test]
fn test_expired_credential() {
    // Same setup as happy path but with expired credential
    let credential_expiry: u64 = 100;
    let current_timestamp: u64 = 200;
    let amount: u64 = 500;
    let aml_threshold: u64 = 10000;
    let jurisdiction_code: u32 = 566;
    let corridor_id: Field = 0xcafebabe;

    let credential_secret: Field = 0x12345678;
    let user_pubkey_hash: Field = 0xabcdef01;
    let payment_asset: Field = 0xdeadbeef;

    let credential_hash = Poseidon2::hash(
        [credential_secret, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );

    let nullifier = Poseidon2::hash([credential_secret, corridor_id], 2);

    let jurisdiction_leaf = Poseidon2::hash([(jurisdiction_code as Field)], 1);
    let mut dummy_leaves: [Field; 16] = [0; 16];
    dummy_leaves[0] = jurisdiction_leaf;
    let (path, root) = build_merkle_path_and_root(dummy_leaves, 0);

    let issuer_pubkey_x: [u8; 32] = [
        121, 190, 102, 126, 249, 220, 187, 172, 85, 160, 98, 149, 206, 135, 11, 7,
        2, 155, 252, 219, 45, 206, 40, 217, 89, 242, 129, 91, 22, 248, 23, 152,
    ];
    let issuer_pubkey_y: [u8; 32] = [
        72, 58, 218, 119, 38, 163, 196, 101, 93, 164, 251, 252, 14, 17, 8, 168,
        253, 23, 180, 72, 166, 133, 84, 25, 156, 71, 208, 143, 251, 16, 212, 184,
    ];

    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let issuer_pubkey_hash = Poseidon2::hash(pubkey_fields, 64);

    let issuer_signature: [u8; 64] = [
        153, 49, 120, 35, 158, 97, 67, 123, 223, 16, 239, 200, 232, 16, 127, 179,
        122, 156, 86, 153, 110, 108, 119, 249, 140, 173, 84, 69, 240, 214, 176, 90,
        84, 105, 84, 156, 48, 82, 152, 214, 61, 126, 206, 86, 118, 120, 100, 27,
        131, 71, 59, 162, 69, 241, 75, 88, 140, 60, 119, 125, 118, 168, 145, 4,
    ];

    main(
        credential_secret,
        credential_hash,
        issuer_signature,
        issuer_pubkey_x,
        issuer_pubkey_y,
        user_pubkey_hash,
        amount,
        jurisdiction_code,
        credential_expiry,
        current_timestamp,
        path,
        0,
        nullifier,
        issuer_pubkey_hash,
        payment_asset,
        aml_threshold,
        corridor_id,
        root,
    );
}

#[test]
fn test_amount_over_threshold() {
    let credential_secret: Field = 0x12345678;
    let user_pubkey_hash: Field = 0xabcdef01;
    let credential_expiry: u64 = 9999999999;
    let current_timestamp: u64 = 100;
    let amount: u64 = 20000;
    let aml_threshold: u64 = 10000;
    let jurisdiction_code: u32 = 566;
    let corridor_id: Field = 0xcafebabe;
    let payment_asset: Field = 0xdeadbeef;

    let credential_hash = Poseidon2::hash(
        [credential_secret, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );

    let nullifier = Poseidon2::hash([credential_secret, corridor_id], 2);

    let jurisdiction_leaf = Poseidon2::hash([(jurisdiction_code as Field)], 1);
    let mut dummy_leaves: [Field; 16] = [0; 16];
    dummy_leaves[0] = jurisdiction_leaf;
    let (path, root) = build_merkle_path_and_root(dummy_leaves, 0);

    let issuer_pubkey_x: [u8; 32] = [
        121, 190, 102, 126, 249, 220, 187, 172, 85, 160, 98, 149, 206, 135, 11, 7,
        2, 155, 252, 219, 45, 206, 40, 217, 89, 242, 129, 91, 22, 248, 23, 152,
    ];
    let issuer_pubkey_y: [u8; 32] = [
        72, 58, 218, 119, 38, 163, 196, 101, 93, 164, 251, 252, 14, 17, 8, 168,
        253, 23, 180, 72, 166, 133, 84, 25, 156, 71, 208, 143, 251, 16, 212, 184,
    ];

    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let issuer_pubkey_hash = Poseidon2::hash(pubkey_fields, 64);

    let issuer_signature: [u8; 64] = [
        55, 103, 95, 49, 28, 44, 87, 82, 213, 215, 117, 27, 64, 201, 103, 121,
        179, 88, 166, 101, 139, 232, 237, 251, 85, 86, 169, 209, 209, 220, 53, 23,
        125, 61, 251, 68, 103, 77, 248, 190, 183, 223, 169, 158, 101, 23, 33, 147,
        228, 27, 204, 148, 196, 100, 243, 174, 169, 47, 2, 0, 182, 94, 254, 61,
    ];

    main(
        credential_secret,
        credential_hash,
        issuer_signature,
        issuer_pubkey_x,
        issuer_pubkey_y,
        user_pubkey_hash,
        amount,
        jurisdiction_code,
        credential_expiry,
        current_timestamp,
        path,
        0,
        nullifier,
        issuer_pubkey_hash,
        payment_asset,
        aml_threshold,
        corridor_id,
        root,
    );
}

#[test]
fn test_invalid_jurisdiction() {
    let credential_secret: Field = 0x12345678;
    let user_pubkey_hash: Field = 0xabcdef01;
    let credential_expiry: u64 = 9999999999;
    let current_timestamp: u64 = 100;
    let amount: u64 = 500;
    let aml_threshold: u64 = 10000;
    let jurisdiction_code: u32 = 999;
    let corridor_id: Field = 0xcafebabe;
    let payment_asset: Field = 0xdeadbeef;

    let credential_hash = Poseidon2::hash(
        [credential_secret, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );

    let nullifier = Poseidon2::hash([credential_secret, corridor_id], 2);

    // Build a Merkle tree where leaf 0 is a wrong value (not jurisdiction_code 999)
    // When main() computes merkle_root(hash(999), 0, bad_path) != bad_root, the check fails
    let mut bad_leaves: [Field; 16] = [0; 16];
    bad_leaves[0] = 12345;
    let (bad_path, bad_root) = build_merkle_path_and_root(bad_leaves, 0);

    let issuer_pubkey_x: [u8; 32] = [
        121, 190, 102, 126, 249, 220, 187, 172, 85, 160, 98, 149, 206, 135, 11, 7,
        2, 155, 252, 219, 45, 206, 40, 217, 89, 242, 129, 91, 22, 248, 23, 152,
    ];
    let issuer_pubkey_y: [u8; 32] = [
        72, 58, 218, 119, 38, 163, 196, 101, 93, 164, 251, 252, 14, 17, 8, 168,
        253, 23, 180, 72, 166, 133, 84, 25, 156, 71, 208, 143, 251, 16, 212, 184,
    ];

    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let issuer_pubkey_hash = Poseidon2::hash(pubkey_fields, 64);

    let issuer_signature: [u8; 64] = [
        55, 103, 95, 49, 28, 44, 87, 82, 213, 215, 117, 27, 64, 201, 103, 121,
        179, 88, 166, 101, 139, 232, 237, 251, 85, 86, 169, 209, 209, 220, 53, 23,
        125, 61, 251, 68, 103, 77, 248, 190, 183, 223, 169, 158, 101, 23, 33, 147,
        228, 27, 204, 148, 196, 100, 243, 174, 169, 47, 2, 0, 182, 94, 254, 61,
    ];

    main(
        credential_secret,
        credential_hash,
        issuer_signature,
        issuer_pubkey_x,
        issuer_pubkey_y,
        user_pubkey_hash,
        amount,
        jurisdiction_code,
        credential_expiry,
        current_timestamp,
        bad_path,
        0,
        nullifier,
        issuer_pubkey_hash,
        payment_asset,
        aml_threshold,
        corridor_id,
        bad_root,
    );
}

#[test]
fn test_invalid_nullifier() {
    let credential_secret: Field = 0x12345678;
    let user_pubkey_hash: Field = 0xabcdef01;
    let credential_expiry: u64 = 9999999999;
    let current_timestamp: u64 = 100;
    let amount: u64 = 500;
    let aml_threshold: u64 = 10000;
    let jurisdiction_code: u32 = 566;
    let corridor_id: Field = 0xcafebabe;
    let payment_asset: Field = 0xdeadbeef;

    let credential_hash = Poseidon2::hash(
        [credential_secret, user_pubkey_hash, (credential_expiry as Field)],
        3,
    );

    // Wrong nullifier: should be hash([credential_secret, corridor_id], 2)
    let nullifier: Field = 0xdeadbeef;

    let jurisdiction_leaf = Poseidon2::hash([(jurisdiction_code as Field)], 1);
    let mut dummy_leaves: [Field; 16] = [0; 16];
    dummy_leaves[0] = jurisdiction_leaf;
    let (path, root) = build_merkle_path_and_root(dummy_leaves, 0);

    let issuer_pubkey_x: [u8; 32] = [
        121, 190, 102, 126, 249, 220, 187, 172, 85, 160, 98, 149, 206, 135, 11, 7,
        2, 155, 252, 219, 45, 206, 40, 217, 89, 242, 129, 91, 22, 248, 23, 152,
    ];
    let issuer_pubkey_y: [u8; 32] = [
        72, 58, 218, 119, 38, 163, 196, 101, 93, 164, 251, 252, 14, 17, 8, 168,
        253, 23, 180, 72, 166, 133, 84, 25, 156, 71, 208, 143, 251, 16, 212, 184,
    ];

    let mut pubkey_fields: [Field; 64] = [0; 64];
    for i in 0..32 {
        pubkey_fields[i] = issuer_pubkey_x[i] as Field;
        pubkey_fields[i + 32] = issuer_pubkey_y[i] as Field;
    }
    let issuer_pubkey_hash = Poseidon2::hash(pubkey_fields, 64);

    let issuer_signature: [u8; 64] = [
        55, 103, 95, 49, 28, 44, 87, 82, 213, 215, 117, 27, 64, 201, 103, 121,
        179, 88, 166, 101, 139, 232, 237, 251, 85, 86, 169, 209, 209, 220, 53, 23,
        125, 61, 251, 68, 103, 77, 248, 190, 183, 223, 169, 158, 101, 23, 33, 147,
        228, 27, 204, 148, 196, 100, 243, 174, 169, 47, 2, 0, 182, 94, 254, 61,
    ];

    main(
        credential_secret,
        credential_hash,
        issuer_signature,
        issuer_pubkey_x,
        issuer_pubkey_y,
        user_pubkey_hash,
        amount,
        jurisdiction_code,
        credential_expiry,
        current_timestamp,
        path,
        0,
        nullifier,
        issuer_pubkey_hash,
        payment_asset,
        aml_threshold,
        corridor_id,
        root,
    );
}
