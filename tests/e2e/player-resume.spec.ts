import { test, expect, type Page, type BrowserContext } from '@playwright/test';

// Reanudación de jugador normal en partida activa: misma sesión (auto-resume),
// acceso visible a "Recuperar mi jugador" y recuperación desde otra sesión.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Reanudación');
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

test('reanudación de jugador: misma sesión, acceso visible y recuperación', async ({ browser }) => {
  test.setTimeout(180_000);

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

  // ── Caso A: Marty cierra la pestaña y reabre con la MISMA sesión -> auto-resume.
  const martyCtx = ctxs[0]!;
  await pages[0]!.close();
  const marty2 = await martyCtx.newPage();
  await marty2.goto(`/j/${code}`);
  await marty2.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
  await expect(marty2.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(marty2.getByText('3.000 €').first()).toBeVisible(); // saldo conservado
  await expect(marty2.getByRole('button', { name: 'Unirme' })).toHaveCount(0); // sin re-unirse ni elegir ficha

  // ── Acceso visible desde una sesión NUEVA: /j/{CODE} y Home ofrecen "Recuperar mi jugador".
  const fCtx = await browser.newContext();
  const F = await fCtx.newPage();
  await F.goto(`/j/${code}`);
  await expect(F.getByRole('button', { name: 'Recuperar mi jugador' })).toBeVisible({ timeout: 20_000 });
  await expect(F.getByRole('button', { name: 'Unirme' })).toHaveCount(0);
  await F.goto('/');
  await expect(F.getByRole('button', { name: 'Recuperar mi jugador' })).toBeVisible();

  // ── Caso B: F recupera la identidad de Marty; el anfitrión aprueba.
  await F.goto(`/j/${code}`);
  await F.getByRole('button', { name: 'Recuperar mi jugador' }).click();
  await F.waitForURL(new RegExp(`/sala/${code}/recuperar-jugador$`), { timeout: 20_000 });
  await F.getByRole('radiogroup', { name: 'Tu identidad anterior' }).getByRole('radio', { name: 'Marty' }).click();
  await F.getByRole('button', { name: 'Solicitar recuperación' }).click();

  // El anfitrión ve la solicitud en la pantalla activa y la aprueba.
  await expect(host.getByRole('button', { name: 'Aceptar' })).toBeVisible({ timeout: 30_000 });
  await host.getByRole('button', { name: 'Aceptar' }).click();
  await host.getByRole('button', { name: 'Aprobar' }).click();

  // F entra a la partida activa como Marty (no se crea jugador nuevo).
  await F.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
  await expect(F.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // La sesión anterior pierde el control: al recargar ya no es miembro y solo se le ofrece recuperar.
  await marty2.reload();
  await expect(marty2.getByRole('link', { name: 'Recuperar mi jugador' })).toBeVisible({ timeout: 20_000 });
  await expect(marty2.getByRole('button', { name: 'Finalizar turno' })).toHaveCount(0);

  await hostCtx.close();
  await fCtx.close();
  for (const c of ctxs) await c.close();
});
