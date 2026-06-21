import { IsString, IsOptional, MinLength } from 'class-validator';

export class SendPaymentDto {
  @IsString()
  @MinLength(1)
  nullifier!: string;

  @IsString()
  @MinLength(1)
  signedXdr!: string;
}

export class BuildPaymentDto {
  @IsString()
  fromAddress!: string;

  @IsString()
  toAddress!: string;

  @IsString()
  amount!: string;

  @IsString()
  asset!: string;

  @IsOptional()
  @IsString()
  assetIssuer?: string;

  @IsString()
  nullifier!: string;
}

export interface SendPaymentResult {
  success: boolean;
  txHash?: string;
  ledger?: number;
  error?: string;
}

export interface Sep31AnchorInfo {
  anchorUrl: string;
  assetCode: string;
  minAmount: string;
  maxAmount: string;
  fields: Record<string, Record<string, string>>;
}
