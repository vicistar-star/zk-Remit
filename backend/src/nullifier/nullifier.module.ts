import { Module } from '@nestjs/common';
import { NullifierService } from './nullifier.service';
import { NullifierController } from './nullifier.controller';

@Module({
  controllers: [NullifierController],
  providers: [NullifierService],
  exports: [NullifierService],
})
export class NullifierModule {}
