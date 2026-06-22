import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { environment } from '../../../environments/environment';

export interface CredentialResponse {
  credentialHash: string;
  issuerSignature: string;
  issuerPubkey: string;
  expiry: number;
  jurisdictionCode: number;
  credentialSecret: string;
}

export interface IssuerInfo {
  name: string;
  pubkeyHash: string;
  supportedCorridors: string[];
}

export interface MerkleRoots {
  jurisdictionRoot: string;
  corridorRoot: string;
  revocationRoot: string;
}

@Injectable({ providedIn: 'root' })
export class CredentialService {
  constructor(private http: HttpClient) {}

  async issue(params: {
    walletAddress: string;
    kycProvider: string;
    corridorId: string;
  }): Promise<CredentialResponse> {
    return lastValueFrom(
      this.http.post<CredentialResponse>(
        `${environment.apiUrl}/credential/issue`,
        params
      )
    );
  }

  async getIssuers(): Promise<IssuerInfo[]> {
    return lastValueFrom(
      this.http.get<IssuerInfo[]>(`${environment.apiUrl}/credential/issuers`)
    );
  }

  async getMerkleRoots(): Promise<MerkleRoots> {
    const [jurisdictionRoot, corridorRoot, revocationRoot] = await Promise.all([
      lastValueFrom(
        this.http.get<{ root: string }>(
          `${environment.apiUrl}/merkle/jurisdiction-root`
        )
      ),
      lastValueFrom(
        this.http.get<{ root: string }>(
          `${environment.apiUrl}/merkle/corridor-root`
        )
      ),
      lastValueFrom(
        this.http.get<{ root: string }>(
          `${environment.apiUrl}/merkle/revocation-root`
        )
      ),
    ]);

    return {
      jurisdictionRoot: jurisdictionRoot.root,
      corridorRoot: corridorRoot.root,
      revocationRoot: revocationRoot.root,
    };
  }
}
