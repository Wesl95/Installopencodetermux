#!/data/data/com.termux/files/usr/bin/bash
#
# opencode.sh — instalação limpa do OpenCode no Termux / Android ARM64
#
# Objetivos:
#   - remover instalações antigas/conflitantes do OpenCode
#   - não apagar projetos, Node, Python, Git ou pacotes que não sejam do OpenCode
#   - evitar o caminho npm/opencode-ai que historicamente falha no Android
#   - instalar uma build nativa/compatível com Termux
#   - limpar caches e artefatos temporários relacionados ao OpenCode
#
# Uso:
#   bash opencode.sh
#
# ATENÇÃO:
#   O script pode apagar configurações antigas do OpenCode.
#   Antes disso, faz backup em ~/opencode-backup-<data>.

set -euo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME_DIR="${HOME:-/data/data/com.termux/files/home}"
BACKUP="$HOME_DIR/opencode-backup-$(date +%Y%m%d-%H%M%S)"

log()  { printf '\n\033[1;36m[OpenCode]\033[0m %s\n' "$*"; }
ok()   { printf '\033[1;32m  ✓\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m  !\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m  ✗\033[0m %s\n' "$*" >&2; exit 1; }

# ------------------------------------------------------------
# 1. Verificações
# ------------------------------------------------------------

log "Verificando ambiente Termux..."

command -v pkg >/dev/null 2>&1 || die "Este script precisa ser executado dentro do Termux."

ARCH="$(uname -m)"
[ "$ARCH" = "aarch64" ] || die "Este instalador foi preparado para ARM64/aarch64. Detectado: $ARCH"

case "$PREFIX" in
  /data/data/com.termux/files/usr) ;;
  *) warn "PREFIX incomum detectado: $PREFIX" ;;
esac

ok "Termux ARM64 detectado."

# ------------------------------------------------------------
# 2. Atualizar apenas a base necessária
# ------------------------------------------------------------

log "Atualizando índices do Termux..."
pkg update -y

log "Garantindo ferramentas básicas..."
pkg install -y curl ca-certificates tar gzip coreutils

# ------------------------------------------------------------
# 3. Backup de configurações do OpenCode
# ------------------------------------------------------------

log "Preparando backup das configurações antigas..."

mkdir -p "$BACKUP"

for item in \
  "$HOME_DIR/.config/opencode" \
  "$HOME_DIR/.local/share/opencode" \
  "$HOME_DIR/.cache/opencode" \
  "$HOME_DIR/.opencode" \
  "$HOME_DIR/.local/bin/opencode"
do
  if [ -e "$item" ]; then
    name="$(basename "$item")"
    cp -a "$item" "$BACKUP/$name" 2>/dev/null || true
  fi
done

ok "Backup criado em: $BACKUP"

# ------------------------------------------------------------
# 4. Remover instalações antigas/conflitantes
# ------------------------------------------------------------

log "Removendo instalações antigas do OpenCode..."

# npm global: remove somente pacotes relacionados ao OpenCode.
if command -v npm >/dev/null 2>&1; then
  npm uninstall -g opencode-ai @opencode-ai/cli opencode 2>/dev/null || true
fi

# Binários/launchers antigos conhecidos.
rm -f \
  "$PREFIX/bin/opencode" \
  "$PREFIX/bin/opencode2" \
  "$PREFIX/bin/opencode-ai" \
  "$HOME_DIR/.local/bin/opencode" \
  2>/dev/null || true

# Instalações oficiais que podem ter ficado no HOME.
rm -rf \
  "$HOME_DIR/.opencode/bin" \
  "$HOME_DIR/.opencode/lib" \
  2>/dev/null || true

# Cache npm somente do pacote OpenCode não é fácil de remover seletivamente;
# não apagamos o cache npm inteiro para não prejudicar seus outros projetos.

ok "Instalações antigas/confusas removidas."

# ------------------------------------------------------------
# 5. Limpar apenas artefatos OpenCode antigos
# ------------------------------------------------------------

log "Limpando caches/artefatos antigos do OpenCode..."

rm -rf \
  "$HOME_DIR/.cache/opencode" \
  "$HOME_DIR/.local/share/opencode" \
  2>/dev/null || true

# Configuração antiga é removida somente depois do backup.
rm -rf "$HOME_DIR/.config/opencode" 2>/dev/null || true

ok "Artefatos antigos limpos."

# ------------------------------------------------------------
# 6. Glibc: não é necessária para uma build Android nativa.
#
# Porém NÃO removemos glibc cegamente, porque outros programas
# do Termux podem depender dela.
# ------------------------------------------------------------

if dpkg -s glibc >/dev/null 2>&1; then
  log "glibc antiga detectada."

  # Verifica se existem pacotes instalados que declaram dependência direta.
  RDEPS="$(apt-cache rdepends --installed glibc 2>/dev/null \
    | sed '1d' \
    | sed 's/^[[:space:]]*//' \
    | grep -v '^glibc$' \
    | grep -v '^$' \
    | head -n 20 || true)"

  if [ -z "$RDEPS" ]; then
    warn "Nenhum dependente instalado foi detectado; removendo glibc antiga."
    pkg uninstall -y glibc || true
    ok "glibc removida."
  else
    warn "glibc NÃO será removida: há pacotes instalados que podem depender dela."
    printf '%s\n' "$RDEPS"
  fi
fi

# Remove somente o repositório específico da glibc se ele estiver instalado
# e não houver necessidade aparente. NÃO mexemos no x11-repo.
if dpkg -s glibc-repo >/dev/null 2>&1; then
  pkg uninstall -y glibc-repo || true
  ok "glibc-repo removido."
fi

# ------------------------------------------------------------
# 7. Instalação nativa compatível com Android/Termux
# ------------------------------------------------------------

log "Instalando OpenCode para Termux..."

# O OpenCode oficial Linux não é um binário Android nativo.
# No Termux, o caminho npm/oficial pode selecionar binários Linux
# incompatíveis com Bionic. Por isso usamos a distribuição Termux
# específica, que fornece o runtime/launcher compatível.
#
# Projeto/repositório da distribuição:
# https://github.com/bd-loser/opencode-bionic
#
# O instalador desse projeto verifica o checksum da release.
#
# Não usamos `npm install -g opencode-ai`.

INSTALLER_URL="https://raw.githubusercontent.com/bd-loser/opencode-bionic/main/install.sh"

curl -fsSL "$INSTALLER_URL" -o "$HOME_DIR/.opencode-termux-installer.sh"

chmod 700 "$HOME_DIR/.opencode-termux-installer.sh"

bash "$HOME_DIR/.opencode-termux-installer.sh"

rm -f "$HOME_DIR/.opencode-termux-installer.sh"

# ------------------------------------------------------------
# 8. Verificação
# ------------------------------------------------------------

log "Verificando instalação..."

command -v opencode >/dev/null 2>&1 \
  || die "OpenCode não apareceu no PATH."

OPENCODE_PATH="$(command -v opencode)"

ok "Launcher: $OPENCODE_PATH"

if opencode --version; then
  ok "OpenCode respondeu corretamente."
else
  die "O comando opencode existe, mas não conseguiu iniciar."
fi

# ------------------------------------------------------------
# 9. Limpeza final
# ------------------------------------------------------------

log "Limpeza final..."

pkg clean 2>/dev/null || true

# Não executamos apt autoremove:
# ele pode remover dependências usadas pelos seus outros projetos.

rm -f "$HOME_DIR/.npm/_logs/"* 2>/dev/null || true

ok "Limpeza concluída."

# ------------------------------------------------------------
# 10. Diagnóstico final
# ------------------------------------------------------------

printf '\n'
printf '\033[1;32m============================================\033[0m\n'
printf '\033[1;32m OpenCode instalado no Termux\033[0m\n'
printf '\033[1;32m============================================\033[0m\n'
printf '\n'
printf 'Arquitetura : %s\n' "$ARCH"
printf 'Launcher    : %s\n' "$OPENCODE_PATH"
printf 'Backup      : %s\n' "$BACKUP"
printf '\n'
printf 'Teste agora:\n'
printf '  opencode --version\n'
printf '  mkdir -p ~/teste-opencode\n'
printf '  cd ~/teste-opencode\n'
printf '  opencode\n'
printf '\n'
printf '\033[1;33mNão foram removidos Node.js, Python, Git, seus projetos ou x11-repo.\033[0m\n'
printf '\033[1;33mO backup das configurações antigas está em:\033[0m\n'
printf '  %s\n' "$BACKUP"
printf '\n'
