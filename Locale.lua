-- GrupoFacil: idiomas. O texto em inglês é a própria chave (e o fallback).
-- O idioma escolhido fica em GrupoFacilDB.language; sem escolha, segue o idioma do cliente (enUS = inglês).
-- As outras línguas ficam em Locale_<código>.lua e se registram em NS.LOCALES. Trocar recarrega a interface.

local ADDON, NS = ...

local PT = {
    ["Hidden (%d)"] = "Escondidos (%d)",
    ["Hidden players"] = "Jogadores escondidos",
    ["Players and groups you hid or blocked. Click to show them again. Players on your game ignore list stay hidden; change that in the game's ignore list."] = "Jogadores e grupos que você escondeu ou bloqueou. Clique para mostrá-los de novo. Quem está na sua lista de ignorados do jogo continua escondido; isso se muda na lista de ignorados do jogo.",
    ["Show"] = "Mostrar",
    ["Unblock"] = "Desbloquear",
    ["blocked"] = "bloqueado",
    ["this session"] = "nesta sessão",
    ["Show all"] = "Mostrar todos",
    ["Shows everyone you hid this session and unblocks everyone you blocked."] = "Mostra todos que você escondeu nesta sessão e desbloqueia todos que você bloqueou.",
    ["+%d more: use /gf blocked and /gf unblock."] = "+%d outros: use /gf blocked e /gf unblock.",
    ["more than one blocked player matches; type the full name: %s"] = "mais de um jogador bloqueado começa assim; digite o nome completo: %s",
    -- v0.11: amigos/guilda, esconder e bloquear
    ["Friend"] = "Amigo",
    ["Guild member"] = "Membro da guilda",
    ["Right-click: hide or block"] = "Clique direito: esconder ou bloquear",
    ["Hide for this session"] = "Esconder nesta sessão",
    ["Hidden until you reload the interface."] = "Fica escondido até você recarregar a interface.",
    ["Block this player"] = "Bloquear este jogador",
    ["Their listings stay hidden, even after a reload. Undo it in the options or with /gf unblock."] = "As listagens dele continuam escondidas, mesmo depois de recarregar. Desfaça nas opções ou com /gf unblock.",
    ["Cancel"] = "Cancelar",
    ["%s blocked. Undo it in the options or with /gf unblock."] = "%s bloqueado. Desfaça nas opções ou com /gf unblock.",
    ["no blocked players."] = "nenhum jogador bloqueado.",
    ["blocked players: %s"] = "jogadores bloqueados: %s",
    ["blocked list cleared."] = "lista de bloqueados limpa.",
    ["%s unblocked."] = "%s desbloqueado.",
    ["not in the blocked list: %s"] = "não está na lista de bloqueados: %s",
    ["/gf blocked - list blocked players; /gf unblock <name> | all - unblock"] = "/gf blocked - lista os jogadores bloqueados; /gf unblock <nome> | all - desbloqueia",
    ["Unblock all"] = "Desbloquear todos",
    ["Blocked players: %d"] = "Jogadores bloqueados: %d",
    ["Right-click a row in the list to block a player. /gf blocked lists them; /gf unblock <name> unblocks one."] = "Clique com o botão direito numa linha da lista para bloquear um jogador. /gf blocked mostra a lista; /gf unblock <nome> desbloqueia um.",
    ["+%d more: pick a level range to narrow the list."] = "+%d outras: use uma faixa de level para reduzir a lista.",
    -- v0.10: dungeon, modo compacto, vagas, zona, composição, {role}/{activity}
    ["dungeon"] = "masmorra",
    ["Dungeon"] = "Masmorra",
    ["All dungeons"] = "Todas as masmorras",
    ["%d dungeons"] = "%d masmorras",
    ["Show only these dungeons. The list has the dungeons in the current results, with their suggested level."] = "Mostra só estas masmorras. A lista traz as masmorras dos resultados atuais, com o level sugerido.",
    ["No dungeons in the results yet. Search first."] = "Ainda não há masmorras nos resultados. Faça uma busca primeiro.",
    ["Hide filters"] = "Esconder filtros",
    ["Show filters"] = "Mostrar filtros",
    ["Compact mode: hides the filter rows so more of the list fits. The filters keep working."] = "Modo compacto: esconde as linhas de filtro para caber mais da lista. Os filtros continuam valendo.",
    ["(filters on)"] = "(filtros ativos)",
    ["needs you"] = "precisa de você",
    ["Needs your role: %s"] = "Tem vaga para você: %s",
    ["Zone: %s"] = "Zona: %s",
    ["Leader's zone: %s"] = "Zona do líder: %s",
    ["Open spots: "] = "Vagas: ",
    ["none"] = "nenhuma",
    ["leader"] = "líder",
    ["Dungeon picks which dungeons to show, and Hide filters gives the list more room."] = "Masmorra escolhe quais masmorras mostrar, e Esconder filtros dá mais espaço à lista.",
    ["Use {class}, {spec}, {level}, {name}, {role} (your Looking For Group roles) and {activity} (the group's dungeon). Empty = English default: "] = "Use {class}, {spec}, {level}, {name}, {role} (suas roles no Looking For Group) e {activity} (a masmorra do grupo). Vazio = padrão em inglês: ",
    ["/gf msg <text> - change the text; use {class} {spec} {level} {name} {role} {activity}"] = "/gf msg <texto> - troca o texto; use {class} {spec} {level} {name} {role} {activity}",
    -- troca de idioma (botão seguro de /reload)
    ["Language changed. Reload the interface to apply it."] = "Idioma alterado. Recarregue a interface para aplicar.",
    ["Reload now"] = "Recarregar agora",
    ["Later"] = "Depois",
    -- janela
    ["Players"] = "Jogadores",
    ["Groups"] = "Grupos",
    ["All"] = "Todos",
    ["Level"] = "Level",
    ["Level %s %s %s"] = "Level %s %s %s",
    ["Lvl %d"] = "Lvl %d",
    ["Spec"] = "Spec",
    ["Tank"] = "Tank",
    ["Healer"] = "Healer",
    ["DPS"] = "DPS",
    ["Drag to resize the window."] = "Arraste para mudar o tamanho da janela.",
    ["Name"] = "Nome",
    ["Newest"] = "Mais novos",
    ["Sort: "] = "Ordem: ",
    ["to"] = "a",
    ["Near me"] = "Perto de mim",
    ["Your level, 3 below to 3 above."] = "Seu level 3 para baixo e 3 para cima.",
    ["Hide delisted"] = "Esconder quem saiu",
    ["Class"] = "Classe",
    ["Click to toggle. None selected = all."] = "Clique para ligar ou desligar. Nenhuma marcada = todas.",
    ["Role"] = "Role",
    ["Needs"] = "Vaga de",
    ["Clear filters"] = "Limpar filtros",
    ["Search again"] = "Buscar de novo",
    ["Repeats the last Looking For Group search (same category and activities)."] =
        "Repete a última busca feita no Looking For Group (mesma categoria e atividades).",
    ["Options"] = "Opções",
    ["Join request message, spec, send mode, window and language. Also in Options > AddOns > GrupoFacil."] =
        "Mensagem do pedido de vaga, spec, modo de envio, janela e idioma. Também em Options > AddOns > GrupoFacil.",
    ["now"] = "agora",
    ["%d members"] = "%d membros",
    ["Whisper"] = "Sussurrar",
    ["Invite"] = "Convidar",
    ["Invite to group"] = "Convidar para o grupo",
    ["Ask the leader to join"] = "Pedir vaga ao líder",
    ["Ask to join"] = "Pedir vaga",
    ["Sent"] = "Enviado",
    ["You can only invite when you are solo or the leader/assistant."] =
        "Só dá para convidar se você estiver sozinho ou for líder/assistente.",
    ["(prefill mode: opens the chat, you press Enter)"] = "(modo preencher: abre o chat, você aperta Enter)",
    ["Sends: "] = "Envia: ",
    ["Unavailable: "] = "Indisponível: ",
    ["Opens the chat so you can write to the player."] = "Abre o chat para você escrever ao jogador.",
    ["Members: "] = "Membros: ",
    ["Left the list"] = "Saiu da lista",
    ["Search in the Looking For Group window."] = "Faça uma busca na janela do Looking For Group.",
    ["Searching..."] = "Buscando...",
    ["Showing %d."] = "Mostrando %d.",
    ["No results. Search in Looking For Group."] = "Sem resultados. Faça uma busca no Looking For Group.",
    ["No result passes the filters."] = "Nenhum resultado passa nos filtros.",
    ["%d-%d of %d"] = "%d-%d de %d",
    ["Join request: "] = "Pedido de vaga: ",

    -- busca, leitura e ações
    ["The search got no answer. Try again."] = "A busca não respondeu. Tente de novo.",
    ["wait %d s (the game limits back-to-back searches)"] = "aguarde %d s (o jogo limita buscas seguidas)",
    ["the game's chat restriction is active"] = "restrição de chat do jogo ativa",
    ["search in the Looking For Group window first"] = "faça uma busca na janela do Looking For Group primeiro",
    ["the search failed (see /gf diag)"] = "a busca falhou (veja /gf diag)",
    ["Game chat restriction active: list frozen."] = "Restrição de chat do jogo ativa: lista congelada.",
    ["Could not read the results."] = "Não foi possível ler os resultados.",
    ["%d results in total."] = "%d resultados no total.",
    ["game chat restriction active; invite blocked."] = "restrição de chat do jogo ativa; convite bloqueado.",
    ["no leader data yet"] = "sem dados do líder",
    ["you are already in a group"] = "você já está em grupo",
    ["already sent recently"] = "já enviado há pouco",
    ["not sent: %s."] = "não enviado: %s.",
    ["wait a few seconds between requests."] = "aguarde alguns segundos entre um pedido e outro.",
    ["the game did not confirm the request was sent. See /gf diag."] = "o jogo não confirmou o envio do pedido. Veja /gf diag.",
    ["request sent to %s."] = "pedido enviado a %s.",
    ["Too many searches in a row; the game refused. Wait %d s."] = "Buscas demais seguidas; o jogo recusou. Espere %d s.",
    ["The search failed"] = "A busca falhou",

    -- diagnóstico
    ["logged an error."] = "registrou um erro.",
    ["Use /gf diag to see it; then /reload to save the report."] = "Use /gf diag para ver; depois /reload para gravar o relatório.",
    ["session %d, %d distinct errors, %d trace lines."] = "sessão %d, %d erros distintos, %d linhas de rastro.",
    ["latest events:"] = "últimos eventos:",
    ["To have it analyzed: /reload (writes the file)."] = "Para analisar: /reload (grava o arquivo).",

    -- opções
    ["version %s  ·  /gf opens the window"] = "versão %s  ·  /gf abre a janela",
    ["Language"] = "Idioma",
    ["Changing the language reloads the interface."] = "Trocar o idioma recarrega a interface.",
    ["Join request message"] = "Mensagem do pedido de vaga",
    ["Default"] = "Padrão",
    ["Goes out as: "] = "Sai assim: ",
    ["How you introduce yourself (this character only)"] = "Como você se apresenta (só este personagem)",
    ["Class name"] = "Nome da classe",
    ["Empty = detect from talents (now: %s)"] = "Vazio = detectar pelos talentos (agora: %s)",
    ["no points"] = "sem pontos",
    ["Empty = game name (%s)"] = "Vazio = nome do jogo (%s)",
    ["Ask to join button"] = "Botão Pedir vaga",
    ["Send the whisper straight to the leader"] = "Enviar o sussurro direto ao líder",
    ["Only open the chat with the text (you press Enter)"] = "Só abrir o chat com o texto (você aperta Enter)",
    ["Window"] = "Janela",
    ["Open together with Looking For Group"] = "Abrir junto com o Looking For Group",
    ["Dock next to Looking For Group"] = "Encaixar ao lado do Looking For Group",
    ["Unchecked, the window stays where you drag it."] = "Desmarcado, a janela fica onde você arrastar.",
    ["Advanced"] = "Avançado",
    ["Capture the native search (applies after /reload)"] = "Capturar a busca nativa (vale depois de /reload)",
    ["Keeps the category and activities of the last search for the Search again button. Turn off if the native search gets stuck on Searching... with the addon on."] =
        "Guarda a categoria e as atividades da última busca para o botão Buscar de novo. Desligue se a busca nativa travar em Searching... com o addon ativo.",
    ["Show the diagnostic trace in chat"] = "Mostrar o rastro de diagnóstico no chat",
    ["Open GrupoFacil"] = "Abrir o GrupoFacil",
    ["Diagnostics in chat"] = "Diagnóstico no chat",
    ["Clear diagnostics"] = "Limpar diagnóstico",
    ["diagnostics cleared."] = "diagnóstico limpo.",
    ["open the options after combat."] = "abra as opções depois do combate.",
    ["could not find the options screen; use the /gf commands."] = "não achei a tela de opções; use os comandos /gf.",
    ["Click: open or close the window"] = "Clique: abre ou fecha a janela",
    ["Right-click: options"] = "Clique direito: opções",
    ["Donate"] = "Doar",
    ["Support the addon"] = "Apoie o addon",
    ["Press Ctrl+C to copy the link, then paste it in your browser."] = "Aperte Ctrl+C para copiar o link e cole no navegador.",
    ["Drag: move the button"] = "Arrastar: move o botão",
    ["Show minimap button"] = "Mostrar botão no minimapa",
    ["Left-click opens the window, right-click opens these options. Drag it around the minimap."] =
        "Clique esquerdo abre a janela, direito abre estas opções. Arraste pela borda do minimapa.",
    ["minimap button: %s"] = "botão no minimapa: %s",
    ["/gf minimap on | off - show or hide the minimap button"] = "/gf minimap on | off - mostra ou esconde o botão no minimapa",

    -- comandos
    ["/gf - open or close the window"] = "/gf - abre ou fecha a janela",
    ["/gf options - open the options (also in Options > AddOns > GrupoFacil)"] =
        "/gf options - abre as opções (também em Options > AddOns > GrupoFacil)",
    ["/gf lang en | pt | es | mx | de | fr - addon language (reloads the UI)"] = "/gf lang en | pt | es | mx | de | fr - idioma do addon (recarrega a interface)",
    ["/gf msg - show the join request text and how it goes out now"] = "/gf msg - mostra o texto do pedido de vaga e como ele sai agora",
    ["/gf msg default - back to the default text (English)"] = "/gf msg default - volta ao texto padrão (inglês)",
    ["/gf spec <name> | /gf spec auto - set or detect this character's spec"] = "/gf spec <nome> | /gf spec auto - fixa ou detecta a spec deste personagem",
    ["/gf class <name> | /gf class auto - set or detect the class name"] = "/gf class <nome> | /gf class auto - fixa ou detecta o nome da classe",
    ["/gf mode direct | prefill - send the whisper or only open the chat with the text"] =
        "/gf mode direct | prefill - envia o sussurro ou só abre o chat com o texto",
    ["/gf auto on | off - open together with Looking For Group"] = "/gf auto on | off - abrir junto com o Looking For Group",
    ["/gf dock - attach the window next to Looking For Group again"] = "/gf dock - prende a janela de novo ao lado do Looking For Group",
    ["/gf hook on | off - capture the native search (turn off if the native search gets stuck; applies after /reload)"] =
        "/gf hook on | off - captura da busca nativa (desligue se a busca nativa travar; vale após /reload)",
    ["/gf diag - error and trace summary; /gf diag snap - save a snapshot now; /gf diag clear"] =
        "/gf diag - resumo dos erros e do rastro; /gf diag snap - grava um retrato agora; /gf diag clear - limpa",
    ["/gf debug on | off - show the trace in chat as it happens"] = "/gf debug on | off - mostra o rastro no chat enquanto acontece",
    ["language: %s (use /gf lang followed by en, pt, es, mx, de or fr)"] = "idioma: %s (use /gf lang seguido de en, pt, es, mx, de ou fr)",
    ["text (custom): %s"] = "texto (personalizado): %s",
    ["text (English default): %s"] = "texto (padrão em inglês): %s",
    ["goes out as: %s"] = "sai assim: %s",
    ["default text (English): %s"] = "texto padrão (inglês): %s",
    ["new text: %s"] = "novo texto: %s",
    ["(no talent points)"] = "(sem pontos de talento)",
    -- primeiro uso (Onboarding.lua)
    ["/gf tour - show the quick tour of the window"] = "/gf tour - mostra o tour rápido da janela",
    ["Show the tour"] = "Mostrar o tour",
    ["Close the game options to see the tour."] = "Feche as opções do jogo para ver o tour.",
    ["New to GrupoFacil? Take a 30-second tour."] = "Primeira vez no GrupoFacil? Faça o tour de 30 segundos.",
    ["Start tour"] = "Começar",
    ["No thanks"] = "Agora não",
    ["You can see the tour any time with /gf tour."] = "Você pode ver o tour quando quiser com /gf tour.",
    ["Tour finished. /gf tour shows it again."] = "Tour concluído. /gf tour mostra de novo.",
    ["The tour is not available in combat."] = "O tour não fica disponível em combate.",
    ["ready. Open Looking For Group or type /gf. New here? /gf tour shows a quick tour."] =
        "pronto. Abra o Looking For Group ou digite /gf. Primeira vez? /gf tour mostra um tour rápido.",
    ["Next"] = "Próximo",
    ["Back"] = "Voltar",
    ["Finish"] = "Concluir",
    ["Skip tour"] = "Pular tour",
    ["Example group"] = "Grupo de exemplo",
    ["Pick what to list"] = "Escolha o que listar",
    ["Filter the list"] = "Filtre a lista",
    ["Act on a row"] = "Use os botões da linha",
    ["Refresh the list"] = "Atualize a lista",
    ["Your message and settings"] = "Sua mensagem e as opções",
    ["Players lists people looking for a group: use it when you lead. Groups lists groups looking for players: use it when you are solo. All shows both."] =
        "Jogadores lista quem procura grupo: use quando você é o líder. Grupos lista grupos procurando gente: use quando você está solo. Todos mostra os dois.",
    ["Type a level range or click Near me. Click the class icons to pick classes (none = all). Role filters by tank, healer or DPS; in Groups mode it becomes Needs: groups missing that role."] =
        "Digite uma faixa de level ou clique em Perto de mim. Clique nos ícones para escolher classes (nenhum = todas). Role filtra por tank, healer ou DPS; no modo Grupos vira Vaga de: grupos que precisam dessa role.",
    ["Invite asks a solo player into your group. Ask to join whispers the group leader your message:\n|cffffffff%s|r\nWhisper opens the chat to write your own."] =
        "Convidar chama um jogador solo para o seu grupo. Pedir vaga manda ao líder do grupo a sua mensagem:\n|cffffffff%s|r\nSussurrar abre o chat para você escrever a sua.",
    ["GrupoFacil reads your Looking For Group search. Search again repeats the last one. The game only allows it from your click and refuses searches that come too fast."] =
        "O GrupoFacil lê a sua busca do Looking For Group. Buscar de novo repete a última. O jogo só permite a busca pelo seu clique e recusa buscas seguidas demais.",
    ["The bottom line shows the message leaders receive. Options changes it ({level}, {spec}, {class}, {name}), the send mode, the language and the minimap button. /gf tour shows this tour again."] =
        "A linha de baixo mostra a mensagem que o líder recebe. Opções muda a mensagem ({level}, {spec}, {class}, {name}), o modo de envio, o idioma e o botão do minimapa. /gf tour mostra este tour de novo.",
    ["send mode: %s"] = "modo de envio: %s",
    ["direct"] = "direto",
    ["prefill"] = "preencher",
    ["open together with Looking For Group: %s"] = "abrir junto com o Looking For Group: %s",
    ["search hook %s; applies after /reload."] = "hook da busca %s; vale depois de /reload.",
    ["search hook: %s"] = "hook da busca: %s",
    ["snapshot saved. /reload to write it to disk."] = "retrato gravado. Faça /reload para gravar no disco.",
    ["debug: %s"] = "debug: %s",
    ["on"] = "ligado",
    ["off"] = "desligado",
    ["on (trace in chat)"] = "ligado (rastro no chat)",
}
NS.PT_STRINGS = PT

-- Outras línguas: Locale_es.lua, Locale_mx.lua, Locale_de.lua, Locale_fr.lua preenchem esta tabela.
NS.LOCALES = { pt = PT }
-- Ordem do seletor; o nome fica na própria língua.
NS.LANGUAGES = {
    { code = "en", name = "English" },
    { code = "pt", name = "Português (Brasil)" },
    { code = "es", name = "Español (España)" },
    { code = "mx", name = "Español (Latinoamérica)" },
    { code = "de", name = "Deutsch" },
    { code = "fr", name = "Français" },
}
-- Idioma do cliente -> idioma do addon, quando o jogador nunca escolheu.
local CLIENT = { ptBR = "pt", ptPT = "pt", esES = "es", esMX = "mx", deDE = "de", frFR = "fr" }
-- Apelidos aceitos em /gf lang.
NS.LANGUAGE_ALIAS = { enus = "en", engb = "en", ptbr = "pt", eses = "es", esmx = "mx", dede = "de", frfr = "fr",
    english = "en", portugues = "pt", ["português"] = "pt", espanol = "es", ["español"] = "es", latam = "mx",
    deutsch = "de", francais = "fr", ["français"] = "fr" }

local function known(code) return code == "en" or NS.LOCALES[code] ~= nil end

function NS.Language()
    local lang = GrupoFacilDB and GrupoFacilDB.language
    if lang and known(lang) then return lang end
    local c = CLIENT[GetLocale and GetLocale() or ""]
    if c and known(c) then return c end
    return "en"
end

function NS.LanguageName(code)
    for _, l in ipairs(NS.LANGUAGES) do if l.code == code then return l.name end end
    return code
end

-- Busca na hora: o idioma só é conhecido depois que o SavedVariables carrega.
NS.L = setmetatable({}, {
    __index = function(_, key)
        local t = NS.LOCALES[NS.Language()]
        return t and t[key] or key
    end,
})

-- Troca o idioma e pede o /reload. ReloadUI() chamado pelo addon pode ser bloqueado pelo jogo
-- (ADDON_ACTION_BLOCKED visto em 12/11/2026), então o recarregamento sai de um botão seguro
-- com a macro /reload (NS.ShowReloadPrompt, em Options.lua).
function NS.SetLanguage(lang)
    lang = NS.LANGUAGE_ALIAS[lang] or lang
    if not known(lang) then return false end
    if not GrupoFacilDB then return false end
    if NS.Language() == lang and GrupoFacilDB.language == lang then return true end
    GrupoFacilDB.language = lang
    if NS.D then NS.D.Trace("CONFIG", "idioma trocado para %s; pedindo /reload", lang) end
    if NS.ShowReloadPrompt then NS.ShowReloadPrompt() end
    return true
end
