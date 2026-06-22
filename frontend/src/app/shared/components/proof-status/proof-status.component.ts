import { Component, Input } from '@angular/core';
import { NgClass } from '@angular/common';

@Component({
  selector: 'app-proof-status',
  standalone: true,
  imports: [NgClass],
  template: `
    <div
      class="inline-flex h-8 w-8 items-center justify-center rounded-full text-sm font-bold"
      [ngClass]="{
        'border border-gray-500 text-gray-400': status === 'idle',
        'border-2 border-yellow-400 text-yellow-400 animate-spin': status === 'pending',
        'bg-green-500 text-white': status === 'verified',
        'bg-red-500 text-white': status === 'failed',
      }"
    >
      @if (status === 'idle') { ○ }
      @if (status === 'pending') { ◌ }
      @if (status === 'verified') { ✓ }
      @if (status === 'failed') { ✗ }
    </div>
  `,
})
export class ProofStatusComponent {
  @Input({ required: true }) status: 'idle' | 'pending' | 'verified' | 'failed' = 'idle';
}
