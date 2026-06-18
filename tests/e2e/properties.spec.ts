import { test, expect, type Page } from '@playwright/test';

// Propiedades (Fase 3): comprar, pagar alquiler, pausa bloquea, salida devuelve a banca,
// recompra y persistencia tras recargar. Anfitrión + 1 jugador (mínimo 2).
const PIN = '246813';

async function createGame(page: Page): Promise<string> {
  await page.goto('/crear');
  await page.getByPlaceholder('La partida del sábado').fill('Propiedades');
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
const ESTACION = 'Estación Sur';
function propRow(page: Page, name: string) {
  return page.getByRole('region', { name: 'Propiedades' }).getByRole('listitem').filter({ hasText: name });
}

test('propiedades: comprar, alquiler, pausa, salida a banca, recompra y persistencia', async ({ browser }) => {
  test.setTimeout(160_000);
  const hostCtx = await browser.newContext();
  const host = await hostCtx.newPage();
  const code = await createGame(host);
  await host.getByText('Configuración de la sala').click();
  await host.getByLabel('Mínimo').fill('2');
  await host.getByRole('button', { name: 'Guardar configuración' }).click();
  await expect(host.getByLabel('Mínimo')).toHaveValue('2');

  const bCtx = await browser.newContext();
  const B = await bCtx.newPage();
  await joinGame(B, code, 'Marty');
  await host.getByRole('button', { name: 'Marcar Preparado' }).click();
  await pickAndReady(B, 1);
  await host.reload(); // recarga autoritativa (evita depender de la propagación Realtime en WebKit)
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // ── B compra la estación.
  await propRow(B, ESTACION).getByRole('button', { name: 'Comprar' }).click();
  await B.getByRole('dialog', { name: 'Comprar propiedad' }).getByRole('button', { name: 'Comprar' }).click();
  await expect(propRow(B, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  // ── El anfitrión ve la propiedad como ajena (sin "Comprar") y paga el alquiler.
  await expect(propRow(host, ESTACION).getByText(/Propiedad de/)).toBeVisible({ timeout: 20_000 });
  await expect(propRow(host, ESTACION).getByRole('button', { name: 'Comprar' })).toHaveCount(0);
  await propRow(host, ESTACION).getByRole('button', { name: 'Pagar alquiler' }).click();
  await host.getByRole('dialog', { name: 'Pagar alquiler' }).getByRole('button', { name: 'Pagar alquiler' }).click();
  // El anfitrión paga 25 de alquiler: 3.000 -> 2.975.
  await expect(host.getByText('2.975 ₥').first()).toBeVisible({ timeout: 20_000 });

  // ── Pausa: las acciones de propiedades quedan deshabilitadas.
  await host.getByRole('button', { name: 'Pausar partida' }).click();
  await host.getByRole('dialog', { name: 'Pausar partida' }).getByRole('button', { name: 'Pausar' }).click();
  await expect(host.getByText('Partida en pausa', { exact: true })).toBeVisible({ timeout: 20_000 });
  await expect(host.getByText(/solo puedes consultar las propiedades/i)).toBeVisible();
  await host.getByRole('button', { name: 'Reanudar partida' }).click();
  await expect(host.getByText('Partida en pausa', { exact: true })).toHaveCount(0, { timeout: 20_000 });

  // ── B abandona: su propiedad vuelve a banca (disponible) y el anfitrión la recompra.
  await B.reload(); // estado autoritativo (versión actual) tras los cambios del anfitrión
  await expect(B.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await B.getByRole('list', { name: 'Saldos de los jugadores' }).getByRole('listitem').filter({ hasText: 'Marty' })
    .getByRole('button', { name: 'Abandonar partida' }).click();
  await B.getByRole('dialog', { name: 'Abandonar partida' }).getByRole('button', { name: 'Sí, abandonar partida' }).click();
  await expect(B.getByText(/Esta partida ya ha comenzado/)).toBeVisible({ timeout: 25_000 }); // B salió
  await host.reload(); // recarga autoritativa: la propiedad de B vuelve a estar disponible
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(propRow(host, ESTACION).getByText('Disponible')).toBeVisible({ timeout: 20_000 });

  await propRow(host, ESTACION).getByRole('button', { name: 'Comprar' }).click();
  await host.getByRole('dialog', { name: 'Comprar propiedad' }).getByRole('button', { name: 'Comprar' }).click();
  await expect(propRow(host, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  // ── Persistencia: recargar conserva la posesión.
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(propRow(host, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
