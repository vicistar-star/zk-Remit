import { Test, TestingModule } from '@nestjs/testing';
import { ConfigService } from '@nestjs/config';
import { CredentialService } from './credential.service';
import { IssueCredentialDto } from './dto/issue-credential.dto';

describe('CredentialService', () => {
  let service: CredentialService;
  let configService: ConfigService;

  const mockPrivateKey = 'a'.repeat(128);
  const mockPublicKey = 'b'.repeat(64);

  beforeEach(async () => {
    const module: TestingModule = await Test.createTestingModule({
      providers: [
        CredentialService,
        {
          provide: ConfigService,
          useValue: {
            get: jest.fn((key: string) => {
              if (key === 'ISSUER_PRIVATE_KEY') return mockPrivateKey;
              if (key === 'ISSUER_PUBLIC_KEY') return mockPublicKey;
              return undefined;
            }),
          },
        },
      ],
    }).compile();

    service = module.get<CredentialService>(CredentialService);
    configService = module.get<ConfigService>(ConfigService);
  });

  it('should be defined', () => {
    expect(service).toBeDefined();
  });

  it('should require ISSUER_PRIVATE_KEY on construction', () => {
    expect(() => {
      new CredentialService({
        get: jest.fn((key: string) => {
          if (key === 'ISSUER_PRIVATE_KEY') return undefined;
          if (key === 'ISSUER_PUBLIC_KEY') return mockPublicKey;
          return undefined;
        }),
      } as any);
    }).toThrow('ISSUER_PRIVATE_KEY');
  });

  it('should require ISSUER_PUBLIC_KEY on construction', () => {
    expect(() => {
      new CredentialService({
        get: jest.fn((key: string) => {
          if (key === 'ISSUER_PRIVATE_KEY') return mockPrivateKey;
          if (key === 'ISSUER_PUBLIC_KEY') return undefined;
          return undefined;
        }),
      } as any);
    }).toThrow('ISSUER_PUBLIC_KEY');
  });

  it('should return issuers with pubkeyHash populated', async () => {
    const issuers = await service.getIssuers();
    expect(issuers).toHaveLength(1);
    expect(issuers[0].name).toBe('mock-issuer');
    expect(issuers[0].pubkeyHash).toMatch(/^0x[0-9a-f]{64}$/);
    expect(issuers[0].supportedCorridors).toContain('NG-PH');
  });

  it('should throw for unsupported corridor', async () => {
    const dto: IssueCredentialDto = {
      walletAddress: 'GAXK2SOZ2RI4ZJ6ZYVJXL6QY7YV5Z7G7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7',
      kycProvider: 'mock-issuer',
      corridorId: 'INVALID' as any,
    };

    await expect(service.issue(dto)).rejects.toThrow('Unsupported corridor');
  });
});
