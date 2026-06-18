import { test, expect, type Page } from '@playwright/test';

// E2E multiusuario contra Supabase local real. Requiere:
//   - supabase start (Realtime + RPC + Edge locales)
//   - app construida con VITE_SUPABASE_URL/ANON locales y VITE_PUBLIC_BASE_URL=http://localhost:4173
//   - pnpm preview en :4173
// El escenario principal usa 6 contextos de navegador independientes (anfitrión + 5).

const PIN = '246813'; // 6 dígitos, no trivial

async function createGame(page: Page, gameName = 'Partida E2E'): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill(gameName);
  await page.getByPlaceholder('Daniel').fill('Anfitrión');
  await page.getByRole('radiogroup', { name: 'Ficha del anfitrión' }).getByRole('radio').first().click();
  await page.getByPlaceholder('••••••').fill(PIN);
  await page.getByRole('button', { name: 'Crear y entrar' }).click();
  await page.waitForURL(/\/sala\/[A-Z0-9]{6}$/);
  const m = page.url().match(/\/sala\/([A-Z0-9]{6})$/);
  if (!m) throw new Error('no se obtuvo el código de sala');
  return m[1];
}

async function joinGame(page: Page, code: string, name: string) {
  await page.goto('/unirse');
  await page.getByPlaceholder('ABC123').fill(code);
  await page.getByRole('button', { name: 'Buscar sala' }).click();
  await page.getByPlaceholder('Marty').fill(name);
  await page.getByRole('button', { name: 'Unirme' }).click();
  await page.waitForURL(new RegExp(`/sala/${code}$`));
}

/** Elige la ficha en la posición dada (distinta por jugador, evita colisiones) y marca Preparado. */
async function pickTokenAndReady(page: Page, tokenIndex: number) {
  await page.getByRole('radiogroup', { name: 'Ficha', exact: true }).getByRole('radio').nth(tokenIndex).click();
  const readyBtn = page.getByRole('button', { name: 'Marcar Preparado' });
  await expect(readyBtn).toBeEnabled({ timeout: 10_000 });
  await readyBtn.click();
  await expect(page.getByRole('button', { name: 'Marcar No preparado' })).toBeVisible();
}

test('escenario principal: anfitrión crea, comparte, 5 se unen, todos listos, inicio', async ({ browser }) => {
  test.setTimeout(120_000);

  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  expect(code).toMatch(/^[A-Z0-9]{6}$/);

  // Sección compartir: código, enlace canónico y QR (sin secretos).
  await expect(host.getByText(code, { exact: false }).first()).toBeVisible();
  const qr = host.getByAltText(/Código QR del enlace de la sala/i);
  await expect(qr).toBeVisible();
  await expect(host.getByText(`localhost:4173/j/${code}`, { exact: false })).toBeVisible();
  const qrAlt = (await qr.getAttribute('alt')) ?? '';
  expect(qrAlt).not.toMatch(/eyJ|service_role|pepper|sb_secret_/i);

  // El anfitrión elige su ficha en la creación; en la sala solo marca preparado.
  const hostReady = host.getByRole('button', { name: 'Marcar Preparado' });
  await expect(hostReady).toBeEnabled();
  await hostReady.click();

  // 5 jugadores en contextos independientes.
  const names = ['Marty', 'Doc', 'Jennifer', 'Biff', 'George'];
  const contexts = [];
  const pages: Page[] = [];
  for (const n of names) {
    const ctx = await browser.newContext();
    const p = await ctx.newPage();
    contexts.push(ctx);
    pages.push(p);
    await joinGame(p, code, n);
  }

  // Cada uno elige una ficha distinta (posiciones 1..5; el anfitrión tiene la 0) y marca preparado.
  for (let i = 0; i < pages.length; i++) {
    await pickTokenAndReady(pages[i]!, i + 1);
  }

  // El anfitrión ve a los 6 y el contador de preparados llega a 6/6 (exact evita el checklist del panel).
  await expect(host.getByText('6/6', { exact: true })).toBeVisible({ timeout: 15_000 });
  for (const n of ['Anfitrión', ...names]) {
    await expect(host.getByText(n, { exact: false }).first()).toBeVisible();
  }

  // El anfitrión inicia la partida.
  const startBtn = host.getByRole('button', { name: 'Iniciar partida' });
  await expect(startBtn).toBeEnabled({ timeout: 10_000 });
  await startBtn.click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();

  // Todos (anfitrión + 5) entran a la partida activa (Fase 2: pantalla de partida).
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 15_000 });
  for (const p of pages) {
    await expect(p.getByText(`Partida ${code}`)).toBeVisible({ timeout: 15_000 });
  }

  await hostCtx.close();
  for (const ctx of contexts) await ctx.close();
});

test('código inexistente muestra error y no entra', async ({ page }) => {
  await page.goto('/unirse');
  await page.getByPlaceholder('ABC123').fill('ABC234');
  await page.getByRole('button', { name: 'Buscar sala' }).click();
  await expect(page.getByRole('alert')).toBeVisible();
  await expect(page).toHaveURL(/\/unirse$/);
});

test('unirse por enlace /j/:code hace la vista previa automática', async ({ browser }) => {
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host, 'Sala enlace');

  const ctx = await browser.newContext();
  const p = await ctx.newPage();
  await p.goto(`/j/${code}`);
  // La vista previa aparece sola: nombre de la sala + formulario de nombre.
  await expect(p.getByText('Sala enlace')).toBeVisible({ timeout: 10_000 });
  await expect(p.getByPlaceholder('Marty')).toBeVisible();

  await hostCtx.close();
  await ctx.close();
});

test('offline muestra aviso discreto sin pantalla en blanco y se recupera', async ({ page, context }) => {
  await page.goto('/');
  await expect(page.getByRole('heading', { name: 'Monopoly: El Multiverso' })).toBeVisible();

  // No prometemos offline completo: al perder red mostramos un aviso discreto y la UI sigue visible.
  await context.setOffline(true);
  await expect(page.getByText(/Sin conexión\. Reintentaremos al volver\./)).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Monopoly: El Multiverso' })).toBeVisible();

  await context.setOffline(false);
  await expect(page.getByText(/Sin conexión\. Reintentaremos al volver\./)).toBeHidden();
});
