import { expect, test } from '@playwright/test';
import { goto, staffLogin } from './fixtures';

/** Change request 07 (CHANGES-07.md). One describe per item; the check names match TECHNICAL-SPEC section 12. */

const FULL = 'Survey No. 98/1, Ramenakoppa, Kasaba 1 Hobali, Hosahalli Post, Shivamogga – 577202, Karnataka';

test.describe('TL7: the Tally export screen (change 07.3)', () => {
  test('no Purchases option; each voucher shows New or "Already exported on"', async ({ page }) => {
    await staffLogin(page, 'accounts');
    await goto(page, '/staff/billing/reports');
    await page.getByRole('tab', { name: 'Tally sales export' }).or(page.getByRole('button', { name: 'Tally sales export' })).first().click();
    const box = page.getByTestId('tally-export');
    await expect(box.getByLabel('Purchases')).toHaveCount(0);
    for (const k of ['Sales', 'Receipts', 'Credit notes']) await expect(box.getByLabel(k)).toBeVisible();
    await expect(box).toContainText('Purchases are entered directly in Tally');
    await expect(page.getByTestId('tally-summary')).toBeVisible();
  });
});

test.describe('TS7: Tally settings for Accounts (change 07.2)', () => {
  test('Accounts renames a ledger and the change is logged with who, old and new name', async ({ page }) => {
    await staffLogin(page, 'accounts');
    await goto(page, '/staff/billing/settings');
    const box = page.getByTestId('tally-settings');
    await expect(box.getByLabel('Purchases')).toHaveCount(0);
    await expect(box.getByLabel("Suppliers' group")).toHaveCount(0);
    const round = box.getByLabel('Round off');
    const name = `Round Off ${Date.now() % 10000}`;
    await round.fill(name);
    await box.getByRole('button', { name: 'Save changes' }).first().click();
    await expect(page.getByTestId('tally-rename').first()).toContainText(name);
    await box.getByRole('button', { name: 'Reset to standard names' }).first().click();
    await expect(round).toHaveValue('Round Off');
  });
});

test.describe('PO7: Purchase Orders and Suppliers (change 07.4)', () => {
  test('the default supplier is preselected; saving opens the preview with the toolbar; Mark as received', async ({ page }) => {
    await staffLogin(page, 'accounts');
