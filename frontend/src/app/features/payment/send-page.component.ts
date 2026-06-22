import { Component, signal } from '@angular/core';
import { WalletConnectComponent } from '../wallet/wallet-connect.component';
import { CredentialFetchComponent, Credential } from '../credential/credential-fetch.component';
import { ProofGenerateComponent } from '../proof/proof-generate.component';
import { ProofResult } from '../../shared/services/noir.service';

@Component({
  selector: 'app-send-page',
  standalone: true,
  imports: [
    WalletConnectComponent,
    CredentialFetchComponent,
    ProofGenerateComponent,
  ],
  template: `
    <div class="space-y-6">
      <div class="mb-6 flex items-center gap-2">
        @for (s of steps; track s.num; let i = $index) {
          <div class="flex items-center gap-2">
            <div
              class="flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold"
              [class.bg-green-500]="s.num <= currentStep()"
              [class.bg-gray-700]="s.num > currentStep()"
              [class.text-white]="true"
            >
              @if (s.num < currentStep()) { ✓ }
              @else { {{ s.num }} }
            </div>
            <span class="hidden text-sm md:inline" [class.text-green-400]="s.num <= currentStep()" [class.text-gray-500]="s.num > currentStep()">
              {{ s.label }}
            </span>
            @if (i < steps.length - 1) {
              <div class="h-px w-8 bg-gray-700"></div>
            }
          </div>
        }
      </div>

      <div class="space-y-6">
        <app-wallet-connect (connected)="onWalletConnected($event)" />

        @if (walletAddress()) {
          <app-credential-fetch
            [walletAddress]="walletAddress()!"
            (credentialFetched)="onCredentialFetched($event)"
          />
        }

        @if (credential()) {
          <app-proof-generate
            [credential]="credential()!"
            [amount]="500"
            corridorId="NG-PH"
            paymentAsset="USDC"
            (proofGenerated)="onProofGenerated($event)"
          />
        }
      </div>
    </div>
  `,
})
export class SendPageComponent {
  steps = [
    { num: 1, label: 'Wallet' },
    { num: 2, label: 'Credential' },
    { num: 3, label: 'Proof' },
    { num: 4, label: 'Payment' },
  ];

  currentStep = signal(1);
  walletAddress = signal<string | null>(null);
  credential = signal<Credential | null>(null);

  onWalletConnected(address: string): void {
    this.walletAddress.set(address);
    this.currentStep.set(2);
  }

  onCredentialFetched(c: Credential): void {
    this.credential.set(c);
    this.currentStep.set(3);
  }

  onProofGenerated(result: ProofResult): void {
    this.currentStep.set(4);
  }
}
