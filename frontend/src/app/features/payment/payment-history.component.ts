import { Component, signal, OnInit } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { lastValueFrom } from 'rxjs';
import { NgClass, DatePipe } from '@angular/common';
import { environment } from '../../../environments/environment';

interface PaymentRecord {
  id: number;
  nullifier: string;
  from_address: string;
  to_address: string;
  amount: string;
  asset_code: string;
  corridor_id: string;
  stellar_tx_hash: string;
  ledger: number;
  created_at: string;
}

@Component({
  selector: 'app-payment-history',
  standalone: true,
  imports: [NgClass, DatePipe],
  template: `
    <div class="rounded-xl bg-[#1e293b] p-6 text-white shadow-lg">
      <h2 class="mb-4 text-xl font-bold">Payment History</h2>

      @if (isLoading()) {
        <div class="flex items-center justify-center py-8">
          <svg class="h-8 w-8 animate-spin text-blue-400" viewBox="0 0 24 24">
            <circle class="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" stroke-width="4" fill="none"/>
            <path class="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z"/>
          </svg>
        </div>
      }

      @if (error()) {
        <div class="rounded-lg bg-red-900/50 p-4 text-sm text-red-300">
          {{ error() }}
        </div>
      }

      @if (!isLoading() && !error()) {
        @if (payments().length === 0) {
          <div class="py-8 text-center text-sm text-gray-400">
            No payments found
          </div>
        } @else {
          <div class="space-y-3">
            @for (p of payments(); track p.id) {
              <div class="rounded-lg border border-gray-700 bg-gray-800/50 p-4">
                <div class="mb-2 flex items-center justify-between">
                  <span class="text-xs font-medium text-green-400">✓ Completed</span>
                  <span class="text-xs text-gray-500">{{ p.created_at | date:'medium' }}</span>
                </div>
                <div class="grid grid-cols-1 gap-2 text-sm md:grid-cols-4">
                  <div>
                    <span class="text-xs text-gray-500">Amount</span>
                    <p class="font-mono">{{ p.amount }} {{ p.asset_code }}</p>
                  </div>
                  <div class="col-span-2">
                    <span class="text-xs text-gray-500">Recipient</span>
                    <p class="truncate font-mono">{{ p.to_address }}</p>
                  </div>
                  <div>
                    <span class="text-xs text-gray-500">Corridor</span>
                    <p class="font-mono">{{ p.corridor_id }}</p>
                  </div>
                </div>
                @if (p.stellar_tx_hash) {
                  <div class="mt-2">
                    <span class="text-xs text-gray-500">Tx Hash</span>
                    <a
                      [href]="'https://stellar.expert/explorer/testnet/tx/' + p.stellar_tx_hash"
                      target="_blank"
                      class="block truncate font-mono text-xs text-blue-400 underline hover:text-blue-300"
                    >
                      {{ p.stellar_tx_hash }}
                    </a>
                  </div>
                }
              </div>
            }
          </div>
        }
      }
    </div>
  `,
})
export class PaymentHistoryComponent implements OnInit {
  payments = signal<PaymentRecord[]>([]);
  isLoading = signal(true);
  error = signal<string | null>(null);

  constructor(private http: HttpClient) {}

  async ngOnInit(): Promise<void> {
    try {
      const data = await lastValueFrom(
        this.http.get<PaymentRecord[]>(`${environment.apiUrl}/payment/history`)
      );
      this.payments.set(data);
    } catch (err: any) {
      this.error.set(err.message || 'Failed to load payment history');
    } finally {
      this.isLoading.set(false);
    }
  }
}
