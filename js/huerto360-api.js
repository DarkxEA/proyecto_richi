// Ayudantes compartidos por todas las páginas para hablar con los PHP de /api
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
    throw new Error("No se pudo conectar con el servidor.");
  }

  // Sin sesión o con un rol que no corresponde: de vuelta al inicio
  if (respuesta.status === 401 || respuesta.status === 403) {
    location.href = "index.html";
    throw new Error("Sesión no válida.");
  }

  let json = {};
  try {
    json = await respuesta.json();
  } catch {
    /* el servidor no devolvió JSON */
  }

  if (!respuesta.ok || json.error) {
    throw new Error(json.error || "Error del servidor.");
  }

  return json;
}

// Botón pequeño para cerrar sesión (las páginas no tenían uno)
function agregarBotonSalir() {
  const boton = document.createElement("button");
  boton.type = "button";
  boton.textContent = "Cerrar sesión";
  boton.style.cssText =
    "position:fixed;top:8px;right:8px;z-index:9999;padding:6px 12px;" +
    "border:1px solid #b9c5b3;border-radius:8px;background:#fff;color:#234;" +
    "font:13px system-ui,sans-serif;cursor:pointer;opacity:.9";

  boton.addEventListener("click", async () => {
    try {
      await fetch("api/logout.php", { method: "POST", credentials: "same-origin" });
    } finally {
      location.href = "index.html";
    }
  });

  document.body.appendChild(boton);
}
