import { test, expect, type Page, type BrowserContext } from '@playwright/test';

// E2E de la partida activa (Fase 2) con 6 jugadores reales. Supabase local + preview.
const PIN = '246813';

async function createGame(page: Page, host = 'Anfitrión'): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Partida activa');
  await page.getByPlaceholder('Daniel').fill(host);
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/, { timeout: 30_000 });
  return page.url().match(/\/sala\/([A-Z0-9]{6})$/)![1]!;
}
async function joinGame(page: Page, code: string, name: string) {
  await page.goto('/unirse');
  await page.getByPlaceholder('ABC123').fill(code);
  await page.getByRole('button', { name: 'Buscar sala' }).click();
  await page.getByPlaceholder('Marty').fill(name);
  await page.getByRole('button', { name: 'Unirme' }).click();
  await page.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
}
async function pickAndReady(page: Page, tokenIndex: number) {
  await page.getByRole('radiogroup', { name: 'Ficha', exact: true }).getByRole('radio').nth(tokenIndex).click();
  const ready = page.getByRole('button', { name: 'Marcar Preparado' });
  await expect(ready).toBeEnabled({ timeout: 10_000 });
  await ready.click();
  await expect(page.getByRole('button', { name: 'Marcar No preparado' })).toBeVisible();
}

test('partida activa: banco, turnos, correcciones, reversión y sincronización', async ({ browser }) => {
  test.setTimeout(150_000);

  const ctxs: BrowserContext[] = [];
  const hostCtx = await browser.newContext();
  ctxs.push(hostCtx);
  const host = await hostCtx.newPage();
  const code = await createGame(host);

  const names = ['Marty', 'Doc', 'Jennifer', 'Biff', 'George'];
  const pages: Page[] = [];
  for (const n of names) {
    const ctx = await browser.newContext();
    ctxs.push(ctx);
    const p = await ctx.newPage();
    pages.push(p);
    await joinGame(p, code, n);
  }
  // El anfitrión ya tiene ficha; marca preparado. Los demás eligen ficha distinta.
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  for (let i = 0; i < pages.length; i++) await pickAndReady(pages[i]!, i + 1);

  // 3) Iniciar.
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 15_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();

  // Todos entran a la partida activa.
  for (const p of [host, ...pages]) await expect(p.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // 4) Saldos iniciales 3.000 ₥ (visibles para todos).
  await expect(host.getByText('3.000 ₥').first()).toBeVisible();

  // 7) Banca: el anfitrión paga 500 a Marty.
  const bank = host.getByRole('region', { name: 'Banca del anfitrión' });
  await bank.getByLabel('Jugador').selectOption({ label: 'Marty' });
  await bank.getByLabel('Importe').fill('500');
  await bank.getByRole('button', { name: 'Pagar al jugador' }).click();
  // 11) Sincronización: Marty (otro cliente) ve su saldo 3.500 ₥.
  await expect(pages[0]!.getByText('3.500 ₥').first()).toBeVisible({ timeout: 30_000 });

  // 5) Turnos: el jugador en turno finaliza; el número de turno avanza.
  const all = [host, ...pages];
  let current: Page | null = null;
  for (const p of all) {
    if (await p.getByRole('button', { name: 'Finalizar turno' }).isVisible().catch(() => false)) { current = p; break; }
  }
  expect(current).not.toBeNull();
  await current!.getByRole('button', { name: 'Finalizar turno' }).click();
  await expect(host.getByText('Turno 2')).toBeVisible({ timeout: 20_000 });

  // 6) Transferencia entre jugadores: Doc paga 200 a Jennifer.
  const docTransfer = pages[1]!.getByRole('button', { name: 'Enviar' });
  await pages[1]!.getByLabel('Destinatario').selectOption({ label: 'Jennifer' });
  await pages[1]!.getByLabel('Importe').first().fill('200');
  await docTransfer.click();
  await expect(pages[2]!.getByText('3.200 ₥').first()).toBeVisible({ timeout: 30_000 });

  // 8) Ajuste de saldo (corrección del anfitrión) a George = 9.000.
  const details = host.locator('details', { hasText: 'Correcciones del anfitrión' });
  await details.locator('summary').click();
  const adjustForm = details.locator('form').first();
  await adjustForm.getByLabel('Jugador').selectOption({ label: 'George' });
  await adjustForm.getByLabel('Nuevo saldo').fill('9000');
  await adjustForm.getByLabel('Motivo (obligatorio)').fill('ajuste de prueba');
  await adjustForm.getByRole('button', { name: 'Ajustar saldo' }).click();
  await expect(host.getByText('9.000 ₥').first()).toBeVisible({ timeout: 20_000 });

  // 10) Revertir el pago del banco a Marty (vuelve a 3.000).
  await host.getByRole('button', { name: 'Revertir' }).first().click();
  await host.getByRole('dialog', { name: 'Revertir movimiento' }).getByLabel('Motivo (obligatorio)').fill('deshacer pago');
  await host.getByRole('dialog', { name: 'Revertir movimiento' }).getByRole('button', { name: 'Revertir' }).click();
  await expect(pages[0]!.getByText('3.000 ₥').first()).toBeVisible({ timeout: 30_000 });

  // 12-13) Recargar el anfitrión: el estado activo se conserva.
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(host.getByText('Turno 2')).toBeVisible({ timeout: 20_000 });

  for (const c of ctxs) await c.close();
});
