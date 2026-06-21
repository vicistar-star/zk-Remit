import { Controller, Post, Body, UsePipes, ValidationPipe, UseGuards } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { ProofService } from './proof.service';
import { RelayProofDto } from './dto/relay-proof.dto';

@Controller('proof')
@UseGuards(ThrottlerGuard)
export class ProofController {
  constructor(private readonly proofService: ProofService) {}

  @Post('relay')
  @UsePipes(new ValidationPipe({ whitelist: true }))
  async relay(@Body() dto: RelayProofDto) {
    return this.proofService.relay(dto);
  }
}
