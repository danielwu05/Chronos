# Design Spec: Lutris (Web + Desktop), Heroic Flatpak, External Epic/GOG, Itch.io Full Catalog & External Game Metadata Fallback

**Data:** 2026-11-15 (Atualizada com Ressalvas 1 e 2)
**Escopo:** Correção da filtragem das lojas Epic/GOG tanto no Heroic (Flatpak) quanto nas lojas externas (Chrome/Firefox/Proxy), suporte completo ao `lutris.net` e ao launcher desktop do Lutris, cobertura sob demanda do catálogo do `itch.io` e cascata zero-key de metadados/autocomplete fora da Steam.

---

## 1. Intenção e Porquê

Hoje o filtro de jogos/launchers do Chronos falha em cinco frentes interligadas:
1. **Heroic Launcher (Flatpak `com.heroicgameslauncher.hgl`)**: as lojas internas Epic (`store.epicgames.com`) e GOG (`gog.com`) deixam de filtrar dentro do Heroic porque o Flatpak foi aberto sem override `.desktop` ativo (`sync_launcher_proxy_if_configured` só rodava no boot), com o caminho errado de NSS DB (`~/.var/app/.../.pki/nssdb` em vez de `data/pki/nssdb`), sem acesso do sandbox `bwrap` aos certificados em `~/.local/share/chronos/ca/`, e sem `--proxy-server` repassado ao Electron.
2. **Lojas Externas (`store.epicgames.com` e `www.gog.com` no Chrome/Firefox/Proxy)**:
   - Em `www.gog.com`, páginas de jogo expõem gêneros via `<li class="genres__item">` e `<a href="/games?genres=rougelike">` (incluindo o slug com typo `rougelike` da própria GOG), títulos com `®`/`™` (`Heroes of Might and Magic® 3: Complete`) e `<product-tile>` envolvendo `<a class="product-tile">`, causando tags vazias, duplicação de cards e falhas de busca na Steam;
   - Em `store.epicgames.com`, cards usam containers/títulos React/EDS sem `.title`/`h2`/`h3`, `resolveCardContainer` só rodava para Steam (`/app/`), `extractPageGameInfo` não limpava sufixos longos de `<title>` nem extraía `/p/<slug>` antes da hidratação, `background.js` pulava navegação single-game sem `appId`, falhas temporárias no batch envenenavam `resolvedCache`, e o Chrome local ainda pode rodar versão em cache (`1.1.36_0`) até o `.crx`/`.xpi` ser republicado/recarregado;
   - Adicionalmente, atrás do `chronos_proxy` (`rustls` + HTTP/1.1), rotas de busca/home da `store.epicgames.com` recebem `403 Forbidden (Cf-Mitigated: challenge)` do Cloudflare (enquanto rotas diretas `/p/<slug>` ainda são bloqueadas antes do upstream e o Chrome direto funciona via extensão).
3. **`lutris.net` (navegador + proxy)**: `lutris.net` está fora de `LAUNCHER_STORE_HOSTS`, `LAUNCHER_STORE_DOMAINS` e `extract_launcher_url_hint`, além de usar layout HTML próprio (`.game-preview`, `.game-name`, `.game-details a[href*="/games/genre/"]`, `.game-info li`).
4. **Launcher Desktop do Lutris (`lutris` / `net.lutris.Lutris`)**: `scan_lutris_and_bottles` ignora o `pga.db` do Flatpak e arquivos `.yml` sem `name:` na raiz (onde `game.exe`/`game.prefix` estão indentados); não identifica processos Wine/Proton/`umu-run` por `WINEPREFIX`, `LUTRIS_GAME_UUID` ou `.exe` com `\`/truncamento de 15 chars em `/proc/<pid>/comm`; `engine.rs` não reconhece `lutris:rungameid/`; e jogos não-Steam descobertos nunca preenchiam tags em `game_metadata_cache`.
5. **Jogos fora da Steam & catálogo completo do `itch.io`**: a resolução de metadados (`resolve_game_metadata_async`) e o autocomplete (`search_game_suggestions_async`) consultam apenas a Steam API. Jogos exclusivos da GOG, consoles/emuladores/multiplataforma (*Minecraft*, *Heroes of Might and Magic® 3: Complete*, etc.) e indies do `itch.io` ficam sem tags ou ausentes na busca.

---

## 2. Objetivos, Não-Objetivos e Anti-Objetivos

### Objetivos
- Fazer as lojas **Epic Games** e **GOG** funcionarem de forma confiável tanto nas lojas **externas** (Chrome/Firefox) quanto dentro do **Heroic Flatpak** (proxy fail-open + confiança TLS no sandbox), empacotando/atualizando `.crx`/`.xpi` com bump de versão.
- Garantir que o **launcher desktop do Lutris** (nativo e Flatpak `net.lutris.Lutris`) tenha descoberta real, configuração opcional de proxy/CA, detecção de processos nativos/Wine/Proton/`umu-run` por prefixo/executável/janela e bloqueio por nome ou tag (com preenchimento via cascata externa).
- Suportar **`lutris.net`** de ponta a ponta no navegador (Chrome/Firefox + `background.js`), no proxy (`chronos_proxy`) e na extração de dicas de URL.
- Expandir a cobertura do **`itch.io`** para o catálogo inteiro usando a **Estratégia A (Sob Demanda + Memória Local)**:
  - Extração completa de tags/gêneros do DOM/HTML nas páginas e cards do `itch.io` + aprendizado automático (`dom_learned` com `keepalive`, inclusive em `localHit`).
  - Busca pública sob demanda em `https://itch.io/search?q=...` + página do jogo como último nível da cascata externa.
- Implementar cascata zero-key em `steam_api.rs` para resolução de tags e autocomplete:
  `Cache SQLite -> Steam API -> GOG Catalog API -> LizardByte GameDB (IGDB mirror) -> Itch.io Web On-Demand`.

### Não-Objetivos
- Crawler/robô em background paginando feeds `.xml` da `itch.io` (Abordagem B descartada).
- Evasão ou bypass de desafios anti-bot/Cloudflare (`Cf-Mitigated: challenge`): nunca burlar desafios Cloudflare via spoofing TLS/CAPTCHA; onde o desafio ocorrer atrás do proxy MITM (ex.: `store.epicgames.com` `/browse` via proxy), documentar a limitação e priorizar acesso direto protegido pela extensão quando aplicável.
- Integração com APIs que exijam API key/OAuth do usuário (`RAWG`, `IGDB` direto via Twitch).
- Alteração de assinatura FRB/Dart para `SteamGameSuggestionDto` (`app_id: i64` continua `0` para fontes sem Steam AppID, aproveitando o suporte já existente em `general_settings_view.dart`) ou replicação completa do parser de URLs em `lib/services/web_block_server.dart`.

### Anti-Objetivos
- **Nunca quebrar fail-open no Heroic**: não aplicar `flatpak override --user --env=http_proxy=...` persistente, pois impediria o Heroic de navegar caso o `chronos_proxy` esteja desligado.
- **Nunca envenenar o `game_metadata_cache` com resultados de busca/home**: tags extraídas de páginas de busca (`/search`, `/games?q=`) ou hubs genéricos nunca devem ser gravadas como metadados de um título específico, e aprendizados `dom_learned` nunca devem apagar `app_id` ou tags mais ricas já vindas de APIs oficiais.
- **Não adicionar crates HTML externas no `Cargo.toml`**: reutilizar `tokio-rustls`, `serde_json`, `rusqlite` e `flate2` já presentes no workspace.

---

## 3. Restrições Técnicas Observadas

- `chronos_extension/focus_filters_core.js` e `chronos_extension_firefox/focus_filters_core.js` devem permanecer idênticos (o mesmo vale para `background.js` em ambos pacotes); `rust/src/proxy.rs` embute `chronos_extension/focus_filters_core.js` em tempo de compilação (`include_str!`).
- No sistema local do ambiente atual, `/etc/hosts` contém `127.0.0.1 itch.io www.itch.io` e `::1 itch.io www.itch.io`. A lógica de rede precisa falhar graciosamente em tempo curto se o host estiver bloqueado localmente ou offline, e testes automatizados devem usar payloads/servidores locais mockados em vez de depender de internet/DNS livre.
- No ambiente Flatpak do Heroic (`com.heroicgameslauncher.hgl`), `$HOME` é `/home/<user>` e `$XDG_DATA_HOME` é `~/.var/app/com.heroicgameslauncher.hgl/data` (mesmo caminho dentro e fora do sandbox `bwrap`), enquanto `~/.local/share/chronos/` e `~/.pki/nssdb` são bloqueados/invisíveis dentro do container.

---

## 4. Abordagens Consideradas e Escolha

| Tema | Abordagem Escolhida | Alternativa Descartada | Motivo |
| :--- | :--- | :--- | :--- |
| **APIs fora da Steam** | **Cascata Zero-Key**: `Steam -> GOG Catalog -> LizardByte GameDB -> Itch Web` | Apenas `GameDB` ou `RAWG/IGDB` com chave | `GOG` traz micro-tags estilo Steam (`Roguelike`, `Metroidvania`) para PC; `GameDB` cobre consoles/emuladores/*Minecraft*; zero configuração de usuário. |
| **Catálogo completo `itch.io`** | **Abordagem A**: leitura DOM/HTML na navegação + busca `itch.io/search` sob demanda + aprendizado persistido no `game_metadata_cache` | **Abordagem B** (crawler RSS `.xml` em background) | Atinge todo o catálogo público sob demanda sem risco de rate-limit/bloqueio Cloudflare por varredura contínua e com mínimo código novo. |
| **Heroic Flatpak** | **Wrapper fail-open + CA copiada em `data/chronos-ca/` + NSS DB em `data/pki/nssdb` + `--proxy-server` só quando porta `4546` responde** | `flatpak override --env=http_proxy=...` global | Mantém o Heroic funcional se o Chronos estiver desligado e respeita o isolamento do sandbox `bwrap`. |

---

## 5. Arquitetura, Componentes e Decisões Fechadas

### Componente 1: Heroic, Steam & Lutris (Nativo/Flatpak) Proxy, Trust e Launcher Desktop (`rust/src/launchers.rs`, `rust/src/detector.rs`, `rust/src/engine.rs`, `rust/src/local_api.rs`, `rust/src/api/simple.rs`, `rust/src/bin/chronos_proxy.rs`)

1. **Registro de CA nos bancos NSS reais dos Flatpaks**:
   - Para cada app Flatpak suportado (`com.valvesoftware.Steam`, `com.heroicgameslauncher.hgl`, `net.lutris.Lutris`), se `~/.var/app/<app_id>` existir:
     - Registrar `Chronos Local Focus CA` em **ambos** `~/.var/app/<app_id>/.pki/nssdb` e **`~/.var/app/<app_id>/data/pki/nssdb`** (criando se necessário via `register_ca_in_nss_db_for_home`).
   - Manter `"lutris.desktop"` e `"net.lutris.Lutris.desktop"` em `target_desktops`, o registro no host em `~/.pki/nssdb` e a sincronização de CA de sistema (`sync_system_ca_if_needed`).

2. **Staging da CA dentro de caminho acessível ao sandbox (`data/chronos-ca/`)**:
   - Quando `~/.var/app/<app_id>` existir e `configure_native_launcher_proxy_for_home(..., true)` rodar:
     - Copiar `chronos-combined-ca-bundle.crt` e `chronos-proxy-ca.crt` para `~/.var/app/<app_id>/data/chronos-ca/`.
   - Quando `enable == false`: remover `~/.var/app/<app_id>/data/chronos-ca/` (além dos `.desktop` overrides com marcador e `chronos-launcher-env`).

3. **Wrapper `chronos-launcher-env` ciente de `flatpak run` (fail-open)**:
   - Quando `127.0.0.1:4546` estiver respondendo **e** a linha executada envolver `flatpak` com `com.heroicgameslauncher.hgl`, `com.valvesoftware.Steam` ou `net.lutris.Lutris`:
     - Localizar a posição de `<app_id>` nos argumentos (`flatpak run [opts] <app_id> [app_args...]`).
     - Inserir **antes** de `<app_id>` as flags `--env=http_proxy=http://127.0.0.1:4546`, `--env=https_proxy=http://127.0.0.1:4546`, `--env=HTTP_PROXY=http://127.0.0.1:4546`, `--env=HTTPS_PROXY=http://127.0.0.1:4546`, `--env=no_proxy=...`, `--env=NO_PROXY=...`, `--env=NSS_USE_SHARED_DB=enabled`, e apontar `--env=SSL_CERT_FILE=...`, `--env=CURL_CA_BUNDLE=...`, `--env=REQUESTS_CA_BUNDLE=...`, `--env=NODE_EXTRA_CA_CERTS=...` para os arquivos em `~/.var/app/<app_id>/data/chronos-ca/` quando existirem.
     - Para `com.heroicgameslauncher.hgl`, inserir logo **após** `<app_id>` (antes dos demais argumentos/URIs) `--proxy-server=http://127.0.0.1:4546` e `--proxy-bypass-list=<-loopback>,localhost,127.0.0.1`, garantindo que o Electron/Chromium `<webview>` não ignore `$http_proxy` sob Wayland/`xdg-desktop-portal`.
   - Caso a porta `4546` não responda, executar `exec "$@"` intacto.

4. **Fronteira de opt-in e re-sincronização automática de launchers recém-instalados *(Decisão fechada — Builder Check #1)***:
   - **Opt-in explícito preservado:** `has_launcher_proxy_configured_in_home(&home)` (presença de `chronos-launcher-env` ou de `.desktop` override com marcador) continua sendo o gatilho de opt-in. Como `FocusFilters::default().launcher_filter_enabled` é `true`, não ativamos `.desktop` wrappers nem `pkexec` silenciosamente em instalações virgens sem que o usuário tenha ativado a proteção de loja/proxy ao menos uma vez (e respeitamos `configure_native_launcher_proxy(false)`).
   - **Auto-sync quando já opt-in:** disparar `sync_launcher_proxy_if_configured()` em thread separada (quando `launcher_filter_enabled` está ativo e `has_launcher_proxy_configured_in_home` é `true`) em `rust/src/local_api.rs::apply_focus_filters_update` e `rust/src/api/simple.rs::set_focus_filters`, além da checagem leve `needs_launcher_proxy_resync(&home)` no watchdog do `chronos_proxy.rs`.

5. **Descoberta, Detecção & Bloqueio do Launcher Desktop do Lutris (`launchers.rs`, `detector.rs`, `engine.rs`) *(Ressalva #2)***:
   - **Descoberta unificada nativo + Flatpak (`scan_lutris_and_bottles`)**:
     - Ler `pga.db` em `~/.local/share/lutris/pga.db` e `~/.var/app/net.lutris.Lutris/data/lutris/pga.db` (inspecionando colunas disponíveis para ler também `configpath` e eventual `steamid` com segurança).
     - Enriquecer entradas do `pga.db` e ler arquivos `.yml`/`.yaml` de `~/.config/lutris/games` e `~/.var/app/net.lutris.Lutris/config/lutris/games` via parser ciente de blocos indentados (`game.exe`, `game.prefix`, `game.working_dir`, `game.appid`), mesmo quando o YAML não possui `name:` na raiz (usando título do `pga.db` ou slug humanizado como fallback).
     - Preservar `wine_prefix` / `install_dir` e `exec_hint` normalizados (inclusive basenames `.exe` e barras `/` equivalentes para paths Windows `C:\...` / `Z:\...`).
   - **Detecção e encerramento de jogos Wine/Proton/`umu-run`/nativos**:
     - Em `detect_and_enforce_launcher_filters_with_options` e `detector.rs`: inspecionar `process.environ()` (ou `/proc/<pid>/environ`) para `WINEPREFIX`, `LUTRIS_GAME_UUID`, `UMU_ID`, `SteamAppId`, `SteamGameId`, e casar executáveis mesmo quando `/proc/<pid>/comm` está truncado em 15 bytes (`wine64-preloade`) ou o binário é um wrapper (`wine`, `wine64`, `proton`, `umu-run`, `reaper`).
     - Nunca matar o próprio cliente `lutris` / `net.lutris.Lutris` pelo filtro automático de jogos (apenas o processo/prefixo/janela do jogo bloqueado).
     - Disparar `trigger_async_metadata_prefetch` para entradas casadas tanto por processo quanto por janela quando `cached_meta.is_none()`, passando pela cascata completa (`Steam -> GOG -> GameDB -> Itch`) para que jogos não-Steam no Lutris recebam tags e sejam bloqueados automaticamente.
   - **Esquema URI em `engine.rs`**: reconhecer `"lutris:rungameid/"` além de `"lutris:rungame/"` em `extract_binary_basename`.

---

### Componente 2: DOM, Navegação, Extensões & Proxy para Epic, GOG, `lutris.net` e `itch.io` (`chronos_extension/*`, `chronos_extension_firefox/*`, `rust/src/proxy.rs`, `rust/src/steam_api.rs`, `lib/services/extension_packager.dart`)

1. **Hosts e títulos genéricos**:
   - Incluir `"lutris.net"` em `LAUNCHER_STORE_HOSTS` (ambas extensões JS) e `LAUNCHER_STORE_DOMAINS` (`proxy.rs`).
   - Expandir `GENERIC_STOREFRONT_TITLES` (JS) e `is_generic_storefront_title` (Rust) com `"lutris"`, `"games"`, `"games - lutris"`, `"itch.io"`, `"top games"`, `"browse games"`.
   - Limpar marcações registradas (`®`, `™`, `©`) e sufixos de `<title>` de Epic (`| Baixe e compre hoje - Epic Games Store`, `| Download and Buy Today - Epic Games Store`) e GOG (`on GOG.com`, `| GOG.com`) em JS e `normalize_match_text`.

2. **Correções específicas de lojas externas (`store.epicgames.com` e `www.gog.com`) *(Ressalva #1)***:
   - **URL tags / genres**: incluir `[?&]genres?=` em `hasUrlTagHub` (`focus_filters_core.js`) e `extract_launcher_url_hint` (`steam_api.rs`), limpar prefixos como `GameGenre/` (Epic) e mapear o typo real da GOG `"rougelike"` -> `"Roguelike"`.
   - **Single-game fallback antes da hidratação SPA**: extrair `title` do slug `/p/<slug>`, `/game/<slug>`, `/games/<slug>` e `*.itch.io/<slug>` já na leitura da URL e usá-lo como fallback se `<h1>` ainda não tiver hidratado na SPA; estender `background.js::checkLauncherNavigationRedirect` para resolver qualquer `info.isSingleGamePage && info.title && !isGenericStorefrontTitle(info.title)` (não apenas quando `appId || hasUrlTagHub`).
   - **DOM de `www.gog.com`**: ler tags/gêneros da página em `.genres__item` e `a[href*='genres=']` além de `.game_details`; nos cards, deduplicar nós pai/filho entre `product-tile`, `.product-tile` e `a[href*='/game/']` para não dobrar o lote nem ocultar apenas o link interno deixando célula fantasma; priorizar `[title]` / `.product-tile__title` em cards.
   - **DOM de `store.epicgames.com`**: aplicar `resolveCardContainer` também em `a[href*='/p/']`, `a[href*='/game/']` e `a[href*='/games/']`; extrair título limpo via `[data-testid="offer-title-info-title"]`, `[data-component="OfferTitleInfo"]`, heading/`img[alt]`/`aria-label` sanitizado (sem preços/descontos `R$`, `-50%`) ou slug `/p/<slug>` em vez de `a.textContent` concatenado (que falha busca na API ou passa de 120 chars).
   - **Não-envenenamento de `resolvedCache`**: em `focus_filters_core.js`, não gravar miss permanente em `resolvedCache` quando `RESOLVE_LAUNCHER_ITEMS` falhar/expirar ou retornar erro de rede (`!resp || !resp.success`), permitindo nova tentativa na próxima mutação/scroll.
   - **Empacotamento & Sync de Extensões**: incrementar versão no `manifest.json` de Chrome/Firefox, manter `chronos_extension` e `chronos_extension_firefox` sincronizados, e regenerar `.crx`/`.xpi`/`update.xml` + Firefox profile `.xpi`.
   - **Cloudflare atrás do `chronos_proxy` na `store.epicgames.com`**: registrar explicitamente que `/p/<slug>` continua bloqueado antes do upstream pelo proxy, porém páginas `/browse`/`/` da `store.epicgames.com` atrás de MITM (`rustls` + HTTP/1.1) recebem `403 Cf-Mitigated: challenge` do Cloudflare no Heroic/Firefox; o plano explicará a arquitetura sem bypass anti-bot (Chrome direto sem MITM já opera via extensão; em Firefox, avaliar com o usuário se mantém proxy em Epic ou confia no addon quando aplicável).

3. **Extração JS para `lutris.net` e `itch.io` (`focus_filters_core.js` — idêntico em Chrome e Firefox)**:
   - **`isCommunitySub` / `isSingleGamePage`**: reconhecer `/games/<slug>` em `lutris.net` (excluindo `/games`, `/games/genre/...`, `/games/platform/...`).
   - **Página inteira (`extractPageGameInfo`)**:
     - `lutris.net`: ler título em `h1` (`- Lutris` / `| Lutris`), tags em `a[href*="/games/genre/"]` e `.game-info li` iniciados por `"Genre:"`/`"Gênero:"`, e `/games/genre/<slug>` da URL.
     - `itch.io` / `*.itch.io`: extrair `/games/tag-<slug>` e `/games/genre-<slug>` da URL; ler `.game_info_panel_widget a[href*="/games/tag-"]`, `.game_info_panel_widget a[href*="/games/genre-"]`, linhas rotuladas `Genre`/`Tags`, `.tags a[href*="/games/tag-"]` e JSON-LD (`genre`, `keywords`).
   - **Cards (`extractCards`)**: `lutris.net` (`.game-preview`, `.game-name`, `.game-details a[href*="/games/genre/"]`, `.game-details .small-text` `Genre: ...`); `itch.io` (`.game_cell`, `.game_title`, `.game_genre`, `.tag_link`, `a[href*="/games/tag-"]`).
   - **Aprendizado mesmo quando `localHit` dispara na 1ª visita *(Decisão fechada — Builder Check #2)***:
     - Quando `doc` existir e `info.isSingleGamePage && !info.isSearchQuery && info.title && info.siteTags.length > 0`, disparar `resolveItems` com `keepalive: true` antes de redirecionar via `onBlockPage`, enviando `isSingleGamePage` e `isSearchQuery`.

4. **Dicas de URL em Rust (`steam_api::extract_launcher_url_hint`)**:
   - Adicionar `gog.com` (`?genres=`, `/game/<slug>`), `store.epicgames.com` (`?tag=`, `?category=GameGenre/...`, `/p/<slug>`), `lutris.net` (`/games?q=`, `/games/genre/<slug>`, `/games/<slug>`), `itch.io` / `*.itch.io` (`/games/tag-<slug>`, `/games/genre-<slug>`, `*.itch.io/<slug>`).

---

### Componente 3: Cascata Externa Zero-Key + `itch.io` Sob Demanda + Cache Aprendido (`rust/src/steam_api.rs`, `rust/src/local_api.rs`, `rust/src/proxy.rs`, `rust/src/api/simple.rs`, `lib/services/web_block_server.dart`)

1. **Helpers de parsing leve & similaridade de título (`steam_api.rs`)**:
   - Função `is_confident_title_match(query, candidate)` exigindo igualdade normalizada/compacta, ou prefixo/contenção forte quando ambos têm comprimento significativo, evitando falsos positivos entre nomes curtos distintos.
   - Helpers puros (sem dependências extras no `Cargo.toml`) para:
     - **GOG Catalog API** (`https://catalog.gog.com/v1/catalog?limit=5&query=like:<encoded>`): parse de `products[]` (`title`, `genres[].name`, `tags[].name`, `coverHorizontal`/`coverVertical`).
     - **LizardByte GameDB (IGDB)** (`https://app.lizardbyte.dev/GameDB/buckets/<2chars>.json` -> `https://app.lizardbyte.dev/GameDB/games/<id>.json`): cálculo do bucket de 2 caracteres alfanuméricos minúsculos a partir do título normalizado (tratando títulos com menos de 2 caracteres alfanuméricos); mapeamento de `genres[].name`, `themes[].name`, `game_modes[].name`, e classificação explícita `AO` apenas para `age_ratings` verdadeiramente adult-only (sem marcar `M`/`PEGI 18` genéricos como `NSFW`).
     - **Itch.io Web On-Demand** (`https://itch.io/search?q=<encoded>` -> HTML `.game_cell` -> `<game_url>`): parser HTML delimitado de `.game_cell` (`data-game_id`, link `*.itch.io/<slug>`, `.game_title`, `.game_genre`) e parser da página do jogo (`.game_info_panel_widget` `/games/tag-*`, `/games/genre-*` e `<script type="application/ld+json">`).

2. **Perfis de latência e miss-cache *(Decisão fechada — Builder Check #3)***:
   - Para evitar travar navegação no proxy por 16–20s caso múltiplos provedores falhem ou `itch.io` esteja inacessível (`/etc/hosts`/rede lenta):
     - Manter um cache em memória de misses recentes (`OnceLock<Mutex<HashMap<String, i64>>>` com TTL curto de `60s` por `(app_id, title_norm)`) apenas quando toda a cascata externa falhar sem rede/sem hit.
     - Usar timeout de `2500ms` por hop externo para provedores secundários (`GOG`, `GameDB`, `Itch Web`) e envolver a chamada síncrona em `proxy.rs::check_launcher_page_block` com `tokio::time::timeout(Duration::from_millis(3500), ...)` — se estourar no proxy antes de carregar o HTML, faz fallback fail-open imediato e o script injetado (`focus_filters_core.js`) + `/__chronos_api__/launchers/resolve` finaliza a resolução/bloqueio assim que o DOM abre (sem cache negativo permanente).
     - Em `handle_launchers_resolve_payload` (`local_api.rs`), substituir o loop sequencial de resoluções por execução concorrente limitada (ex.: até `6` futuras via `tokio::task::JoinSet` / `futures` padrão do `tokio`) dentro de um budget por lote (`~6s`) para filtrar cards em ~1–2s em vez de >15s.

3. **Precedência e merge no `game_metadata_cache` *(Decisão fechada — Builder Check #2)***:
   - Ao ler cache (`title:<norm>`), se existir entrada cujo `tags` e `genres` e `categories` estão todos vazios (`meta.tags.is_empty() && meta.genres.is_empty()`), permitir fallback externo em vez de bloquear com cache vazio.
   - `save_learned_dom_metadata(title, tags)` **nunca** deve sobrescrever `app_id`, `source` ou tags já existentes de fontes de API (`Steam`, `gog_catalog`, `gamedb_igdb`, `itch_web`): quando já houver entrada para `title:<norm>`, apenas faz **união** das novas tags canonicalizadas preservando `app_id`, `genres`, `categories` e `source` original; só grava `source = "dom_learned"` quando não existir entrada prévia.
   - Da mesma forma, quando uma consulta da cascata resolver por nome e houver entrada prévia `dom_learned`, mescla as tags aprendidas com os dados mais ricos da API (`merge_metadata`), atualizando para a fonte API.

4. **Fluxo `resolve_game_metadata_async(app_id, title_hint)`**:
   - Cache SQLite (`appid:<id>`, `title:<norm>`).
   - **Passo 1 — Steam API**: exige `is_confident_title_match(title_hint, &meta.title)` quando `app_id.is_none()`.
   - **Passo 2 — GOG Catalog**: se Passo 1 falhar/não casar título -> consulta GOG, canonicaliza, mescla com eventual `dom_learned`, salva (`source = "gog_catalog"`).
   - **Passo 3 — LizardByte GameDB**: se Passo 2 falhar -> bucket + ficha IGDB, canonicaliza (`Role-playing (RPG)` -> `RPG`, etc.), salva (`source = "gamedb_igdb"`).
   - **Passo 4 — Itch.io Web On-Demand**: se Passo 3 falhar -> `itch.io/search?q=...`, entra na ficha do jogo se houver match confiável (ou usa `.game_genre` do card se a ficha falhar), salva (`source = "itch_web"`).

5. **Persistência de tags aprendidas pelo DOM (`handle_launchers_resolve_payload` em `local_api.rs`)**:
   - Aceitar campo opcional `isSingleGamePage: bool` (também aceitando `isDetailPage: bool` como alias) padrão `false`.
   - Quando `(isSingleGamePage || isDetailPage) && !is_search_query && !title.is_empty() && !is_generic_storefront_title(&title) && !site_tags.is_empty()`: chamar `save_learned_dom_metadata(&title, &site_tags)` (com respeito à precedência API acima).

6. **Autocomplete multi-fonte (`search_game_suggestions_async` em `steam_api.rs`)**:
   - Consultar Steam + GOG Catalog + LizardByte GameDB bucket em paralelo (`tokio::join!` com timeout curto) + jogos locais instalados; consultar `itch.io/search?q=<encoded>` se os resultados relevantes forem `< limit` ou `query.len() >= 3` sem match exato nas lojas PC.
   - Deduplicar por título normalizado priorizando Steam > GOG > GameDB > Itch > local, com `app_id = 0` e `source` legível (`"GOG"`, `"IGDB (GameDB)"`, `"Itch.io"`).

7. **Mensagens por fonte & Escopo do servidor fallback (`local_api.rs`, `proxy.rs`, `simple.rs`, `web_block_server.dart`) *(Decisão fechada — Builder Check #4)***:
   - Em `local_api.rs`, `proxy.rs` e `api/simple.rs::lookup_steam_game_metadata` (`LauncherGameDto.launcher`), mapear `meta.source` para rótulo legível (`"Steam API"`, `"GOG"`, `"IGDB"`, `"Itch.io"`, `"Página"`) em vez de hardcodear `"(Steam API)"` ou `"Genérico"`.
   - Para `lib/services/web_block_server.dart`: como o filtro de lojas/proxy (`4546`, Heroic Flatpak, HTML MITM) requer o daemon `chronos_proxy` ativo (`4545`/`4546`), mantemos o parser de hints URL/DOM completo apenas no backend Rust (`chronos_proxy` + `local_api.rs`), garantindo apenas que `WebBlockServer._handleLaunchersResolve` não quebre com campos opcionais novos (`isSingleGamePage`) e herde os novos metadados/fontes automaticamente via `lookupSteamGameMetadata` (`simple.rs`).

---

## 6. O que Fica a Cargo do Plano de Implementação (Builder)

- Assinaturas exatas dos parsers HTML/JSON internos e escolha dos testes unitários com payloads reais capturados em fixtures (incluindo fixtures reais de `www.gog.com`, `store.epicgames.com`, `lutris.net`, Lutris `pga.db`/YAML/`.exe`/environ Wine/Proton/`umu-run`, GOG Catalog, GameDB e `itch.io` `.game_cell`/`.game_info_panel_widget`).
- Script/lógica exata de reescrita de argumentos no `chronos-launcher-env` (preservando `--branch=stable --arch=x86_64 --command=heroic-run --command=... --file-forwarding` e `@@u ... @@` para Heroic, Steam e Lutris Flatpak).
- Reempacotamento das extensões `.crx`/`.xpi` (bump de versão + via `extension_packager` / build do app) e rebuild/restart do binário `chronos_proxy` em `~/.local/share/chronos/bin/chronos_proxy` no plano de verificação, além do checklist manual com lojas externas (`store.epicgames.com`, `www.gog.com`), Heroic Flatpak, Lutris (web + desktop), e `itch.io`.
