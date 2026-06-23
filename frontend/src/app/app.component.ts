import { Component } from '@angular/core';
import { RouterOutlet, RouterLink, RouterLinkActive } from '@angular/router';
import { WalletConnectComponent } from './features/wallet/wallet-connect.component';

@Component({
  selector: 'app-root',
  standalone: true,
  imports: [RouterOutlet, RouterLink, RouterLinkActive, WalletConnectComponent],
  template: `
    <div class="min-h-screen bg-[#0f172a] text-white">
      <nav class="flex items-center justify-between border-b border-gray-800 px-4 py-3 md:px-8">
        <span class="text-xl font-bold text-white">zkremit</span>
        <div class="flex items-center gap-3 md:gap-4">
          <a
            routerLink="/send"
            routerLinkActive="text-green-400"
            class="text-xs text-gray-400 transition-colors hover:text-white md:text-sm"
          >Send</a>
          <a
            routerLink="/history"
            routerLinkActive="text-green-400"
            class="text-xs text-gray-400 transition-colors hover:text-white md:text-sm"
          >History</a>
          <app-wallet-connect />
        </div>
      </nav>

      <main class="mx-auto max-w-3xl px-4 py-8 md:px-8">
        <router-outlet />
      </main>

      <footer class="border-t border-gray-800 px-4 py-4 text-center text-xs text-gray-600 md:px-8">
        Zero-knowledge cross-border payments · Built on Stellar · Proofs by Noir
      </footer>
    </div>
  `,
})
export class AppComponent {}
