// =====================================================================
// Huerto360 v0.0.3 · Cliente API Centralizado, Sesión y Sincronización
// =====================================================================

/** Realiza llamadas JSON a los controladores en /api */
async function apiLlamar(url, accion, datos = {}) {
  let respuesta;
  try {
    respuesta = await fetch(url, {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ ...datos, accion })
    });
  } catch {
    throw new Error("No se pudo conectar con el servidor. Revisa que XAMPP esté encendido.");
  }

  // Sin sesión o sin permisos: redirigir a index.html
  if (respuesta.status === 401 || respuesta.status === 403) {
    location.href = "index.html";
    throw new Error("Sesión no válida o expirada.");
  }

  let json = {};
  try {
    json = await respuesta.json();
  } catch {
    /* Respuesta vacía o no JSON */
  }

  if (!respuesta.ok || json.error) {
    throw new Error(json.error || "Ocurrió un error en el servidor.");
  }

  return json;
}

/**
 * Sondeo inteligente en segundo plano:
 * Refresca la información automáticamente cada X segundos
 * y de forma reactiva al regresar a la pestaña del navegador.
 */
function iniciarSincronizacion(callbackActualizar, intervaloMs = 25000) {
  if (typeof callbackActualizar !== "function") return;

  let temporizador = setInterval(() => {
    if (document.visibilityState === "visible") {
      callbackActualizar();
    }
  }, intervaloMs);

  // Al volver a la pestaña, actualizar inmediatamente
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") {
      callbackActualizar();
    }
  });

  return temporizador;
}

/** Botón accesible y ergonómico para cerrar sesión (ideal para adultos mayores) */
function agregarBotonSalir() {
  if (document.getElementById("btnCerrarSesionGlobal")) return;

  const boton = document.createElement("button");
  boton.id = "btnCerrarSesionGlobal";
  boton.type = "button";
  boton.innerHTML = "<span>🚪</span> <span>Salir</span>";
  boton.title = "Cerrar sesión de Huerto360";
  boton.setAttribute("aria-label", "Cerrar sesión de tu cuenta");

  boton.style.cssText =
    "position:fixed;bottom:18px;right:18px;z-index:9999;padding:10px 18px;" +
    "border:2px solid #b33930;border-radius:12px;background:#ffffff;color:#b33930;" +
    "font:bold 15px system-ui,-apple-system,sans-serif;cursor:pointer;" +
    "display:inline-flex;align-items:center;gap:8px;" +
    "box-shadow:0 6px 18px rgba(179,57,48,0.25);transition:all .2s ease;" +
    "min-height:44px;min-width:44px;";

  boton.addEventListener("mouseenter", () => {
    boton.style.background = "#b33930";
    boton.style.color = "#ffffff";
    boton.style.transform = "translateY(-2px)";
  });

  boton.addEventListener("mouseleave", () => {
    boton.style.background = "#ffffff";
    boton.style.color = "#b33930";
    boton.style.transform = "translateY(0)";
  });

  boton.addEventListener("click", async () => {
    if (confirm("¿Estás seguro de que deseas salir de tu sesión?")) {
      try {
        await fetch("api/logout.php", { method: "POST", credentials: "same-origin" });
      } finally {
        location.href = "index.html";
      }
    }
  });

  document.body.appendChild(boton);
}
