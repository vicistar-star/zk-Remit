import { Controller, Post, Get, Body, ValidationPipe, UsePipes } from '@nestjs/common';
import { CredentialService } from './credential.service';
import { IssueCredentialDto } from './dto/issue-credential.dto';

@Controller('credential')
export class CredentialController {
  constructor(private readonly credentialService: CredentialService) {}

  @Post('issue')
  @UsePipes(new ValidationPipe({ whitelist: true }))
  async issue(@Body() dto: IssueCredentialDto) {
    return this.credentialService.issue(dto);
  }

  @Get('issuers')
  async getIssuers() {
    return this.credentialService.getIssuers();
  }
}
