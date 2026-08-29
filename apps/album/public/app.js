// Álbum familiar — lógica de la web (sin dependencias)

import { crearZip } from './zip.js';

const $ = (id) => document.getElementById(id);

const ui = {
  nombreAlbum: $('nombreAlbum'),
  subtitulo: $('subtitulo'),
  aviso: $('avisoConexion'),
  seccionPendientes: $('seccionPendientes'),
  ayudaPendientes: $('ayudaPendientes'),
  gridPendientes: $('gridPendientes'),
  detalleEnICloud: $('detalleEnICloud'),
  gridEnICloud: $('gridEnICloud'),
  gridAlbum: $('gridAlbum'),
  estadoAlbum: $('estadoAlbum'),
  btnRefrescar: $('btnRefrescar'),
  btnAnfitrion: $('btnAnfitrion'),
  btnSeleccionar: $('btnSeleccionar'),
  barraSeleccion: $('barraSeleccion'),
  textoSeleccion: $('textoSeleccion'),
  btnSeleccionarTodas: $('btnSeleccionarTodas'),
  btnDescargarLote: $('btnDescargarLote'),
  btnCancelarSeleccion: $('btnCancelarSeleccion'),
  btnSubir: $('btnSubir'),
  dlgSubir: $('dlgSubir'),
  formSubir: $('formSubir'),
  campoNombre: $('campoNombre'),
  campoComentario: $('campoComentario'),
  campoArchivos: $('campoArchivos'),
  resumenArchivos: $('resumenArchivos'),
  progresoSubida: $('progresoSubida'),
  barraSubida: $('barraSubida'),
  textoProgreso: $('textoProgreso'),
  notaSubida: $('notaSubida'),
  btnEnviarSubida: $('btnEnviarSubida'),
  btnCancelarSubida: $('btnCancelarSubida'),
  dlgVisor: $('dlgVisor'),
  visorContenido: $('visorContenido'),
  visorAutor: $('visorAutor'),
  visorFecha: $('visorFecha'),
  visorTexto: $('visorTexto'),
  btnDescargar: $('btnDescargar'),
  btnEliminarVisor: $('btnEliminarVisor'),
  btnCerrarVisor: $('btnCerrarVisor'),
  btnAnterior: $('btnAnterior'),
  btnSiguiente: $('btnSiguiente'),
  dlgAnfitrion: $('dlgAnfitrion'),
  formAnfitrion: $('formAnfitrion'),
  campoPin: $('campoPin'),
  notaAnfitrion: $('notaAnfitrion'),
  btnSalirAnfitrion: $('btnSalirAnfitrion'),
  btnCancelarAnfitrion: $('btnCancelarAnfitrion'),
  toast: $('toast'),
  estadoFondo: $('estadoFondo'),
};

const estado = {
  album: null,        // respuesta de /api/album
  uploads: [],        // respuesta de /api/uploads
  adminDisponible: false,
  modo: 'servidor',   // 'servidor' (Node propio) | 'vercel' (serverless + Supabase)
  subidasDisponibles: true,
  avisoConfiguracion: null,
  visorLista: [],
  visorIndice: 0,
  cargando: false,
  seleccionando: false,
  seleccion: new Map(), // clave → descriptor de descarga
};

// ------------------------------------------------------------------ utilidades
function toast(mensaje, ms = 3200) {
  ui.toast.textContent = mensaje;
  ui.toast.hidden = false;
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => { ui.toast.hidden = true; }, ms);
}

function pinGuardado() {
  try { return sessionStorage.getItem('adminPin') || ''; } catch { return ''; }
}

function esAnfitrion() { return Boolean(pinGuardado()); }

// Cada subida devuelve una clave secreta: guardándola en este dispositivo,
// quien subió la foto puede borrarla luego sin necesitar el PIN del anfitrión.
function misSubidas() {
  try { return JSON.parse(localStorage.getItem('misSubidas') || '{}'); } catch { return {}; }
}

function guardarMiSubida(id, clave) {
  if (!id || !clave) return;
  try {
    const mias = misSubidas();
    mias[id] = clave;
    const ids = Object.keys(mias);
    for (const viejo of ids.slice(0, Math.max(0, ids.length - 200))) delete mias[viejo];
    localStorage.setItem('misSubidas', JSON.stringify(mias));
  } catch { /* modo privado */ }
}

function claveDe(id) { return misSubidas()[id] || null; }

function olvidarMiSubida(id) {
  try {
    const mias = misSubidas();
    delete mias[id];
    localStorage.setItem('misSubidas', JSON.stringify(mias));
  } catch { /* nada */ }
}

function haceTiempo(ms) {
  const seg = Math.max(0, Math.round((Date.now() - ms) / 1000));
  if (seg < 60) return 'hace un momento';
  const min = Math.round(seg / 60);
  if (min < 60) return `hace ${min} min`;
  const h = Math.round(min / 60);
  if (h < 24) return `hace ${h} h`;
  return `hace ${Math.round(h / 24)} días`;
}

const fmtDia = new Intl.DateTimeFormat('es-ES', { weekday: 'long', day: 'numeric', month: 'long' });
const fmtDiaConAnio = new Intl.DateTimeFormat('es-ES', { day: 'numeric', month: 'long', year: 'numeric' });
const fmtHora = new Intl.DateTimeFormat('es-ES', { hour: '2-digit', minute: '2-digit' });

function diaLegible(iso) {
  if (!iso) return '';
  const fecha = new Date(iso);
  if (Number.isNaN(fecha.getTime())) return '';
  const conAnio = fecha.getFullYear() !== new Date().getFullYear();
  return (conAnio ? fmtDiaConAnio : fmtDia).format(fecha);
}

function fechaHoraLegible(iso) {
  if (!iso) return '';
  const fecha = new Date(iso);
  if (Number.isNaN(fecha.getTime())) return '';
  return `${diaLegible(iso)}, ${fmtHora.format(fecha)}`;
}

function nombrePropio(nombreCompleto) {
  return String(nombreCompleto || '').trim().split(/\s+/)[0] || 'el anfitrión';
}

// ------------------------------------------------------------------ carga datos
async function cargarEstado() {
  try {
    const res = await fetch('/api/estado');
    const datos = await res.json();
    estado.adminDisponible = Boolean(datos.adminDisponible);
    estado.modo = datos.modo === 'vercel' ? 'vercel' : 'servidor';
    estado.subidasDisponibles = datos.subidasDisponibles !== false;
    estado.avisoConfiguracion = datos.avisoConfiguracion || null;
    if (datos.albumUrl) {
      const enlace = document.getElementById('enlaceICloud');
      if (enlace) enlace.href = datos.albumUrl;
    }
  } catch { /* sin conexión: se reintenta con el resto */ }
}

async function cargarAlbum(forzar = false) {
  const res = await fetch(`/api/album${forzar ? '?refrescar=1' : ''}`);
  const datos = await res.json();
  if (!res.ok) throw new Error(datos.error || 'Error al leer el álbum');
  estado.album = datos;
}

async function cargarUploads() {
  const res = await fetch('/api/uploads');
  const datos = await res.json();
  if (res.ok) estado.uploads = datos.uploads || [];
}

async function cargarTodo(forzar = false) {
  if (estado.cargando) return;
  estado.cargando = true;
  ui.btnRefrescar.classList.add('girando');
  try {
    const [resAlbum] = await Promise.allSettled([cargarAlbum(forzar), cargarUploads()]);
    if (resAlbum.status === 'rejected' && !estado.album) {
      ui.estadoAlbum.textContent = '⚠️ ' + resAlbum.reason.message;
      ui.estadoAlbum.hidden = false;
    }
    pintarTodo();
  } finally {
    estado.cargando = false;
    ui.btnRefrescar.classList.remove('girando');
  }
}

// ---------------------------------------------------------------------- pintar
function celdaMiniatura(item, onAbrir, descSeleccion) {
  const celda = document.createElement('button');
  celda.type = 'button';
  celda.className = 'celda';
  celda.addEventListener('click', () => {
    if (estado.seleccionando && descSeleccion) toggleSeleccion(descSeleccion);
    else onAbrir();
  });

  if (item.thumbUrl) {
    const img = document.createElement('img');
    img.loading = 'lazy';
    img.decoding = 'async';
    img.alt = item.caption || 'Foto del álbum';
    img.src = item.thumbUrl;
    celda.appendChild(img);
  } else if (item.isVideo && item.fullUrl) {
    const video = document.createElement('video');
    video.src = item.fullUrl;
    video.preload = 'metadata';
    video.muted = true;
    video.playsInline = true;
    celda.appendChild(video);
  }

  if (item.isVideo) {
    const marca = document.createElement('span');
    marca.className = 'marca-video';
    marca.textContent = '▶';
    celda.appendChild(marca);
  }
  if (item.contributor) {
    const autor = document.createElement('span');
    autor.className = 'marca-autor';
    autor.textContent = item.contributor;
    celda.appendChild(autor);
  }
  if (estado.seleccionando && descSeleccion) {
    const marca = document.createElement('span');
    marca.className = 'marca-sel';
    marca.textContent = '✓';
    celda.appendChild(marca);
    if (estado.seleccion.has(descSeleccion.clave)) celda.classList.add('seleccionada');
  }
  return celda;
}

// ----------------------------------------------- selección y descarga en lote
function descAlbum(foto) {
  return {
    clave: `a:${foto.guid}`,
    nombre: foto.filename || `foto-${String(foto.downloadChecksum || foto.guid).slice(0, 8)}.jpg`,
    tipo: 'icloud',
    checksum: foto.downloadChecksum,
    esVideo: foto.isVideo,
  };
}

function descUpload(u) {
  return {
    clave: `u:${u.id}`,
    nombre: u.originalName || `${u.id}.jpg`,
    tipo: 'upload',
    url: u.originalUrl || u.url,
    esVideo: u.isVideo,
  };
}

function actualizarBarraSeleccion() {
  const n = estado.seleccion.size;
  ui.textoSeleccion.textContent = n === 1 ? '1 seleccionada' : `${n} seleccionadas`;
}

function toggleSeleccion(desc) {
  if (estado.seleccion.has(desc.clave)) estado.seleccion.delete(desc.clave);
  else estado.seleccion.set(desc.clave, desc);
  actualizarBarraSeleccion();
  pintarTodo();
}

function entrarSeleccion() {
  estado.seleccionando = true;
  estado.seleccion.clear();
  ui.barraSeleccion.hidden = false;
  ui.btnSubir.hidden = true;
  actualizarBarraSeleccion();
  pintarTodo();
}

function salirSeleccion() {
  estado.seleccionando = false;
  estado.seleccion.clear();
  ui.barraSeleccion.hidden = true;
  ui.btnSubir.hidden = false;
  pintarTodo();
}

function seleccionarTodas() {
  for (const foto of estado.album?.photos || []) {
    const d = descAlbum(foto);
    estado.seleccion.set(d.clave, d);
  }
  for (const u of estado.uploads) {
    const d = descUpload(u);
    estado.seleccion.set(d.clave, d);
  }
  actualizarBarraSeleccion();
  pintarTodo();
}

async function descargarLote() {
  const items = [...estado.seleccion.values()];
  if (!items.length) return toast('Toca las fotos que quieras descargar');
  if (items.length > 60) return toast('Máximo 60 por descarga: hazlo en un par de tandas 🙏', 5000);

  // Los vídeos de iCloud no caben por el proxy: se descargan individualmente
  const videosICloud = items.filter((i) => i.tipo === 'icloud' && i.esVideo);
  const descargables = items.filter((i) => !(i.tipo === 'icloud' && i.esVideo));

  ui.btnDescargarLote.disabled = true;
  const entradas = [];
  const nombresUsados = new Set();
  let fallos = 0;
  try {
    for (const [n, it] of descargables.entries()) {
      ui.estadoFondo.hidden = false;
      ui.estadoFondo.textContent = `⬇️ Descargando ${n + 1} de ${descargables.length}…`;
      try {
        const url = it.tipo === 'icloud'
          ? `/api/descargar?checksum=${encodeURIComponent(it.checksum)}`
          : it.url;
        const res = await fetch(url);
        if (!res.ok) throw new Error(String(res.status));
        const datos = new Uint8Array(await res.arrayBuffer());
        let nombre = String(it.nombre || 'foto.jpg').trim() || 'foto.jpg';
        if (nombresUsados.has(nombre.toLowerCase())) nombre = `${String(n + 1).padStart(2, '0')}-${nombre}`;
        nombresUsados.add(nombre.toLowerCase());
        entradas.push({ nombre, datos });
      } catch {
        fallos += 1;
      }
    }
    if (!entradas.length) {
      toast('⚠️ No se pudo descargar ninguna foto; inténtalo de nuevo', 5000);
      return;
    }
    ui.estadoFondo.textContent = '📦 Empaquetando ZIP…';
    const zip = crearZip(entradas);
    const blob = new Blob([zip], { type: 'application/zip' });
    const enlace = document.createElement('a');
    enlace.href = URL.createObjectURL(blob);
    enlace.download = `album-${new Date().toISOString().slice(0, 10)}.zip`;
    document.body.appendChild(enlace);
    enlace.click();
    enlace.remove();
    setTimeout(() => URL.revokeObjectURL(enlace.href), 60000);

    const avisos = [];
    if (fallos) avisos.push(`${fallos} fallaron`);
    if (videosICloud.length) avisos.push(`${videosICloud.length} vídeo${videosICloud.length === 1 ? '' : 's'} de iCloud fuera del ZIP (descárgalos de uno en uno)`);
    toast(`ZIP con ${entradas.length} ${entradas.length === 1 ? 'foto' : 'fotos'} listo ✅${avisos.length ? ' · ' + avisos.join(' · ') : ''}`, 5500);
    salirSeleccion();
  } finally {
    ui.btnDescargarLote.disabled = false;
    ui.estadoFondo.hidden = true;
  }
}

function pintarAlbum() {
  ui.gridAlbum.replaceChildren();
  const datos = estado.album;
  if (!datos) return;

  ui.nombreAlbum.textContent = datos.streamName || 'Álbum familiar';
  document.title = datos.streamName || 'Álbum familiar';
  const partes = [`${datos.photos.length} ${datos.photos.length === 1 ? 'elemento' : 'elementos'}`];
  if (datos.owner) partes.push(`álbum de ${nombrePropio(datos.owner)}`);
  if (datos.fetchedAt) partes.push(`actualizado ${haceTiempo(datos.fetchedAt)}`);
  ui.subtitulo.textContent = partes.join(' · ');

  ui.aviso.hidden = !datos.stale;
  if (datos.stale) {
    ui.aviso.textContent = '⚠️ Ahora mismo no se puede conectar con iCloud: estás viendo la última copia guardada.';
  }

  if (!datos.photos.length) {
    ui.estadoAlbum.textContent = 'El álbum de iCloud todavía no tiene fotos.';
    ui.estadoAlbum.hidden = false;
    return;
  }
  ui.estadoAlbum.hidden = true;

  let diaAnterior = null;
  datos.photos.forEach((foto, i) => {
    const dia = diaLegible(foto.dateCreated);
    if (dia && dia !== diaAnterior) {
      const titulo = document.createElement('p');
      titulo.className = 'fecha-grupo';
      titulo.textContent = dia;
      ui.gridAlbum.appendChild(titulo);
      diaAnterior = dia;
    }
    ui.gridAlbum.appendChild(celdaMiniatura(foto, () => abrirVisor(listaVisorAlbum(), i), descAlbum(foto)));
  });
}

function celdaPendiente(upload) {
  const item = uploadComoVisor(upload);
  const celda = celdaMiniatura(item, () => {
    const lista = estado.uploads.filter((u) => u.estado === upload.estado).map(uploadComoVisor);
    const indice = lista.findIndex((v) => v.id === upload.id);
    abrirVisor(lista, Math.max(0, indice));
  }, descUpload(upload));
  celda.classList.add('celda-pendiente');

  const esMia = Boolean(claveDe(upload.id));
  if (!estado.seleccionando && (esAnfitrion() || esMia)) {
    const acciones = document.createElement('span');
    acciones.className = 'acciones-anfitrion';
    if (esAnfitrion() && upload.estado === 'pendiente') {
      const ok = document.createElement('button');
      ok.className = 'ok';
      ok.title = 'Marcar como ya añadida a iCloud';
      ok.textContent = '✓';
      ok.addEventListener('click', (ev) => { ev.stopPropagation(); accionAnfitrion(upload.id, 'en_icloud'); });
      acciones.appendChild(ok);
    }
    const borrar = document.createElement('button');
    borrar.title = 'Borrar esta subida';
    borrar.textContent = '🗑';
    borrar.addEventListener('click', (ev) => {
      ev.stopPropagation();
      if (confirm(`¿Borrar la foto subida por ${upload.uploader || 'alguien'}?`)) {
        if (esMia && !esAnfitrion()) borrarMiSubida(upload.id);
        else accionAnfitrion(upload.id, 'borrar');
      }
    });
    acciones.appendChild(borrar);
    celda.appendChild(acciones);
  }
  return celda;
}

// Borrado sin PIN de una subida hecha desde este mismo dispositivo
async function borrarMiSubida(id) {
  try {
    const res = await fetch('/api/borrar-mia', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ id, clave: claveDe(id) }),
    });
    const datos = await res.json();
    if (!res.ok) throw new Error(datos.error || `Error ${res.status}`);
    olvidarMiSubida(id);
    toast('Foto borrada 🗑');
    await cargarUploads();
    pintarTodo();
  } catch (err) {
    toast(`⚠️ ${err.message}`, 4500);
  }
}

function pintarPendientes() {
  const pendientes = estado.uploads.filter((u) => u.estado === 'pendiente');
  const enICloud = estado.uploads.filter((u) => u.estado === 'en_icloud');

  ui.seccionPendientes.hidden = !pendientes.length && !(esAnfitrion() && enICloud.length);
  ui.gridPendientes.replaceChildren(...pendientes.map(celdaPendiente));

  const anfitrion = estado.album?.owner ? nombrePropio(estado.album.owner) : 'el anfitrión';
  ui.ayudaPendientes.textContent =
    `Estas fotos las ha subido la familia desde esta web y ya se ven aquí. ` +
    `${anfitrion} las pasará al álbum de iCloud desde su iPhone.`;

  const verMarcadas = esAnfitrion() && enICloud.length;
  ui.detalleEnICloud.hidden = !verMarcadas;
  if (verMarcadas) {
    ui.detalleEnICloud.querySelector('summary').textContent =
      `Ver ${enICloud.length} ya marcadas como añadidas a iCloud`;
    ui.gridEnICloud.replaceChildren(...enICloud.map(celdaPendiente));
  }
}

function pintarTodo() {
  pintarAlbum();
  pintarPendientes();
  ui.notaSubida.textContent =
    `Las fotos se verán aquí al momento para toda la familia y ` +
    `${estado.album?.owner ? nombrePropio(estado.album.owner) : 'el anfitrión'} las añadirá al álbum de iCloud.`;
}

// ----------------------------------------------------------------------- visor
function listaVisorAlbum() {
  return (estado.album?.photos || []).map((f) => ({
    ...f,
    // Las fotos se descargan a través del servidor (fuerza "guardar archivo");
    // los vídeos de iCloud en Vercel van directos (demasiado grandes para la función).
    descargarHref:
      f.isVideo && estado.modo === 'vercel'
        ? f.videoUrl || f.fullUrl || null
        : f.downloadChecksum
          ? `/api/descargar?checksum=${encodeURIComponent(f.downloadChecksum)}`
          : f.fullUrl || null,
  }));
}

function uploadComoVisor(u) {
  // Para descargar se prefiere el original en calidad completa si ya terminó
  // de subirse en segundo plano; si no, la versión ligera.
  const descarga = u.originalUrl || u.url;
  const externa = /^https?:\/\//.test(descarga);
  return {
    id: u.id,
    thumbUrl: u.isVideo ? null : u.url,
    fullUrl: u.url,
    videoUrl: u.isVideo ? u.url : null,
    isVideo: u.isVideo,
    caption: u.caption,
    contributor: u.uploader,
    dateCreated: u.uploadedAt,
    // Supabase acepta ?download para forzar la descarga; el servidor propio usa ?descargar
    descargarHref: externa ? `${descarga}?download` : `${descarga}?descargar`,
  };
}

function abrirVisor(lista, indice) {
  if (!lista.length) return;
  estado.visorLista = lista;
  estado.visorIndice = indice;
  pintarVisor();
  if (!ui.dlgVisor.open) ui.dlgVisor.showModal();
}

function pintarVisor() {
  const item = estado.visorLista[estado.visorIndice];
  if (!item) return;
  ui.visorContenido.replaceChildren();

  if (item.isVideo && item.videoUrl) {
    const video = document.createElement('video');
    video.src = item.videoUrl;
    video.controls = true;
    video.autoplay = true;
    video.playsInline = true;
    if (item.posterUrl) video.poster = item.posterUrl;
    ui.visorContenido.appendChild(video);
  } else {
    const img = document.createElement('img');
    img.src = item.fullUrl || item.thumbUrl;
    img.alt = item.caption || 'Foto';
    ui.visorContenido.appendChild(img);
  }

  ui.visorAutor.textContent = item.contributor || '';
  ui.visorFecha.textContent = fechaHoraLegible(item.dateCreated);
  ui.visorTexto.textContent = item.caption || '';
  ui.visorTexto.hidden = !item.caption;
  if (item.descargarHref) {
    ui.btnDescargar.href = item.descargarHref;
    const externa = /^https?:\/\//.test(item.descargarHref) && !item.descargarHref.startsWith(location.origin);
    if (externa) {
      ui.btnDescargar.target = '_blank';
      ui.btnDescargar.rel = 'noopener';
    } else {
      ui.btnDescargar.removeAttribute('target');
      ui.btnDescargar.removeAttribute('rel');
    }
    ui.btnDescargar.hidden = false;
  } else {
    ui.btnDescargar.hidden = true;
  }

  // Eliminar: solo para subidas de la web (tienen id), si son mías o soy anfitrión
  const esSubida = Boolean(item.id);
  ui.btnEliminarVisor.hidden = !(esSubida && (claveDe(item.id) || esAnfitrion()));

  const varios = estado.visorLista.length > 1;
  ui.btnAnterior.hidden = !varios;
  ui.btnSiguiente.hidden = !varios;

  // Precargar las imágenes vecinas para que el paso sea instantáneo
  for (const vecino of [estado.visorIndice - 1, estado.visorIndice + 1]) {
    const v = estado.visorLista[vecino];
    if (v && !v.isVideo && v.fullUrl) new Image().src = v.fullUrl;
  }
}

function moverVisor(paso) {
  const n = estado.visorLista.length;
  if (!n) return;
  estado.visorIndice = (estado.visorIndice + paso + n) % n;
  pintarVisor();
}

// ------------------------------------------------------------------- subidas
function actualizarResumenArchivos() {
  const archivos = ui.campoArchivos.files;
  const selector = ui.campoArchivos.closest('.selector-archivos');
  if (!archivos || !archivos.length) {
    ui.resumenArchivos.textContent = 'Tocar para elegir fotos o vídeos';
    selector.classList.remove('con-archivos');
    return;
  }
  const totalMB = [...archivos].reduce((acc, f) => acc + f.size, 0) / (1024 * 1024);
  ui.resumenArchivos.textContent =
    `${archivos.length} ${archivos.length === 1 ? 'archivo elegido' : 'archivos elegidos'} (${totalMB.toFixed(1)} MB)`;
  selector.classList.add('con-archivos');
}

// Reduce la foto a 2048 px de lado y JPEG antes de subir: pasa de varios MB a
// menos de 1, la subida vuela y para el álbum es calidad de sobra (es la misma
// resolución que sirve iCloud en su web). Si algo falla, se envía el original.
async function optimizarImagen(archivo) {
  const tipo = archivo.type || '';
  if (!tipo.startsWith('image/') || tipo === 'image/gif') return archivo;
  if (archivo.size < 1.2 * 1024 * 1024) return archivo;
  let url = null;
  try {
    url = URL.createObjectURL(archivo);
    const img = await new Promise((resolver, rechazar) => {
      const i = new Image();
      i.onload = () => resolver(i);
      i.onerror = rechazar;
      i.src = url;
    });
    const LADO_MAX = 2048;
    const escala = Math.min(1, LADO_MAX / Math.max(img.naturalWidth, img.naturalHeight));
    const canvas = document.createElement('canvas');
    canvas.width = Math.max(1, Math.round(img.naturalWidth * escala));
    canvas.height = Math.max(1, Math.round(img.naturalHeight * escala));
    canvas.getContext('2d').drawImage(img, 0, 0, canvas.width, canvas.height);
    const blob = await new Promise((resolver) => canvas.toBlob(resolver, 'image/jpeg', 0.85));
    if (!blob || blob.size >= archivo.size) return archivo;
    const nombre = archivo.name.replace(/\.[^.]+$/, '') + '.jpg';
    return new File([blob], nombre, { type: 'image/jpeg' });
  } catch {
    return archivo;
  } finally {
    if (url) URL.revokeObjectURL(url);
  }
}

// Huella del contenido: el servidor la usa para no guardar la misma foto dos veces
async function huellaArchivo(archivo) {
  try {
    const datos = await archivo.arrayBuffer();
    const hash = await crypto.subtle.digest('SHA-256', datos);
    return [...new Uint8Array(hash)].map((b) => b.toString(16).padStart(2, '0')).join('');
  } catch {
    return null;
  }
}

function subirArchivo(archivo, nombre, comentario, onProgreso) {
  return new Promise((resolve, reject) => {
    const datos = new FormData();
    datos.append('nombre', nombre);
    datos.append('comentario', comentario);
    datos.append('fotos', archivo, archivo.name);
    const xhr = new XMLHttpRequest();
    xhr.open('POST', '/api/upload');
    xhr.responseType = 'json';
    xhr.upload.addEventListener('progress', (ev) => {
      if (ev.lengthComputable) onProgreso(ev.loaded / ev.total);
    });
    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve(xhr.response);
      else reject(new Error(xhr.response?.error || `Error ${xhr.status}`));
    });
    xhr.addEventListener('error', () => reject(new Error('Fallo de conexión durante la subida')));
    xhr.send(datos);
  });
}

// Despliegue serverless: pedimos una URL firmada, el archivo va DIRECTO a
// Supabase (sin límite de Vercel) y después confirmamos la subida.
// Si `original` viene, se piden dos URLs: la ligera se sube ya y el original
// queda para la cola en segundo plano. Devuelve {duplicado: true} si esa foto
// exacta ya estaba subida (la huella se calcula sobre el ORIGINAL).
async function subirArchivoFirmado(archivo, nombre, comentario, original, onProgreso) {
  const hash = await huellaArchivo(original || archivo);
  const prep = await fetch('/api/subida-firmada', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      nombre,
      comentario,
      filename: archivo.name,
      contentType: archivo.type || 'application/octet-stream',
      size: archivo.size,
      hash,
      original: original
        ? { filename: original.name, contentType: original.type || 'application/octet-stream', size: original.size }
        : null,
    }),
  });
  const datosPrep = await prep.json();
  if (!prep.ok) throw new Error(datosPrep.error || `Error ${prep.status}`);
  if (datosPrep.duplicado) return { duplicado: true };

  await new Promise((resolve, reject) => {
    const xhr = new XMLHttpRequest();
    xhr.open('PUT', datosPrep.uploadUrl);
    xhr.setRequestHeader('Content-Type', archivo.type || 'application/octet-stream');
    xhr.upload.addEventListener('progress', (ev) => {
      if (ev.lengthComputable) onProgreso(ev.loaded / ev.total);
    });
    xhr.addEventListener('load', () => {
      if (xhr.status >= 200 && xhr.status < 300) resolve();
      else reject(new Error(`La subida a Supabase falló (${xhr.status})`));
    });
    xhr.addEventListener('error', () => reject(new Error('Fallo de conexión durante la subida')));
    xhr.send(archivo);
  });

  const conf = await fetch('/api/subida-confirmar', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: datosPrep.id }),
  });
  const datosConf = await conf.json();
  if (!conf.ok) throw new Error(datosConf.error || `Error ${conf.status}`);
  guardarMiSubida(datosPrep.id, datosPrep.clave);
  if (original && datosPrep.originalUploadUrl) {
    colaOriginales.push({ id: datosPrep.id, archivo: original, uploadUrl: datosPrep.originalUploadUrl });
  }
  return datosConf;
}

// ---------------- cola de originales en segundo plano (calidad completa) ----
const colaOriginales = [];
let procesandoOriginales = false;

async function subirOriginal(tarea) {
  const put = await fetch(tarea.uploadUrl, {
    method: 'PUT',
    headers: { 'Content-Type': tarea.archivo.type || 'application/octet-stream' },
    body: tarea.archivo,
  });
  if (!put.ok) throw new Error(`PUT original ${put.status}`);
  const conf = await fetch('/api/subida-confirmar', {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ id: tarea.id, original: true }),
  });
  if (!conf.ok) throw new Error(`confirmación del original ${conf.status}`);
}

async function procesarOriginales() {
  if (procesandoOriginales || !colaOriginales.length) return;
  procesandoOriginales = true;
  let hechos = 0;
  let fallidos = 0;
  while (colaOriginales.length) {
    ui.estadoFondo.hidden = false;
    ui.estadoFondo.textContent =
      `⬆️ Subiendo originales en calidad completa… (${hechos + 1} de ${hechos + colaOriginales.length})`;
    const tarea = colaOriginales[0];
    try {
      await subirOriginal(tarea);
    } catch {
      try {
        await subirOriginal(tarea); // un reintento; la versión ligera ya está visible
      } catch {
        fallidos += 1;
      }
    }
    colaOriginales.shift();
    hechos += 1;
  }
  ui.estadoFondo.textContent = fallidos
    ? `⚠️ ${fallidos} ${fallidos === 1 ? 'original no se pudo subir' : 'originales no se pudieron subir'} (la versión ligera sí está)`
    : '✅ Originales en calidad completa subidos';
  setTimeout(() => { ui.estadoFondo.hidden = true; }, fallidos ? 6000 : 3000);
  procesandoOriginales = false;
  await cargarUploads();
  pintarTodo();
}

// Avisar si van a cerrar la web con originales aún subiéndose
window.addEventListener('beforeunload', (ev) => {
  if (colaOriginales.length) {
    ev.preventDefault();
    ev.returnValue = '';
  }
});

async function enviarSubida(ev) {
  ev.preventDefault();
  const nombre = ui.campoNombre.value.trim();
  const comentario = ui.campoComentario.value.trim();
  const archivos = [...(ui.campoArchivos.files || [])];
  if (!nombre) { toast('Escribe tu nombre, por favor'); return; }
  if (!archivos.length) { toast('Elige al menos una foto'); return; }

  try { localStorage.setItem('nombreFamiliar', nombre); } catch { /* modo privado */ }

  ui.btnEnviarSubida.disabled = true;
  ui.progresoSubida.hidden = false;

  let subidos = 0;
  let duplicados = 0;
  try {
    for (const [i, original] of archivos.entries()) {
      ui.textoProgreso.textContent = `${i + 1} de ${archivos.length} · preparando…`;
      // En Vercel: la versión ligera se sube ya y el original queda en cola para
      // subirse en segundo plano. Con servidor propio va el original directo.
      const ligera = estado.modo === 'vercel' ? await optimizarImagen(original) : original;
      const originalAparte = ligera !== original ? original : null;
      ui.textoProgreso.textContent = `${i + 1} de ${archivos.length}`;
      const alProgresar = (fraccion) => {
        ui.barraSubida.value = Math.round(((i + fraccion) / archivos.length) * 100);
      };
      if (estado.modo === 'vercel') {
        const resultado = await subirArchivoFirmado(ligera, nombre, comentario, originalAparte, alProgresar);
        if (resultado.duplicado) duplicados += 1;
        else subidos += 1;
      } else {
        const respuesta = await subirArchivo(ligera, nombre, comentario, alProgresar);
        for (const nueva of respuesta.subidas || []) guardarMiSubida(nueva.id, nueva.clave);
        subidos += (respuesta.subidas || []).length;
        duplicados += respuesta.duplicados || 0;
      }
    }
    ui.dlgSubir.close();
    const anfitrion = estado.album?.owner ? nombrePropio(estado.album.owner) : 'el anfitrión';
    const notaDup = duplicados ? ` (${duplicados} ya ${duplicados === 1 ? 'estaba subida' : 'estaban subidas'})` : '';
    const notaFondo = colaOriginales.length ? ' Los originales siguen subiendo en segundo plano…' : '';
    toast(subidos === 0
      ? `Esas fotos ya estaban subidas 👍`
      : subidos === 1
        ? `¡Foto subida!${notaDup} Ya se ve en la web; ${anfitrion} la pasará a iCloud 👍${notaFondo}`
        : `¡${subidos} fotos subidas!${notaDup} Ya se ven en la web; ${anfitrion} las pasará a iCloud 👍${notaFondo}`, 4600);
    procesarOriginales();
    ui.campoArchivos.value = '';
    ui.campoComentario.value = '';
    actualizarResumenArchivos();
    await cargarUploads();
    pintarTodo();
  } catch (err) {
    toast(`⚠️ ${err.message}${subidos ? ` (se subieron ${subidos})` : ''}`, 5000);
  } finally {
    ui.btnEnviarSubida.disabled = false;
    ui.progresoSubida.hidden = true;
    ui.barraSubida.value = 0;
  }
}

// -------------------------------------------------------------- modo anfitrión
async function accionAnfitrion(id, accion) {
  try {
    const res = await fetch('/api/admin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pin: pinGuardado(), id, accion }),
    });
    const datos = await res.json();
    if (!res.ok) throw new Error(datos.error || `Error ${res.status}`);
    if (accion === 'en_icloud') toast('Marcada como añadida a iCloud ✓');
    if (accion === 'borrar') toast('Subida borrada');
    await cargarUploads();
    pintarTodo();
  } catch (err) {
    toast(`⚠️ ${err.message}`, 4500);
  }
}

async function entrarModoAnfitrion(ev) {
  ev.preventDefault();
  const pin = ui.campoPin.value.trim();
  if (!pin) return;
  try {
    const res = await fetch('/api/admin', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ pin, accion: 'comprobar' }),
    });
    const datos = await res.json();
    if (!res.ok) throw new Error(datos.error || 'PIN incorrecto');
    try { sessionStorage.setItem('adminPin', pin); } catch { /* modo privado */ }
    ui.dlgAnfitrion.close();
    ui.campoPin.value = '';
    toast('Modo anfitrión activado 🔑');
    pintarTodo();
  } catch (err) {
    toast(`⚠️ ${err.message}`, 4500);
  }
}

// ------------------------------------------------------------------ eventos UI
ui.btnSubir.addEventListener('click', () => {
  if (!estado.subidasDisponibles) {
    toast(estado.avisoConfiguracion || 'Las subidas aún no están configuradas; avisa al anfitrión.', 5000);
    return;
  }
  try { ui.campoNombre.value = ui.campoNombre.value || localStorage.getItem('nombreFamiliar') || ''; } catch { /* nada */ }
  ui.dlgSubir.showModal();
});
ui.btnCancelarSubida.addEventListener('click', () => ui.dlgSubir.close());
ui.campoArchivos.addEventListener('change', actualizarResumenArchivos);
ui.formSubir.addEventListener('submit', enviarSubida);

ui.btnRefrescar.addEventListener('click', () => cargarTodo(true));

ui.btnSeleccionar.addEventListener('click', () => {
  if (estado.seleccionando) salirSeleccion();
  else entrarSeleccion();
});
ui.btnCancelarSeleccion.addEventListener('click', salirSeleccion);
ui.btnSeleccionarTodas.addEventListener('click', seleccionarTodas);
ui.btnDescargarLote.addEventListener('click', descargarLote);

ui.btnAnfitrion.addEventListener('click', () => {
  if (!estado.adminDisponible) {
    toast('El modo anfitrión no está activado en el servidor (variable ADMIN_PIN)', 4500);
    return;
  }
  ui.btnSalirAnfitrion.hidden = !esAnfitrion();
  ui.notaAnfitrion.textContent = esAnfitrion()
    ? 'Ya estás en modo anfitrión en este dispositivo.'
    : 'Con el PIN del anfitrión puedes marcar las fotos subidas como «ya en iCloud» o borrarlas.';
  ui.dlgAnfitrion.showModal();
});
ui.btnCancelarAnfitrion.addEventListener('click', () => ui.dlgAnfitrion.close());
ui.btnSalirAnfitrion.addEventListener('click', () => {
  try { sessionStorage.removeItem('adminPin'); } catch { /* nada */ }
  ui.dlgAnfitrion.close();
  toast('Has salido del modo anfitrión');
  pintarTodo();
});
ui.formAnfitrion.addEventListener('submit', entrarModoAnfitrion);

ui.btnCerrarVisor.addEventListener('click', () => ui.dlgVisor.close());
ui.btnEliminarVisor.addEventListener('click', async () => {
  const item = estado.visorLista[estado.visorIndice];
  if (!item?.id) return;
  if (!confirm(`¿Borrar la foto subida por ${item.contributor || 'alguien'}?`)) return;
  ui.dlgVisor.close();
  if (claveDe(item.id)) await borrarMiSubida(item.id);
  else await accionAnfitrion(item.id, 'borrar');
});
ui.btnAnterior.addEventListener('click', () => moverVisor(-1));
ui.btnSiguiente.addEventListener('click', () => moverVisor(1));
ui.dlgVisor.addEventListener('close', () => ui.visorContenido.replaceChildren());
ui.dlgVisor.addEventListener('click', (ev) => {
  if (ev.target === ui.dlgVisor || ev.target === ui.visorContenido) ui.dlgVisor.close();
});

document.addEventListener('keydown', (ev) => {
  if (!ui.dlgVisor.open) return;
  if (ev.key === 'ArrowLeft') moverVisor(-1);
  if (ev.key === 'ArrowRight') moverVisor(1);
});

// Deslizar con el dedo en el visor (Android / iPhone)
let toqueX = null;
ui.dlgVisor.addEventListener('touchstart', (ev) => { toqueX = ev.changedTouches[0].clientX; }, { passive: true });
ui.dlgVisor.addEventListener('touchend', (ev) => {
  if (toqueX === null) return;
  const delta = ev.changedTouches[0].clientX - toqueX;
  toqueX = null;
  if (Math.abs(delta) > 48) moverVisor(delta < 0 ? 1 : -1);
}, { passive: true });

// Refresco automático: cada 5 minutos y al volver a la pestaña
setInterval(() => cargarTodo(), 5 * 60 * 1000);
document.addEventListener('visibilitychange', () => {
  if (!document.hidden && estado.album && Date.now() - estado.album.fetchedAt > 90 * 1000) {
    cargarTodo();
  }
});

// ------------------------------------------------------------------- arranque
if ('serviceWorker' in navigator) {
  // Ruta relativa: el ámbito del SW queda en "/" o en "/album/" según el despliegue
  navigator.serviceWorker.register('./sw.js').catch(() => { /* sin PWA, la web sigue funcionando */ });
}

cargarEstado();
cargarTodo();
