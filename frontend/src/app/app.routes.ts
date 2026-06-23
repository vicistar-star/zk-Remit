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
    path: 'history',
    loadComponent: () =>
      import('./features/payment/payment-history.component').then(
        (c) => c.PaymentHistoryComponent
      ),
  },
  { path: '**', redirectTo: '/send' },
];

export const appConfig: ApplicationConfig = {
  providers: [provideRouter(routes), provideHttpClient()],
};
