import { Injectable, InternalServerErrorException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { randomBytes } from 'crypto';
import { poseidon1, poseidon2, poseidon3 } from 'poseidon-lite';
import nacl from 'tweetnacl';
import { getPool } from '../db/client';
import { IssueCredentialDto, CredentialResponse, IssuerResponse } from './dto/issue-credential.dto';

const CORRIDOR_MAP: Record<string, { senderJurisdiction: number }> = {
  'NG-PH': { senderJurisdiction: 566 },
  'NG-GB': { senderJurisdiction: 566 },
  'GH-US': { senderJurisdiction: 288 },
  'KE-DE': { senderJurisdiction: 404 },
};

const ISSUERS: IssuerResponse[] = [
  {
    name: 'mock-issuer',
    pubkeyHash: '',
    supportedCorridors: ['NG-PH', 'NG-GB', 'GH-US', 'KE-DE'],
  },
];

@Injectable()
export class CredentialService {
  private readonly issuerPrivateKey: Uint8Array;
  private readonly issuerPublicKey: Uint8Array;

  constructor(private readonly configService: ConfigService) {
    const privHex = this.configService.get<string>('ISSUER_PRIVATE_KEY');
    const pubHex = this.configService.get<string>('ISSUER_PUBLIC_KEY');

    if (!privHex || privHex.length !== 128) {
      throw new Error('ISSUER_PRIVATE_KEY must be a 64-byte hex string (128 chars)');
    }
    if (!pubHex || pubHex.length !== 64) {
      throw new Error('ISSUER_PUBLIC_KEY must be a 32-byte hex string (64 chars)');
    }

    this.issuerPrivateKey = Buffer.from(privHex, 'hex');
    this.issuerPublicKey = Buffer.from(pubHex, 'hex');
  }

  async issue(dto: IssueCredentialDto): Promise<CredentialResponse> {
    const pool = getPool();

    const corridorInfo = CORRIDOR_MAP[dto.corridorId];
    if (!corridorInfo) {
      throw new Error(`Unsupported corridor: ${dto.corridorId}`);
    }

    const credentialSecretBytes = randomBytes(32);
    const credentialSecret = '0x' + credentialSecretBytes.toString('hex');

    const walletBytes = Buffer.from(dto.walletAddress, 'utf-8');
    const userPubkeyHashBigInt = this.hashBytesToField(walletBytes);
    const userPubkeyHashBytes = this.bigIntToBytes32(userPubkeyHashBigInt);
    const userPubkeyHash = '0x' + userPubkeyHashBytes.toString('hex');

    const expirySec = Math.floor(Date.now() / 1000) + 90 * 24 * 60 * 60;
    const expiryBigInt = BigInt(expirySec);

    const credentialSecretField = BigInt('0x' + credentialSecretBytes.toString('hex'));
    const credentialHashBigInt = poseidon3([
      credentialSecretField,
      userPubkeyHashBigInt,
      expiryBigInt,
    ]);
    const credentialHashBytes = this.bigIntToBytes32(credentialHashBigInt);
    const credentialHash = '0x' + credentialHashBytes.toString('hex');

    const corridorBytes = Buffer.from(dto.corridorId, 'utf-8');
    const corridorHex = corridorBytes.toString('hex');
    const corridorIdBigInt = poseidon1([BigInt('0x' + corridorHex)]);
    const corridorIdStr = '0x' + this.bigIntToBytes32(corridorIdBigInt).toString('hex');

    const message = Buffer.concat([
      credentialHashBytes,
      userPubkeyHashBytes,
      this.bigIntToBytes64(expiryBigInt),
    ]);
    const signature = nacl.sign.detached(message, this.issuerPrivateKey);
    const issuerSignature = '0x' + Buffer.from(signature).toString('hex');

    const issuerPubkey = '0x' + Buffer.from(this.issuerPublicKey).toString('hex');

    try {
      await pool.query(
        `INSERT INTO credentials
          (wallet_address, kyc_provider, credential_hash, credential_secret,
           issuer_signature, issuer_pubkey, user_pubkey_hash,
           jurisdiction_code, corridor_id, expiry)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
         ON CONFLICT (wallet_address, corridor_id)
         DO UPDATE SET
           credential_hash = EXCLUDED.credential_hash,
           credential_secret = EXCLUDED.credential_secret,
           issuer_signature = EXCLUDED.issuer_signature,
           issuer_pubkey = EXCLUDED.issuer_pubkey,
           user_pubkey_hash = EXCLUDED.user_pubkey_hash,
           jurisdiction_code = EXCLUDED.jurisdiction_code,
           expiry = EXCLUDED.expiry,
           is_revoked = false,
           revoked_at = NULL`,
        [
          dto.walletAddress,
          dto.kycProvider,
          credentialHash,
          credentialSecret,
          issuerSignature,
          issuerPubkey,
          userPubkeyHash,
          corridorInfo.senderJurisdiction,
          corridorIdStr,
          expirySec,
        ]
      );
    } catch (err: any) {
      throw new InternalServerErrorException('Failed to store credential');
    }

    return {
      credentialHash,
      issuerSignature,
      issuerPubkey,
      expiry: expirySec,
      jurisdictionCode: corridorInfo.senderJurisdiction,
      credentialSecret,
    };
  }

  async getIssuers(): Promise<IssuerResponse[]> {
    const pubkeyBigInts = this.bytesToFieldChunks(this.issuerPublicKey, 2);
    const pubkeyHashBigInt = poseidon2([pubkeyBigInts[0], pubkeyBigInts[1]]);
    const pubkeyHash =
      '0x' + this.bigIntToBytes32(pubkeyHashBigInt).toString('hex');

    ISSUERS[0].pubkeyHash = pubkeyHash;
    return ISSUERS;
  }

  async revoke(credentialHash: string): Promise<void> {
    const pool = getPool();
    await pool.query(
      `UPDATE credentials SET is_revoked = true, revoked_at = NOW()
       WHERE credential_hash = $1`,
      [credentialHash]
    );
  }

  private hashBytesToField(bytes: Uint8Array): bigint {
    const chunks = this.bytesToFieldChunks(bytes, 4);
    if (chunks.length === 1) return poseidon1([chunks[0]]);
    if (chunks.length === 2) return poseidon2([chunks[0], chunks[1]]);
    if (chunks.length === 3) return poseidon3([chunks[0], chunks[1], chunks[2]]);

    let hash = poseidon3([chunks[0], chunks[1], chunks[2]]);
    for (let i = 3; i < chunks.length; i++) {
      hash = poseidon2([hash, chunks[i]]);
    }
    return hash;
  }

  private bytesToFieldChunks(bytes: Uint8Array, chunkCount: number): bigint[] {
    const chunkSize = Math.ceil(bytes.length / chunkCount);
    const chunks: bigint[] = [];
    for (let i = 0; i < chunkCount; i++) {
      const start = i * chunkSize;
      const end = Math.min(start + chunkSize, bytes.length);
      if (start >= bytes.length) {
        chunks.push(BigInt(0));
      } else {
        const hex = Array.from(bytes.subarray(start, end))
          .map(b => b.toString(16).padStart(2, '0'))
          .join('');
        chunks.push(BigInt('0x' + hex));
      }
    }
    return chunks;
  }

  private bigIntToBytes32(n: bigint): Buffer {
    const hex = n.toString(16).padStart(64, '0').slice(0, 64);
    const buf = Buffer.alloc(32);
    buf.write(hex, 'hex');
    return buf;
  }

  private bigIntToBytes64(n: bigint): Buffer {
    const buf = Buffer.alloc(8);
    buf.writeBigUInt64BE(n);
    return buf;
  }
}
