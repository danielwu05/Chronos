# Contexto do Projeto: Chronos

## 1. Visão Geral
- **Nome do Projeto:** Chronos
- **Propósito:** Aplicação desktop offline-first de produtividade e autocontrole estrito para Linux (Arch Linux / Hyprland / Wayland / X11).
- **Objetivo Principal:** Monitorar o consumo de tempo em aplicações e sites distratores (foco atual: YouTube), debitar cotas diárias em tempo real, impedir bypasses via travas unilaterais (Modo Catraca/Ratchet) e forçar bloqueios ativos (Overlay e pausa de mídia).

## 2. Stack Tecnológica
- **Frontend / UI:** Flutter Desktop (Linux GTK3, Material 3, Dark Theme).
- **Core / Daemon:** Rust (crate interna em `rust/`).
- **Ponte FFI:** `flutter_rust_bridge` (v2.13.0).
- **Persistência:** SQLite local via `rusqlite` (compilação estática `bundled`), operando em modo WAL (`PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON;`).
- **Detecção de Sistema:**
  - `sysinfo`: varredura de processos no `/proc`.
  - `playerctl` (MPRIS2 via D-Bus): monitoramento de reprodução de mídia em navegadores/players.
  - `hyprctl` / `xdotool`: captura de janela em foco.
- **Enforcement:** `window_manager` no Flutter (always-on-top + maximizar) e comandos de pausa via `playerctl pause`.

## 3. Modelo de Banco de Dados (`rust/src/db.rs`)
- `app_config`:
  - `key` (TEXT, PK)
  - `value` (TEXT)
  - `updated_at_utc` (INTEGER)
  - Controla: `is_onboarded` (booleano de cadastro inicial), `app_mode` ('SELF_CONTROL' ou 'PARENTAL'), `device_role` ('NONE', 'PARENT', 'CHILD'), `device_id`, `pairing_code` e `is_paired`.
- `rules`:
  - `entity_id` (TEXT, PK)
  - `display_name` (TEXT)
  - `daily_quota_seconds` (INTEGER)
  - `is_blocked_completely` (INTEGER, 0 ou 1)
  - `mode` ('PARENTAL' ou 'SELF_CONTROL')
  - `ratchet_locked_until_utc` (INTEGER, timestamp de bloqueio da Catraca)
  - `updated_at_utc` (INTEGER)
  - `target_type` ('APP', 'SITE', 'KEYWORD' ou 'GROUP')
  - `pattern` (TEXT: domínios, palavras-chave ou lista de executáveis de uma sessão)
  - `weekend_quota_seconds` (INTEGER: cota diferenciada para Sábado e Domingo)
  - `schedule_json` (TEXT: serialização opcional de cronograma)
- `usage_intervals`: modelo de União de Intervalos com `interval_id`, `entity_id`, `device_id`, `started_at_utc`, `ended_at_utc`, `synced`.
- `emergency_tokens`: controle de tokens mensais (tabela singleton `id = 1`) com `remaining_tokens` e `leisure_locked_until_utc`.
- `install_quarantine`: fila de análise de novos binários.

## 4. Estado Atual dos Arquivos
- **`rust/src/db.rs`:**
  - Banco SQLite inicializado em WAL, gerencia mutex thread-safe (`parking_lot::Mutex<Connection>`).
  - Preenche regras padrão para múltiplas entidades (`youtube`, `discord`, `steam`, `twitter`, `reddit`).
  - Suporte completo a rotinas de teste e manutenção: `reset_database_full`, `reset_daily_usage`, `debug_unlock_ratchet`, `refill_emergency_tokens` e `get_database_stats`.
- **`rust/src/detector.rs`:**
  - Detecta janelas ativas via `hyprctl activewindow -j` e fallback `xdotool`.
  - Detecta reprodução via MPRIS em segundo plano com suporte a navegadores (Chromium, Brave, Firefox).
  - Implementa "Sticky Session" com `LAST_YOUTUBE_SEEN_UTC` (`AtomicI64`): se o usuário mudar de aba e o título "YouTube" sumir da janela, mantém o débito ativo por até 120s caso o player continue em status `Playing`.
  - Pausa mídias ativas quando a cota atinge zero (`pause_background_media`).
  - Varredura de binários e processos suspeitos/não-confiáveis (`find_untrusted_processes`) executados fora de diretórios oficiais de pacotes.
- **`rust/src/engine.rs`:**
  - `tick_entity`: loop reativo que estende sessões ativas no SQLite ou cria novos intervalos se houver hiato > 3s.
  - Suporte a múltiplos tipos de alvo: `APP` (processos e janelas), `SITE` (domínios e URLs via MPRIS/browser) e `KEYWORD` (palavras-chave na janela e mídia).
  - `list_installed_desktop_apps`: varredura automática dos diretórios `/usr/share/applications` e `~/.local/share/applications` buscando programas instalados (.desktop) no Linux.
  - Retorna `TickState` completo com cota diária, tempo consumido, tempo restante, estado de trava da catraca e tokens de emergência.
  - `activate_ratchet_lock`: tranca a Catraca por N horas.
  - `update_quota_ratchet`: permite reduções imediatas de tempo, mas proíbe aumentos se a Catraca estiver travada.
  - `use_emergency_token`: desconta 1 token mensal, concede +1h de emergência e aplica penalidade travando o lazer por 24h.
  - CRUD e controle de regras (`get_all_rules`, `save_rule`, `delete_rule`, `toggle_entity_block`).
  - Gestão de quarentena de binários (`get_quarantine_items`, `review_quarantine`, `scan_system_untrusted_processes`).
- **`rust/src/api/simple.rs`:** Expõe para Dart:
  - Stream reativo (`start_tracking_stream` via `StreamSink<LiveEngineTick>`).
  - Varredura de aplicativos instalados (`get_installed_applications`).
  - Ações de cota: `change_quota`, `lock_ratchet`, `consume_emergency_token`.
  - Ações de teste e reset de banco: `reset_database_full`, `reset_daily_usage`, `debug_unlock_ratchet`, `refill_emergency_tokens`, `get_database_stats`.
  - Onboarding e pareamento: `get_onboarding_state`, `save_onboarding_choice`, `verify_and_pair_device`, `reset_onboarding_state`.
  - Regras: `get_all_rules`, `save_rule`, `delete_rule`, `toggle_entity_block`.
  - Quarentena: `get_quarantine_items`, `review_quarantine_item`, `scan_system_processes`.
- **`lib/main.dart` & `lib/widgets/` & `lib/screens/`:**
  - Inicializa `windowManager` e `RustLib`.
  - **Fluxo de Cadastro / Onboarding ([`OnboardingScreen`](file:///home/dwu/Downloads/Faculdade/misc/chronos_app/lib/screens/onboarding_screen.dart)):**
    - Escolha de Modo (Pessoal vs Parental).
    - No Modo Pessoal: Personalização de Bloqueios inicial com ajuste de cotas, ativação de Catraca 24h e botão para adicionar novos apps/sites instalados.
    - No Modo Parental: Escolha de papel (Pai vs Filho) e pareamento via QR Code ou Senha/PIN.
  - **Modal Universal de Adição de Bloqueio ([`AddBlockDialog`](file:///home/dwu/Downloads/Faculdade/misc/chronos_app/lib/widgets/add_block_dialog.dart)):**
    - Permite escolher entre **Aplicativo Instalado** (janela de busca e seleção de todos os executáveis do Linux) e **Site / Web** (com opção entre Bloquear Site por Domínio ou Bloquear por Palavras-Chave).
  - **Botão de Retorno ao Cadastro:**
    - Botão no AppBar e banner no Dashboard permitindo voltar à tela inicial de cadastro durante os testes.

- **`lib/services/web_block_server.dart` & `chronos_extension/`:**
  - **Servidor HTTP Local (`WebBlockServer` na porta 4545):**
    - Servidor embutido no app Chronos que atende requisições de status e checagem de regras em `/api/status` e `/api/check`.
    - Serve a página criada de bloqueio de sites em `/blocked` (`http://127.0.0.1:4545/blocked?entity=...&site=...`), exibindo aviso claro de limite esgotado, cota configurada, horário de liberação e botão de ativação de Token de Emergência (+1h).
    - Endpoint `/api/emergency-token` para consumir token diretamente pela página.
  - **Extensão do Navegador (`chronos_extension` - Manifest V3):**
    - Intercepta acessos a sites bloqueados antes da navegação (`onBeforeNavigate`) e monitora abas abertas em segundo plano.
    - Substitui automaticamente o site bloqueado no Chrome/Chromium pela página de aviso criada.
  - **Diferenciação de Bloqueio (Sites vs Apps):**
    - No caso de `target_type == 'SITE'`, o Chronos **não sequestra o foco nem maximiza o app desktop**, mantendo o usuário no navegador onde o site é substituído pela página de limite esgotado.
    - No caso de `target_type == 'APP'`, o overlay desktop em tela cheia (`FocusOverlay`) continua atuando.

## 5. Próximos Passos no Roadmap
1. Criar a interface de visualização controlada do YouTube (via InAppWebView com injeção de CSS para ocultação de Shorts e algoritmo de recomendação).
2. Protocolo de pareamento criptográfico (BIP-39 + chaves Ed25519) para autoridade remota (Modo Parental).
