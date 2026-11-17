#!/usr/bin/env bash
# Instala o Chronos Guard em paths protegidos pelo root (/usr/local, /etc).
# Deve ser executado uma única vez com privilégio administrativo (pkexec ou sudo).

set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "install-guard: execute como root (sudo ou pkexec)." >&2; exit 1; }

SCRIPT_DIR="${2:-$(cd "$(dirname "$0")" && pwd)}"
TARGET_USER="${1:-${SUDO_USER:-${PKEXEC_UID:+$(id -nu "$PKEXEC_UID")}}}"
[ -n "${TARGET_USER:-}" ] || TARGET_USER="$(logname 2>/dev/null || echo dwu)"
TARGET_HOME="$(getent passwd "$TARGET_USER" | cut -d: -f6)"

# 1. Instala binário do guard (somente root pode modificar) e link no PATH
install -d -m 0755 /usr/local/lib/chronos /usr/local/bin
install -m 0755 -o root -g root "$SCRIPT_DIR/chronos-guard" /usr/local/lib/chronos/chronos-guard
ln -sf /usr/local/lib/chronos/chronos-guard /usr/local/bin/chronos-guard

# 2. Instala pacotes CRX3 / XPI, config, Root CA público e PAC no store protegido
install -d -m 0755 /usr/local/share/chronos
install -m 0644 -o root -g root "$SCRIPT_DIR/chronos.crx"  /usr/local/share/chronos/chronos.crx
install -m 0644 -o root -g root "$SCRIPT_DIR/guard.conf"   /usr/local/share/chronos/guard.conf
[ -f "$SCRIPT_DIR/chronos.xpi" ] && install -m 0644 -o root -g root "$SCRIPT_DIR/chronos.xpi" /usr/local/share/chronos/chronos.xpi
[ -f "$SCRIPT_DIR/chronos-proxy-ca.crt" ] && install -m 0644 -o root -g root "$SCRIPT_DIR/chronos-proxy-ca.crt" /usr/local/share/chronos/chronos-proxy-ca.crt
[ -f "$SCRIPT_DIR/proxy.pac" ] && install -m 0644 -o root -g root "$SCRIPT_DIR/proxy.pac" /usr/local/share/chronos/proxy.pac

# 3. Ação polkit (padrão: exige senha administrativa)
install -d -m 0755 /usr/share/polkit-1/actions
cat > /usr/share/polkit-1/actions/org.chronos.guard.policy <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE policyconfig PUBLIC
 "-//freedesktop//DTD PolicyKit Policy Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/PolicyKit/1/policyconfig.dtd">
<policyconfig>
  <vendor>Chronos</vendor>
  <action id="org.chronos.guard.run">
    <description>Chronos Guard Browser Policy Manager</description>
    <message>Autenticação necessária para alterar a proteção dos navegadores</message>
    <defaults>
      <allow_any>auth_admin</allow_any>
      <allow_inactive>auth_admin</allow_inactive>
      <allow_active>auth_admin_keep</allow_active>
    </defaults>
    <annotate key="org.freedesktop.policykit.exec.path">/usr/local/lib/chronos/chronos-guard</annotate>
  </action>
</policyconfig>
EOF
chmod 0644 /usr/share/polkit-1/actions/org.chronos.guard.policy

# 4. Regra polkit: libera SEM senha apenas subcomandos que reforçam/atualizam proteção.
install -d -m 0755 /etc/polkit-1/rules.d
ESCAPED_HOME="${TARGET_HOME//\//\\/}"
cat > /etc/polkit-1/rules.d/49-chronos-guard.rules <<EOF
polkit.addRule(function(action, subject) {
  if (action.id === "org.chronos.guard.run" && subject.user === "$TARGET_USER") {
    var cmd = action.lookup("command_line") || "";
    if (cmd === "/usr/local/lib/chronos/chronos-guard apply" ||
        cmd === "/usr/local/lib/chronos/chronos-guard apply --quiet" ||
        /^\/usr\/local\/lib\/chronos\/chronos-guard update-crx ${ESCAPED_HOME}\/\.local\/share\/chronos\/guard\/build\/chronos\.crx [0-9.]+$/.test(cmd) ||
        cmd === "/usr/local/lib/chronos/chronos-guard update-ca ${TARGET_HOME}/.local/share/chronos/ca/chronos-proxy-ca.crt ${TARGET_HOME}/.local/share/chronos/proxy.pac") {
      return polkit.Result.YES;
    }
  }
});
EOF
chmod 0644 /etc/polkit-1/rules.d/49-chronos-guard.rules

# 5. Serviço systemd que restaura políticas continuamente
cat > /etc/systemd/system/chronos-guard.service <<'EOF'
[Unit]
Description=Chronos Browser Extension & Focus Policy Guard
After=local-fs.target

[Service]
Type=simple
ExecStartPre=/usr/local/lib/chronos/chronos-guard apply --quiet
ExecStart=/usr/local/lib/chronos/chronos-guard watch
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF
chmod 0644 /etc/systemd/system/chronos-guard.service

systemctl daemon-reload
systemctl enable --now chronos-guard.service
systemctl restart chronos-guard.service
/usr/local/lib/chronos/chronos-guard apply

echo "Chronos Guard instalado e ativo para Chrome, Chromium, Brave, Edge, Vivaldi, Opera e Firefox!"
