-- GrupoFacil: idiomas. O texto em inglês é a própria chave (e o fallback).
-- O idioma escolhido fica em GrupoFacilDB.language ("en" padrão, "pt"); trocar recarrega a interface.

local ADDON, NS = ...

local PT = {
    -- janela
    ["Players"] = "Jogadores",
    ["Groups"] = "Grupos",
    ["All"] = "Todos",
    ["Level"] = "Level",
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
    ["Use {class}, {spec}, {level} and {name}. Empty = English default: "] =
        "Use {class}, {spec}, {level} e {name}. Vazio = padrão em inglês: ",
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
    ["/gf lang en | pt - addon language (reloads the UI)"] = "/gf lang en | pt - idioma do addon (recarrega a interface)",
    ["/gf msg - show the join request text and how it goes out now"] = "/gf msg - mostra o texto do pedido de vaga e como ele sai agora",
    ["/gf msg <text> - change the text; use {class} {spec} {level} {name}"] = "/gf msg <texto> - troca o texto; use {class} {spec} {level} {name}",
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
    ["language: %s (use /gf lang en or /gf lang pt)"] = "idioma: %s (use /gf lang en ou /gf lang pt)",
    ["text (custom): %s"] = "texto (personalizado): %s",
    ["text (English default): %s"] = "texto (padrão em inglês): %s",
    ["goes out as: %s"] = "sai assim: %s",
    ["default text (English): %s"] = "texto padrão (inglês): %s",
    ["new text: %s"] = "novo texto: %s",
    ["(no talent points)"] = "(sem pontos de talento)",
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

function NS.Language()
    local lang = GrupoFacilDB and GrupoFacilDB.language
    if lang == "pt" then return "pt" end
    return "en"
end

-- Busca na hora: o idioma só é conhecido depois que o SavedVariables carrega.
NS.L = setmetatable({}, {
    __index = function(_, key)
        if NS.Language() == "pt" then return PT[key] or key end
        return key
    end,
})

-- Troca o idioma e recarrega a interface (chamada a partir de um clique ou comando).
function NS.SetLanguage(lang)
    if lang ~= "en" and lang ~= "pt" then return end
    if not GrupoFacilDB or NS.Language() == lang then return end
    GrupoFacilDB.language = lang
    if NS.D then NS.D.Trace("CONFIG", "idioma trocado para %s; recarregando", lang) end
    ReloadUI()
end
