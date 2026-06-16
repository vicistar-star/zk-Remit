import { Module } from '@nestjs/common';
import { NullifierService } from './nullifier.service';

@Module({
  providers: [NullifierService],
  exports: [NullifierService],
})
export class NullifierModule {}
