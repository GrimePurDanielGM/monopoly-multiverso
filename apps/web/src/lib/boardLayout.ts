// Disposición de un tablero cuadrado (tipo Monopoly) a partir del nº de casillas del anillo.
// Coloca las casillas en el perímetro de una rejilla G×G empezando en la esquina inferior derecha
// (índice 0 = Salida) y avanzando en sentido antihorario (izquierda por la fila inferior). Exacto
// cuando N es múltiplo de 4 (Classic = 40 → 11×11); para otros tamaños deja huecos al final del anillo.

export interface GridCell {
  index: number;
  row: number; // 1-based para CSS grid-row
  col: number; // 1-based para CSS grid-column
}
export interface BoardGrid {
  size: number; // G (celdas por lado)
  cells: GridCell[];
}

export function boardGrid(ringSize: number): BoardGrid {
  const n = Math.max(1, ringSize);
  let g = Math.floor(n / 4) + 1;
  while (4 * (g - 1) < n) g++;
  const coords: [number, number][] = [];
  for (let c = g - 1; c >= 0; c--) coords.push([g - 1, c]); // fila inferior: esquina inf-dcha → inf-izda
  for (let r = g - 2; r >= 0; r--) coords.push([r, 0]);     // columna izquierda: → esquina sup-izda
  for (let c = 1; c <= g - 1; c++) coords.push([0, c]);     // fila superior: → esquina sup-dcha
  for (let r = 1; r <= g - 2; r++) coords.push([r, g - 1]); // columna derecha: → vuelta al inicio
  const cells = coords.slice(0, n).map(([r, c], index) => ({ index, row: r + 1, col: c + 1 }));
  return { size: g, cells };
}

/** ¿Es una casilla de esquina del anillo? (salida, cárcel, parking, ir-a-la-cárcel aproximados). */
export function isCornerIndex(index: number, ringSize: number): boolean {
  if (index === 0) return true;
  const q = ringSize / 4;
  return [Math.round(q), Math.round(2 * q), Math.round(3 * q)].includes(index);
}
