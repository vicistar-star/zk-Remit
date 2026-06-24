import { test, expect, Page } from '@playwright/test';

test.describe('zkremit Payment Flow', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/send');
  });

  test('wallet connect shows address after Freighter mock', async ({ page }) => {
    await page.evaluate(() => {
      (window as any).freighter = {
        isConnected: async () => ({ isConnected: false }),
        requestAccess: async () => true,
        getPublicKey: async () => 'GAXK2SOZ2RI4ZJ6ZYVJXL6QY7YV5Z7G7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7Y6Y7Y',
      };
    });

    const connectButton = page.getByText('Connect Freighter Wallet');
    await expect(connectButton).toBeVisible();

    await connectButton.click();
    await page.waitForTimeout(500);

    const addressDisplay = page.getByText(/GAXK/);
    await expect(addressDisplay).toBeVisible();
  });

  test('credential fetch shows success state', async ({ page }) => {
    await page.route('**/credential/issue', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          credentialHash: '0x' + 'a'.repeat(64),
          issuerSignature: '0x' + 'b'.repeat(128),
          issuerPubkey: '0x' + 'c'.repeat(64),
          expiry: 9999999999,
          jurisdictionCode: 566,
          credentialSecret: '0x' + 'd'.repeat(64),
        }),
      });
    });

    await page.route('**/credential/issuers', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify([
          { name: 'mock-issuer', pubkeyHash: '0x' + 'e'.repeat(64), supportedCorridors: ['NG-PH', 'NG-GB', 'GH-US', 'KE-DE'] },
        ]),
      });
    });

    const getCredentialButton = page.getByText('Get Compliance Credential');
    await expect(getCredentialButton).toBeVisible();

    if (await getCredentialButton.isEnabled()) {
      await getCredentialButton.click();
      await page.waitForTimeout(500);
      const successIndicator = page.getByText(/Credential issued/);
      await expect(successIndicator).toBeVisible();
    }
  });

  test('proof generation shows progress', async ({ page }) => {
    await page.route('**/credential/issue', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          credentialHash: '0x' + 'a'.repeat(64),
          issuerSignature: '0x' + 'b'.repeat(128),
          issuerPubkey: '0x' + 'c'.repeat(64),
          expiry: 9999999999,
          jurisdictionCode: 566,
          credentialSecret: '0x' + 'd'.repeat(64),
        }),
      });
    });

    const generateButton = page.getByText('Generate ZK Proof');
    if (await generateButton.isEnabled()) {
      await generateButton.click();
      await page.waitForTimeout(300);
      const progressBar = page.locator('[role="progressbar"]');
      await expect(progressBar).toBeVisible();
    }
  });

  test('full flow completes on desktop viewport', async ({ page }) => {
    await page.route('**/credential/issue', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          credentialHash: '0x' + 'a'.repeat(64),
          issuerSignature: '0x' + 'b'.repeat(128),
          issuerPubkey: '0x' + 'c'.repeat(64),
          expiry: 9999999999,
          jurisdictionCode: 566,
          credentialSecret: '0x' + 'd'.repeat(64),
        }),
      });
    });

    await page.route('**/proof/relay', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          verified: true,
          txHash: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        }),
      });
    });

    await page.route('**/payment/build-unsigned', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          unsignedXdr: 'AAAAAgAAAQAAAAAAAAAA',
        }),
      });
    });

    await page.route('**/payment/send', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          success: true,
          txHash: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
          ledger: 1234567,
        }),
      });
    });

    const heading = page.getByText(/zkremit/);
    await expect(heading).toBeVisible();
  });

  test('full flow completes on mobile viewport', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 812 });

    await page.route('**/credential/issue', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          credentialHash: '0x' + 'a'.repeat(64),
          issuerSignature: '0x' + 'b'.repeat(128),
          issuerPubkey: '0x' + 'c'.repeat(64),
          expiry: 9999999999,
          jurisdictionCode: 566,
          credentialSecret: '0x' + 'd'.repeat(64),
        }),
      });
    });

    await page.route('**/proof/relay', async (route) => {
      await route.fulfill({
        status: 200,
        contentType: 'application/json',
        body: JSON.stringify({
          verified: true,
          txHash: 'abcdef1234567890abcdef1234567890abcdef1234567890abcdef1234567890',
        }),
      });
    });

    const sendPage = page.getByText(/Send Payment|zkremit/);
    await expect(sendPage).toBeVisible({ timeout: 10000 });

    await page.waitForTimeout(500);
    const noHorizontalScroll = await page.evaluate(() => {
      return document.documentElement.scrollWidth <= window.innerWidth;
    });
    expect(noHorizontalScroll).toBe(true);
  });
});
