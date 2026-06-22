import { ApplicationConfig } from '@angular/core';
import { provideRouter, Routes } from '@angular/router';
import { provideHttpClient } from '@angular/common/http';

export const routes: Routes = [
  { path: '', redirectTo: '/send', pathMatch: 'full' },
  {
    path: 'send',
    loadComponent: () =>
      import('./features/payment/send-page.component').then(
        (c) => c.SendPageComponent
      ),
  },
  {
    path: 'wallet',
    loadComponent: () =>
      import('./features/wallet/wallet-connect.component').then(
        (c) => c.WalletConnectComponent
      ),
  },
  {
    path: 'credential',
    loadComponent: () =>
      import('./features/credential/credential-fetch.component').then(
        (c) => c.CredentialFetchComponent
      ),
  },
  {
    path: 'proof',
    loadComponent: () =>
      import('./features/proof/proof-generate.component').then(
        (c) => c.ProofGenerateComponent
      ),
  },
  {
    path: 'payment',
    loadComponent: () =>
      import('./features/payment/payment-send.component').then(
        (c) => c.PaymentSendComponent
      ),
  },
  { path: '**', redirectTo: '/send' },
];

export const appConfig: ApplicationConfig = {
  providers: [provideRouter(routes), provideHttpClient()],
};
