import { test, expect, type Page, type BrowserContext } from '@playwright/test';

// Salida/expulsión de jugador en partida activa (Fase 2): abandonar (saldo a la banca),
// expulsar (banca / reparto), salir del orden, persistencia tras recargar.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Salidas');
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
function row(page: Page, name: string) {
  return page.getByRole('list', { name: 'Saldos de los jugadores' }).getByRole('listitem').filter({ hasText: name });
}

test('salida y expulsión: abandonar a la banca, expulsar y repartir, persistencia', async ({ browser }) => {
  test.setTimeout(160_000);

  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  // Mínimo configurable a 2: iniciamos con anfitrión + 3 jugadores (cobertura completa, menos contextos).
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByLabel('Mínimo')).toHaveValue('2');
  const names = ['Marty', 'Doc', 'Jennifer'];
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
  await host.reload(); // estado autoritativo (evita depender de la propagación Realtime en WebKit)
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  const [marty, doc] = pages as [Page, Page, Page]; // Jennifer se expulsa desde la fila del anfitrión

  // ── El anfitrión EXPULSA a Doc (saldo a la banca, opción por defecto).
  await row(host, 'Doc').getByRole('button', { name: 'Sacar jugador' }).click();
  const removeDlg = host.getByRole('dialog', { name: 'Sacar jugador' });
  await expect(removeDlg.getByLabel('Devolver a la banca')).toBeChecked();
  await removeDlg.getByRole('button', { name: 'Sí, sacar jugador' }).click();
  await expect(row(host, 'Doc')).toHaveCount(0, { timeout: 20_000 });           // fuera de la lista
  // Doc deja de participar: su pantalla pasa a "no formas parte" (vía Realtime).
  await expect(doc.getByText(/Esta partida ya ha comenzado/)).toBeVisible({ timeout: 25_000 });

  // ── Un jugador SOLICITA abandonar (Marty tiene saldo): el anfitrión lo aprueba (saldo a la banca).
  await row(marty, 'Marty').getByRole('button', { name: 'Abandonar partida' }).click();
  const leaveDlg = marty.getByRole('dialog', { name: 'Abandonar partida' });
  await expect(leaveDlg.getByRole('button', { name: 'No, seguir jugando' })).toBeFocused();
  await leaveDlg.getByRole('button', { name: 'Sí, solicitar abandono' }).click();
  await host.reload();
  await expect(host.getByText('Solicitudes de abandono')).toBeVisible({ timeout: 25_000 });
  await host.getByRole('region', { name: 'Solicitudes de abandono' }).getByRole('button', { name: 'Aprobar · a la banca' }).click();
  await expect(marty.getByText(/Esta partida ya ha comenzado/)).toBeVisible({ timeout: 25_000 });
  await expect(row(host, 'Marty')).toHaveCount(0, { timeout: 20_000 });

  // ── El anfitrión EXPULSA a Jennifer REPARTIENDO el saldo entre los restantes (solo el host).
  // Único restante = el anfitrión: recibe los 3.000 de Jennifer (3.000 -> 6.000), sin resto.
  await row(host, 'Jennifer').getByRole('button', { name: 'Sacar jugador' }).click();
  const distDlg = host.getByRole('dialog', { name: 'Sacar jugador' });
  await distDlg.getByLabel('Repartir entre jugadores restantes').check();
  await distDlg.getByRole('button', { name: 'Sí, sacar jugador' }).click();
  await expect(row(host, 'Jennifer')).toHaveCount(0, { timeout: 20_000 });
  await expect(row(host, 'Anfitrión').getByText('6.000 €')).toBeVisible({ timeout: 20_000 });   // 3.000 + 3.000

  // ── Persistencia: recargar conserva el estado final.
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(row(host, 'Anfitrión').getByText('6.000 €')).toBeVisible({ timeout: 20_000 });
  await expect(row(host, 'Doc')).toHaveCount(0);
  await expect(row(host, 'Marty')).toHaveCount(0);
  await expect(row(host, 'Jennifer')).toHaveCount(0);

  await hostCtx.close();
  for (const c of ctxs) await c.close();
});
