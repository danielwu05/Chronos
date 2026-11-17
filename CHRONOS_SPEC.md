# Chronos — Especificação Funcional e Arquitetura do Sistema

Documento de especificação técnica e funcional do **Chronos**, desenvolvido para servir de contexto operacional contínuo para agentes de inteligência artificial e desenvolvedores.

---

## 1. Visão Geral e Filosofia do Projeto

* **Nome:** Chronos
* **Ecossistema:** Linux Desktop (Arch Linux, Hyprland/Wayland, X11/XWayland).
* **Propósito:** Aplicação offline-first de produtividade e autocontrole estrito com tolerância zero a desvios (*anti-cheat / anti-distraction*).
* **Premissas Fundamentais:**
  * **Offline-First:** Banco de dados relacional embutido sem dependência de nuvem para execução das regras.
  * **Assimetria de Decisão (Modo Catraca):** O usuário pode reduzir suas cotas de distração ou reforçar travas a qualquer momento com efeito imediato, mas qualquer tentativa de aumento ou afrouxamento é unilateralmente bloqueada ou submetida a atrito severo.
  * **Detecção Multi-camada:** Rastreamento simultâneo de processos no sistema operacional, janelas ativas em foco, e reprodução de mídia em navegadores via D-Bus/MPRIS2 (inclusive em abas em segundo plano e telas secundárias).
  * **Enforcement Físico:** Interrupção forçada de mídias via comandos de barramento e sequestro visual de foco (*fullscreen always-on-top overlay*) quando o limite é atingido.

---

## 2. Stack Tecnológica

| Camada | Tecnologia | Função / Responsabilidade |
|---|---|---|
| **Frontend / UI** | Flutter Desktop (Linux GTK3) | Interface gráfica com Material 3 Dark, exibição de telemetria em tempo real, painel de controle de cotas e renderização do overlay bloqueador. |
| **Window Control** | `window_manager` | Controle programático de janela Flutter: fullscreen, always-on-top, maximização forçada e sequestro de foco. |
| **Core / Daemon** | Rust | Engine de baixo nível, inspeção de processos, comandos de sistema, máquina de estados das cotas e loop de telemetria. |
| **FFI Bridge** | `flutter_rust_bridge` (v2) | Serialização binária assíncrona de alta performance e streaming contínuo de dados Rust para o Dart via `StreamSink`. |
| **Banco de Dados** | SQLite (via `rusqlite` bundled) | Armazenamento transacional local em modo WAL (*Write-Ahead Logging*). |
| **Media Bus** | `playerctl` (MPRIS2 / D-Bus) | Inspeção de metadados de reprodutores de áudio/vídeo e despacho de comandos de pausa (`pause`). |
| **Window Query** | `hyprctl` / `xdotool` / `wmctrl` | Consulta de árvore de clientes de janelas no Wayland nativo (Hyprland) e X11. |
| **Process Inspection** | `sysinfo` | Varredura de `/proc` para identificação e terminação direta (`kill`) de executáveis nativos. |

---

## 3. Modelo de Banco de Dados (`chronos.db`)

O banco SQLite roda configurado com:
`PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL; PRAGMA foreign_keys = ON;`

```sql
-- 1. Regras de cota diária e travas
CREATE TABLE IF NOT EXISTS rules (
    entity_id TEXT PRIMARY KEY,
    display_name TEXT NOT NULL,
    daily_quota_seconds INTEGER NOT NULL,
    is_blocked_completely INTEGER NOT NULL DEFAULT 0,
    mode TEXT NOT NULL,
    ratchet_locked_until_utc INTEGER,
    updated_at_utc INTEGER NOT NULL
);

-- 2. União de Intervalos consumidos (Deltas de Uso)
CREATE TABLE IF NOT EXISTS usage_intervals (
    interval_id TEXT PRIMARY KEY,
    entity_id TEXT NOT NULL,
    device_id TEXT NOT NULL,
    started_at_utc INTEGER NOT NULL,
    ended_at_utc INTEGER NOT NULL,
    synced INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (entity_id) REFERENCES rules (entity_id)
);

-- 3. Tokens de emergência (Singleton id = 1)
CREATE TABLE IF NOT EXISTS emergency_tokens (
    id INTEGER PRIMARY KEY CHECK (id = 1),
    remaining_tokens INTEGER NOT NULL DEFAULT 2,
    leisure_locked_until_utc INTEGER NOT NULL DEFAULT 0,
    last_reset_month INTEGER NOT NULL
);

-- 4. Fila de quarentena de instaladores
CREATE TABLE IF NOT EXISTS install_quarantine (
    request_id TEXT PRIMARY KEY,
    app_identifier TEXT NOT NULL,
    display_name TEXT NOT NULL,
    platform TEXT NOT NULL,
    status TEXT NOT NULL,
    requested_at_utc INTEGER NOT NULL
);
