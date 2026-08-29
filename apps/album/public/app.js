// Álbum familiar — lógica de la web (sin dependencias)

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
};

const estado = {
  album: null,        // respuesta de /api/album
  uploads: [],        // respuesta de /api/uploads
  adminDisponible: false,
  visorLista: [],
  visorIndice: 0,
  cargando: false,
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
function celdaMiniatura(item, onAbrir) {
  const celda = document.createElement('button');
  celda.type = 'button';
  celda.className = 'celda';
  celda.addEventListener('click', onAbrir);

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
  return celda;
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
    ui.gridAlbum.appendChild(celdaMiniatura(foto, () => abrirVisor(listaVisorAlbum(), i)));
  });
}

function celdaPendiente(upload) {
  const item = uploadComoVisor(upload);
  const celda = celdaMiniatura(item, () => {
    const lista = estado.uploads.filter((u) => u.estado === upload.estado).map(uploadComoVisor);
    const indice = lista.findIndex((v) => v.id === upload.id);
    abrirVisor(lista, Math.max(0, indice));
  });
  celda.classList.add('celda-pendiente');

  if (esAnfitrion()) {
    const acciones = document.createElement('span');
    acciones.className = 'acciones-anfitrion';
    if (upload.estado === 'pendiente') {
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
        accionAnfitrion(upload.id, 'borrar');
      }
    });
    acciones.appendChild(borrar);
    celda.appendChild(acciones);
  }
  return celda;
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
    descargarHref: f.downloadChecksum ? `/api/descargar?checksum=${encodeURIComponent(f.downloadChecksum)}` : null,
  }));
}

function uploadComoVisor(u) {
  return {
    id: u.id,
    thumbUrl: u.isVideo ? null : u.url,
    fullUrl: u.url,
    videoUrl: u.isVideo ? u.url : null,
    isVideo: u.isVideo,
    caption: u.caption,
    contributor: u.uploader,
    dateCreated: u.uploadedAt,
    descargarHref: `${u.url}?descargar`,
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
    ui.btnDescargar.hidden = false;
  } else {
    ui.btnDescargar.hidden = true;
  }

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
  try {
    for (const [i, archivo] of archivos.entries()) {
      ui.textoProgreso.textContent = `${i + 1} de ${archivos.length}`;
      await subirArchivo(archivo, nombre, comentario, (fraccion) => {
        ui.barraSubida.value = Math.round(((i + fraccion) / archivos.length) * 100);
      });
      subidos += 1;
    }
    ui.dlgSubir.close();
    const anfitrion = estado.album?.owner ? nombrePropio(estado.album.owner) : 'el anfitrión';
    toast(subidos === 1
      ? `¡Foto subida! Ya se ve en la web; ${anfitrion} la pasará a iCloud 👍`
      : `¡${subidos} fotos subidas! Ya se ven en la web; ${anfitrion} las pasará a iCloud 👍`, 4200);
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
  try { ui.campoNombre.value = ui.campoNombre.value || localStorage.getItem('nombreFamiliar') || ''; } catch { /* nada */ }
  ui.dlgSubir.showModal();
});
ui.btnCancelarSubida.addEventListener('click', () => ui.dlgSubir.close());
ui.campoArchivos.addEventListener('change', actualizarResumenArchivos);
ui.formSubir.addEventListener('submit', enviarSubida);

ui.btnRefrescar.addEventListener('click', () => cargarTodo(true));

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
  navigator.serviceWorker.register('/sw.js').catch(() => { /* sin PWA, la web sigue funcionando */ });
}

cargarEstado();
cargarTodo();
