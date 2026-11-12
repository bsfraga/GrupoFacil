-- GrupoFacil: Español (Latinoamérica, esMX). Solo lo que cambia respecto a Locale_es.lua.
local ADDON, NS = ...

NS.LOCALES.mx = setmetatable({
    ["Join request message, spec, send mode, window and language. Also in Options > AddOns > GrupoFacil."] = "Mensaje de solicitud, especialización, modo de envío, ventana e idioma. También en Opciones > Accesorios > GrupoFacil.",
    ["You can only invite when you are solo or the leader/assistant."] = "Solo puedes invitar si no tienes grupo o eres el líder o ayudante.",
    ["(prefill mode: opens the chat, you press Enter)"] = "(modo rellenar: abre el chat y tú presionas Enter)",
    ["The search got no answer. Try again."] = "La búsqueda no obtuvo respuesta. Intenta de nuevo.",
    ["the search failed (see /gf diag)"] = "la búsqueda falló (revisa /gf diag)",
    ["Could not read the results."] = "No se pudieron leer los resultados.",
    ["already sent recently"] = "ya se envió hace poco",
    ["the game did not confirm the request was sent. See /gf diag."] = "el juego no confirmó el envío de la solicitud. Revisa /gf diag.",
    ["Too many searches in a row; the game refused. Wait %d s."] = "Demasiadas búsquedas seguidas; el juego las rechazó. Espera %d s.",
    ["The search failed"] = "La búsqueda falló",
    ["logged an error."] = "registró un error.",
    ["Only open the chat with the text (you press Enter)"] = "Solo abrir el chat con el texto (tú presionas Enter)",
    ["could not find the options screen; use the /gf commands."] = "no se encontró la pantalla de opciones; usa los comandos /gf.",
    ["Press Ctrl+C to copy the link, then paste it in your browser."] = "Presiona Ctrl+C para copiar el enlace y pégalo en tu navegador.",
    ["/gf options - open the options (also in Options > AddOns > GrupoFacil)"] = "/gf options - abre las opciones (también en Opciones > Accesorios > GrupoFacil)",
    ["Skip tour"] = "Omitir tour",
    ["Players lists people looking for a group: use it when you lead. Groups lists groups looking for players: use it when you are solo. All shows both."] = "Jugadores muestra a quien busca grupo: úsalo si eres el líder. Grupos muestra grupos que buscan jugadores: úsalo si estás solo. Todos muestra ambos.",
    ["Type a level range or click Near me. Click the class icons to pick classes (none = all). Role filters by tank, healer or DPS; in Groups mode it becomes Needs: groups missing that role."] = "Escribe un rango de niveles o haz clic en Cerca de mí. Haz clic en los íconos de clase para elegir clases (ninguna = todas). Función filtra por tanque, sanador o DPS; en el modo Grupos pasa a ser Falta: grupos a los que les falta esa función.",
}, { __index = NS.LOCALES.es })
