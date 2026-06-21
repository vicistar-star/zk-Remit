import { Injectable, BadRequestException, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { getPool } from '../db/client';
import { NullifierService } from '../nullifier/nullifier.service';
import {
  SendPaymentDto,
  BuildPaymentDto,
  SendPaymentResult,
  Sep31AnchorInfo,
} from './dto/send-payment.dto';

@Injectable()
export class PaymentService {
  private readonly logger = new Logger(PaymentService.name);
  private readonly horizonUrl: string;
  private readonly stellarPassphrase: string;

  constructor(
    private readonly configService: ConfigService,
    private readonly nullifierService: NullifierService,
  ) {
    this.horizonUrl = this.configService.get<string>('STELLAR_HORIZON_URL') ?? '';
    this.stellarPassphrase = this.configService.get<string>('STELLAR_PASSPHRASE') ?? '';
  }

  async send(dto: SendPaymentDto): Promise<SendPaymentResult> {
    const pool = getPool();

    const { rows } = await pool.query(
      'SELECT corridor_id FROM nullifiers WHERE nullifier = $1 LIMIT 1',
      [dto.nullifier]
    );
    if (rows.length === 0) {
      throw new BadRequestException('Proof not verified — cannot send payment');
    }

    try {
      const { TransactionBuilder, Horizon } = await import('@stellar/stellar-sdk');

      const server = new Horizon.Server(this.horizonUrl);
      const transaction = TransactionBuilder.fromXDR(dto.signedXdr, this.stellarPassphrase);
      const txHash = transaction.hash().toString('hex');

      const submitResult = await server.submitTransaction(transaction);

      const ledger = submitResult.ledger;

      await pool.query(
        `INSERT INTO payments (nullifier, from_address, to_address, amount, asset_code, corridor_id, stellar_tx_hash, ledger)
         VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
        [dto.nullifier, '', '', '', '', rows[0].corridor_id ?? '', txHash, ledger]
      );

      return { success: true, txHash, ledger };
    } catch (err: any) {
      this.logger.error(`Payment submission failed: ${err.message}`);
      if (err.response?.data?.extras?.result_codes) {
        const codes = err.response.data.extras.result_codes;
        return { success: false, error: `Stellar error: ${JSON.stringify(codes)}` };
      }
      return { success: false, error: err.message };
    }
  }

  async buildUnsignedPaymentXdr(dto: BuildPaymentDto): Promise<string> {
    try {
      const { TransactionBuilder, Operation, Asset, Memo, Horizon } = await import('@stellar/stellar-sdk');

      const server = new Horizon.Server(this.horizonUrl);
      const sourceAccount = await server.loadAccount(dto.fromAddress);

      let asset: any;
      if (dto.asset === 'XLM') {
        asset = Asset.native();
      } else if (dto.assetIssuer) {
        asset = new Asset(dto.asset, dto.assetIssuer);
      } else {
        throw new BadRequestException('assetIssuer is required for non-XLM assets');
      }

      const nullifierHash = Buffer.from(dto.nullifier.slice(2), 'hex').subarray(0, 32);
      const memo = Memo.hash(nullifierHash);

      const tx = new TransactionBuilder(sourceAccount, {
        fee: '1000',
        networkPassphrase: this.stellarPassphrase,
      })
        .addOperation(
          Operation.payment({
            destination: dto.toAddress,
            asset,
            amount: dto.amount,
          })
        )
        .addMemo(memo)
        .setTimeout(300)
        .build();

      const xdr = tx.toEnvelope().toXDR('base64');
      return xdr;
    } catch (err: any) {
      this.logger.error(`Build unsigned XDR failed: ${err.message}`);
      throw err;
    }
  }

  async getSep31AnchorInfo(corridorId: string): Promise<Sep31AnchorInfo> {
    const corridorMap: Record<string, Sep31AnchorInfo> = {
      'NG-PH': {
        anchorUrl: 'https://anchor.example.com',
        assetCode: 'USDC',
        minAmount: '1',
        maxAmount: '10000',
        fields: {
          sender: { name: 'required', email: 'optional' },
        },
      },
      'NG-GB': {
        anchorUrl: 'https://anchor.example.com',
        assetCode: 'USDC',
        minAmount: '1',
        maxAmount: '10000',
        fields: {
          sender: { name: 'required', email: 'optional' },
        },
      },
      'GH-US': {
        anchorUrl: 'https://anchor.example.com',
        assetCode: 'USDC',
        minAmount: '1',
        maxAmount: '5000',
        fields: {
          sender: { name: 'required', email: 'optional' },
        },
      },
      'KE-DE': {
        anchorUrl: 'https://anchor.example.com',
        assetCode: 'USDC',
        minAmount: '1',
        maxAmount: '5000',
        fields: {
          sender: { name: 'required', email: 'optional' },
        },
      },
    };

    const info = corridorMap[corridorId];
    if (!info) {
      throw new BadRequestException(`Unsupported corridor: ${corridorId}`);
    }

    return info;
  }
}
