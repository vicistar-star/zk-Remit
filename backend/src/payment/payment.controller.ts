import { Controller, Post, Get, Param, Body, UsePipes, ValidationPipe } from '@nestjs/common';
import { PaymentService } from './payment.service';
import { SendPaymentDto, BuildPaymentDto } from './dto/send-payment.dto';

@Controller()
export class PaymentController {
  constructor(private readonly paymentService: PaymentService) {}

  @Post('payment/send')
  @UsePipes(new ValidationPipe({ whitelist: true }))
  async send(@Body() dto: SendPaymentDto) {
    return this.paymentService.send(dto);
  }

  @Get('payment/sep31-info/:corridorId')
  async getSep31Info(@Param('corridorId') corridorId: string) {
    return this.paymentService.getSep31AnchorInfo(corridorId);
  }

  @Post('payment/build-unsigned')
  @UsePipes(new ValidationPipe({ whitelist: true }))
  async buildUnsigned(@Body() dto: BuildPaymentDto) {
    return this.paymentService.buildUnsignedPaymentXdr(dto);
  }

  @Get('payment/history')
  async getHistory() {
    return this.paymentService.getHistory();
  }

  @Get('health')
  async health() {
    return {
      status: 'ok',
      timestamp: Date.now(),
      network: process.env.STELLAR_NETWORK ?? 'testnet',
    };
  }
}
