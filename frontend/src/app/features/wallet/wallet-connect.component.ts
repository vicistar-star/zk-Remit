import { Component, EventEmitter, Output, signal } from '@angular/core';
import { NgClass } from '@angular/common';
import { StellarService } from '../../shared/services/stellar.service';

@Component({
  selector: 'app-wallet-connect',
  standalone: true,
  imports: [NgClass],
  template: `
    <div class="rounded-xl bg-[#1e293b] p-6 text-white shadow-lg">
      @if (!stellarService.isConnected()) {
        <div class="flex flex-col items-center gap-4">
          <span class="text-3xl">🔗</span>
          <button
            (click)="handleConnect()"
            [disabled]="isConnecting()"
            class="rounded-lg bg-[#16a34a] px-6 py-3 font-semibold text-white transition-colors hover:bg-[#15803d] disabled:cursor-not-allowed disabled:opacity-50"
          >
            @if (isConnecting()) {
              <span class="flex items-center gap-2">
                <svg class="h-5 w-5 animate-spin" viewBox="0 0 24 24">
                  <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/>
                  <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
                </svg>
                Connecting...
              </span>
            } @else {
              Connect Freighter Wallet
            }
          </button>
          <p class="text-sm text-gray-400">Privacy-preserving payments on Stellar</p>
        </div>
      } @else {
        <div class="flex flex-col gap-3">
          <div class="flex items-center gap-2">
            <span class="h-2 w-2 rounded-full bg-green-500 shadow-[0_0_6px_rgba(34,197,94,0.6)]"></span>
            <span class="text-sm text-green-400">Connected</span>
          </div>
          <div class="flex items-center justify-between">
            <span class="font-mono text-sm text-gray-300">{{ stellarService.formatAddress() }}</span>
            <button (click)="copyAddress()" class="text-xs text-gray-400 hover:text-white">
              {{ showCopied() ? 'Copied!' : 'Copy' }}
            </button>
          </div>
          <div class="flex items-center justify-between">
            <span class="text-lg font-semibold">{{ stellarService.balance() }} XLM</span>
            <button (click)="stellarService.refreshBalance()" class="text-gray-400 hover:text-white">
              <svg class="h-4 w-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
                <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15"/>
              </svg>
            </button>
          </div>
          <button (click)="handleDisconnect()" class="self-start text-xs text-gray-500 hover:text-gray-300">
            Disconnect
          </button>
        </div>
      }
      @if (error()) {
        <div class="mt-3 rounded-lg bg-red-900/50 p-3 text-sm text-red-300">
          {{ error() }}
          <a href="https://freighter.app" target="_blank" class="ml-1 underline">Install Freighter →</a>
        </div>
      }
    </div>
  `,
})
export class WalletConnectComponent {
  @Output() connected = new EventEmitter<string>();

  isConnecting = signal(false);
  showCopied = signal(false);
  error = signal<string | null>(null);

  constructor(public stellarService: StellarService) {}

  async handleConnect(): Promise<void> {
    this.isConnecting.set(true);
    this.error.set(null);
    try {
      const address = await this.stellarService.connect();
      this.connected.emit(address);
    } catch (err: any) {
      this.error.set(err.message || 'Failed to connect');
    } finally {
      this.isConnecting.set(false);
    }
  }

  handleDisconnect(): void {
    this.stellarService.disconnect();
    this.showCopied.set(false);
  }

  async copyAddress(): Promise<void> {
    const addr = this.stellarService.address();
    if (!addr) return;
    await navigator.clipboard.writeText(addr);
    this.showCopied.set(true);
    setTimeout(() => this.showCopied.set(false), 2000);
  }
}
