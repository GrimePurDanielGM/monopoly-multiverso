import { test, expect, type Page } from '@playwright/test';

// Mínimo de jugadores configurable a 2 (entorno de pruebas): la UI permite seleccionar 2,
// no se puede iniciar con 1 jugador y sí con 2 preparados.
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Dos jugadores');
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

test('mínimo configurable a 2: no inicia con 1, sí con 2 preparados', async ({ browser }) => {
  test.setTimeout(120_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);

  // La UI permite seleccionar 2 como mínimo.
  await host.getByText('Configuración de la sala').click();
  const minInput = host.getByLabel('Mínimo');
  await expect(minInput).toHaveAttribute('min', '2');
  await minInput.fill('2');
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(minInput).toHaveValue('2');

  // Con 1 jugador (el anfitrión, preparado) NO se puede iniciar.
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeDisabled();

  // Entra un segundo jugador y se prepara: ahora SÍ se puede iniciar.
  const pCtx = await browser.newContext();
  const p2 = await pCtx.newPage();
  await joinGame(p2, code, 'Marty');
  await pickAndReady(p2, 1);
  // Recarga autoritativa del anfitrión (evita depender del tiempo de propagación Realtime).
  await host.reload();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await pCtx.close();
});
