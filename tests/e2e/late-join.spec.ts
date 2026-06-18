import { test, expect, type Page, type BrowserContext } from '@playwright/test';

// Incorporaciones tardías controladas (Fase 2): opción de config, solicitud, aprobación,
// aparición en todos, saldo inicial, al final del orden, rechazo y sala llena.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Tardios');
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
async function enableLateJoin(host: Page, max: number) {
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Máximo').fill(String(max));
  await host.getByRole('checkbox').check();
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByRole('checkbox')).toBeChecked();
}
async function startWith(host: Page, code: string, names: string[]): Promise<{ ctxs: BrowserContext[]; pages: Page[] }> {
  const ctxs: BrowserContext[] = [];
  const pages: Page[] = [];
  for (const n of names) {
    const c = await host.context().browser()!.newContext();
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
  return { ctxs, pages };
}

test('opción desactivada: /j no ofrece entrar como nuevo jugador', async ({ browser }) => {
  test.setTimeout(120_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  const { ctxs } = await startWith(host, code, ['Marty', 'Doc', 'Jennifer', 'Biff', 'George']);

  const fCtx = await browser.newContext();
  const F = await fCtx.newPage();
  await F.goto(`/j/${code}`);
  await expect(F.getByRole('button', { name: 'Recuperar mi jugador' })).toBeVisible({ timeout: 20_000 });
  await expect(F.getByRole('button', { name: 'Solicitar entrar como nuevo jugador' })).toHaveCount(0);

  await hostCtx.close(); await fCtx.close();
  for (const c of ctxs) await c.close();
});

test('opción activada: solicitar, rechazar, reintentar, aprobar y sala llena', async ({ browser }) => {
  test.setTimeout(180_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await enableLateJoin(host, 7);
  const { ctxs } = await startWith(host, code, ['Marty', 'Doc', 'Jennifer', 'Biff', 'George']);

  // Séptimo solicita entrar.
  const gCtx = await browser.newContext();
  const G = await gCtx.newPage();
  await G.goto(`/j/${code}`);
  await G.getByRole('button', { name: 'Solicitar entrar como nuevo jugador' }).click();
  await G.waitForURL(new RegExp(`/sala/${code}/entrar$`), { timeout: 20_000 });
  await G.getByPlaceholder('Marty').fill('Septimo');
  await G.getByRole('radiogroup', { name: 'Ficha del nuevo jugador' }).getByRole('radio').first().click();
  await G.getByRole('button', { name: 'Solicitar entrar como nuevo jugador' }).click();
  await expect(G.getByText(/pendiente de aprobación/i)).toBeVisible({ timeout: 20_000 });

  // El anfitrión la ve en la bandeja diferenciada y la RECHAZA.
  await expect(host.getByText(/Solicitudes para entrar en la partida/)).toBeVisible({ timeout: 30_000 });
  await host.getByRole('button', { name: 'Rechazar' }).click();
  await expect(G.getByText(/rechazó tu solicitud/i)).toBeVisible({ timeout: 20_000 });

  // Reintenta y el anfitrión APRUEBA.
  await G.goto(`/sala/${code}/entrar`);
  await G.getByPlaceholder('Marty').fill('Septimo');
  await G.getByRole('radiogroup', { name: 'Ficha del nuevo jugador' }).getByRole('radio').first().click();
  await G.getByRole('button', { name: 'Solicitar entrar como nuevo jugador' }).click();
  await expect(host.getByRole('button', { name: 'Aceptar' })).toBeVisible({ timeout: 30_000 });
  await host.getByRole('button', { name: 'Aceptar' }).click();

  // El séptimo entra: saldo inicial y aparece en todos los clientes.
  await G.waitForURL(new RegExp(`/sala/${code}$`), { timeout: 30_000 });
  await expect(G.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(G.getByText('3.000 ₥').first()).toBeVisible();
  await expect(host.getByText('Septimo').first()).toBeVisible({ timeout: 20_000 });
  await expect(ctxs[0] && (await ctxs[0].pages())[0]!.getByText('Septimo').first()).toBeVisible({ timeout: 20_000 });

  // Recarga conserva identidad/saldo.
  await G.reload();
  await expect(G.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(G.getByText('3.000 ₥').first()).toBeVisible();

  // Sala llena (max 7, ya hay 7): un octavo solicitante es rechazado por el servidor.
  const hCtx = await browser.newContext();
  const H = await hCtx.newPage();
  await H.goto(`/sala/${code}/entrar`);
  await H.getByPlaceholder('Marty').fill('Octavo');
  await H.getByRole('radiogroup', { name: 'Ficha del nuevo jugador' }).getByRole('radio').first().click();
  await H.getByRole('button', { name: 'Solicitar entrar como nuevo jugador' }).click();
  await expect(H.getByRole('alert')).toBeVisible({ timeout: 20_000 });

  await hostCtx.close(); await gCtx.close(); await hCtx.close();
  for (const c of ctxs) await c.close();
});
