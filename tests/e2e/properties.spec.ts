import { test, expect, type Page } from '@playwright/test';

// Propiedades (Fase 3 corrección): compra con aprobación del anfitrión, subasta, alquiler,
// bancarrota frente a jugador y estado espectador. Anfitrión + 1 jugador (mínimo 2).
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
function propRow(page: Page, name: string) {
  return page.getByRole('region', { name: 'Propiedades' }).getByRole('listitem').filter({ hasText: name });
}
const ESTACION = 'Estación del Norte';
const PRADO = 'Paseo del Prado';

test('propiedades: compra con aprobación, subasta, bancarrota y espectador', async ({ browser }) => {
  test.setTimeout(180_000);
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
  await host.reload();
  await expect(host.getByRole('button', { name: 'Iniciar partida' })).toBeEnabled({ timeout: 20_000 });
  await host.getByRole('button', { name: 'Iniciar partida' }).click();
  await host.getByRole('button', { name: 'Iniciar', exact: true }).click();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });

  // ── B solicita comprar la estación; el anfitrión la aprueba.
  await propRow(B, ESTACION).getByRole('button', { name: 'Solicitar compra' }).click();
  await B.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(host.getByText('Solicitudes de compra')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Aprobar' }).click();
  await B.reload();
  await expect(propRow(B, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  // ── B solicita Paseo del Prado; el anfitrión inicia subasta en vez de aprobar.
  await propRow(B, PRADO).getByRole('button', { name: 'Solicitar compra' }).click();
  await B.getByRole('dialog', { name: 'Solicitar compra' }).getByRole('button', { name: 'Solicitar compra' }).click();
  await host.reload();
  await expect(host.getByText('Solicitudes de compra')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de compra' }).getByRole('button', { name: 'Subastar' }).click();
  await expect(host.getByText('Subastas activas')).toBeVisible({ timeout: 20_000 });

  // ── B puja; el anfitrión cierra y se adjudica (B único postor).
  await B.reload();
  await expect(B.getByText('Subastas activas')).toBeVisible({ timeout: 20_000 });
  await B.getByRole('region', { name: 'Subastas activas' }).getByLabel('Tu puja').fill('100');
  await B.getByRole('region', { name: 'Subastas activas' }).getByRole('button', { name: 'Pujar' }).click();
  await host.reload();
  await expect(host.getByText(/Puja: 100/)).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Subastas activas' }).getByRole('button', { name: 'Cerrar subasta' }).click();
  await B.reload();
  await expect(propRow(B, PRADO).getByText('Tuya')).toBeVisible({ timeout: 20_000 });

  // ── B se declara en bancarrota frente al anfitrión; el anfitrión aprueba.
  await B.getByRole('button', { name: 'Declararme en bancarrota' }).click();
  const dlg = B.getByRole('dialog', { name: 'Declararme en bancarrota' });
  await dlg.getByText('Bancarrota por impago a otro jugador').click();
  await dlg.getByLabel('Acreedor').selectOption({ label: 'Anfitrión' });
  await dlg.getByPlaceholder(/motivo/i).fill('Sin liquidez');
  await dlg.getByRole('button', { name: 'Declararme en bancarrota' }).click();
  await host.reload();
  await expect(host.getByText('Solicitudes de bancarrota')).toBeVisible({ timeout: 20_000 });
  await host.getByRole('region', { name: 'Solicitudes de bancarrota' }).getByRole('button', { name: 'Aprobar' }).click();

  // ── B queda como espectador; sus propiedades pasaron al anfitrión.
  await B.reload();
  await expect(B.getByText(/Estás en bancarrota\. Puedes seguir consultando/)).toBeVisible({ timeout: 20_000 });
  await expect(B.getByRole('button', { name: 'Declararme en bancarrota' })).toHaveCount(0);
  await host.reload();
  await expect(host.getByText(`Partida ${code}`)).toBeVisible({ timeout: 20_000 });
  await expect(propRow(host, ESTACION).getByText('Tuya')).toBeVisible({ timeout: 20_000 }); // de B al anfitrión
  await expect(propRow(host, PRADO).getByText('Tuya')).toBeVisible({ timeout: 20_000 });
  await expect(host.getByText('Marty').first()).toBeVisible();
  await expect(host.getByText('En bancarrota').first()).toBeVisible({ timeout: 20_000 });

  await hostCtx.close();
  await bCtx.close();
});
