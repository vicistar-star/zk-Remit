import { Injectable, signal } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';

@Injectable({ providedIn: 'root' })
export class StellarService {
  private _address = signal<string | null>(null);
  readonly address = this._address.asReadonly();

  private _balance = signal<string>('0');
  readonly balance = this._balance.asReadonly();

  private _isConnected = signal(false);
  readonly isConnected = this._isConnected.asReadonly();

  constructor(private http: HttpClient) {}

  async connect(): Promise<string> {
    const freighter = await import('@stellar/freighter-api');

    const connectedRes = await freighter.isConnected();
    if (!connectedRes.isConnected) {
      throw new Error('Freighter not installed');
    }

    await freighter.requestAccess();
    const addrRes = await freighter.getAddress();
    const publicKey = addrRes.address;

    this._address.set(publicKey);
    this._isConnected.set(true);
    await this.refreshBalance();
    return publicKey;
  }

  disconnect(): void {
    this._address.set(null);
    this._balance.set('0');
    this._isConnected.set(false);
  }

  async refreshBalance(): Promise<void> {
    const address = this._address();
    if (!address) return;

    try {
      const res: any = await lastValueFrom(
        this.http.get(`${environment.stellarHorizonUrl}/accounts/${address}`)
      );
      const native = res.balances.find(
        (b: any) => b.asset_type === 'native'
      );
      this._balance.set(native ? native.balance : '0');
    } catch {
      this._balance.set('0');
    }
  }

  formatAddress(): string {
    const addr = this._address();
    if (!addr) return '';
    return addr.slice(0, 5) + '····' + addr.slice(-4);
  }

  async buildAndSignPaymentXdr(params: {
    to: string;
    amount: string;
    asset: string;
    assetIssuer?: string;
    nullifier: string;
  }): Promise<string> {
    const xdr: any = await lastValueFrom(
      this.http.post(`${environment.apiUrl}/payment/build-unsigned`, {
        fromAddress: this._address(),
        toAddress: params.to,
        amount: params.amount,
        asset: params.asset,
        assetIssuer: params.assetIssuer,
        nullifier: params.nullifier,
      })
    );

    const freighter = await import('@stellar/freighter-api');
    const signedRes = await freighter.signTransaction(xdr.unsignedXdr, {
      networkPassphrase:
        environment.stellarNetwork === 'testnet'
          ? 'Test SDF Network ; September 2015'
          : 'Public Global Stellar Network ; September 2015',
    });
    return signedRes.signedTxXdr;
  }

  async submitSignedXdr(
    signedXdr: string,
    nullifier: string
  ): Promise<{ txHash: string; ledger: number }> {
    const result: any = await lastValueFrom(
      this.http.post(`${environment.apiUrl}/payment/send`, {
        signedXdr,
        nullifier,
      })
    );
    return { txHash: result.txHash, ledger: result.ledger };
  }
}
