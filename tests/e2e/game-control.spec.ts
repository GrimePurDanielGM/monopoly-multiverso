import { test, expect, type Page, type BrowserContext } from '@playwright/test';

// Control de partida (Fase 2): pausar bloquea a todos, reanudar continúa, finalizar es terminal.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Control');
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
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
}

test('control: pausar bloquea, reanudar continúa, finalizar es terminal', async ({ browser }) => {
  test.setTimeout(160_000);

  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  const names = ['Marty', 'Doc', 'Jennifer', 'Biff', 'George'];
  const ctxs: BrowserContext[] = [];
  const pages: Page[] = [];
  for (const n of names) {
    const c = await browser.newContext();
    ctxs.push(c);
    const p = await c.newPage();
    pages.push(p);
    await joinGame(p, code, n);
  }
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  for (let i = 0; i < pages.length; i++) await pickAndReady(pages[i]!, i + 1);
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 15_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  const marty = pages[0]!;

  // ── Pausar: confirmación, banner en todos, acciones deshabilitadas.
  await host.getByRole('button', { name: 'Pausar partida' }).click();
  await host.getByRole('dialog', { name: 'Pausar partida' }).getByRole('button', { name: 'Pausar' }).click();
  await expect(host.getByText('Partida en pausa')).toBeVisible({ timeout: 20_000 });
  await expect(marty.getByText('Partida en pausa')).toBeVisible({ timeout: 20_000 });
  await expect(marty.getByRole('button', { name: 'Enviar' })).toBeDisabled();

  // ── Reanudar: vuelve a estar en curso.
  await host.getByRole('button', { name: 'Reanudar partida' }).click();
  await expect(host.getByRole('button', { name: 'Pausar partida' })).toBeVisible({ timeout: 20_000 });
  await expect(marty.getByText('Partida en pausa')).toHaveCount(0, { timeout: 20_000 });

  // ── Finalizar: confirmación fuerte; estado terminal en todos.
  await host.getByRole('button', { name: 'Finalizar partida' }).click();
  const dlg = host.getByRole('dialog', { name: 'Finalizar partida' });
  await expect(dlg.getByRole('button', { name: 'No, continuar jugando' })).toBeFocused();
  await dlg.getByRole('button', { name: 'Sí, finalizar partida' }).click();
  await expect(host.getByRole('heading', { name: 'Partida finalizada' })).toBeVisible({ timeout: 20_000 });
  await expect(marty.getByRole('heading', { name: 'Partida finalizada' })).toBeVisible({ timeout: 20_000 });
  await expect(marty.getByRole('button', { name: 'Finalizar turno' })).toHaveCount(0);

  // ── Recargar conserva el estado finalizado.
  await marty.reload();
  await expect(marty.getByRole('heading', { name: 'Partida finalizada' })).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  for (const c of ctxs) await c.close();
});
