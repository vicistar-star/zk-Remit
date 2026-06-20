import { Controller, Get, Param, BadRequestException } from '@nestjs/common';
import { NullifierService } from './nullifier.service';

@Controller('nullifier')
export class NullifierController {
  constructor(private readonly nullifierService: NullifierService) {}

  @Get(':nullifier')
  async checkNullifier(@Param('nullifier') nullifier: string) {
    if (!this.nullifierService.isValidFormat(nullifier)) {
      throw new BadRequestException('Invalid nullifier format — must be a 66-char hex string starting with 0x');
    }

    const result = await this.nullifierService.isUsed(nullifier);

    return {
      used: result.used,
      nullifier,
      source: result.source,
    };
  }
}
