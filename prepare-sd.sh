#!/usr/bin/env bash
# prepare-sd.sh
# Executa no PC Linux (com adaptador microSD e acesso à internet).
# Baixa os pacotes .deb necessários e os copia para o rootfs do microSD.
# Uso: sudo bash prepare-sd.sh <dispositivo>   ex: sudo bash prepare-sd.sh /dev/sdb

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ── verificar root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute com sudo: sudo bash $0 <dispositivo>"

# ── dispositivo ──────────────────────────────────────────────────────────────
DEVICE="${1:-}"
[[ -z "$DEVICE" ]] && error "Informe o dispositivo. Exemplo: sudo bash $0 /dev/sdb"
[[ ! -b "$DEVICE" ]] && error "Dispositivo não encontrado: $DEVICE"

# ── listar partições disponíveis ─────────────────────────────────────────────
info "Partições detectadas em $DEVICE:"
lsblk "$DEVICE"
echo ""

# Tenta identificar automaticamente partição root (tipo Linux, geralmente a 2ª)
ROOT_PART=$(lsblk -lno NAME,TYPE,FSTYPE "$DEVICE" | awk '$2=="part" && ($3=="ext4" || $3=="ext3") {print "/dev/"$1}' | head -1)
BOOT_PART=$(lsblk -lno NAME,TYPE,FSTYPE "$DEVICE" | awk '$2=="part" && $3=="vfat" {print "/dev/"$1}' | head -1)

[[ -z "$ROOT_PART" ]] && error "Partição root (ext4) não encontrada em $DEVICE. Verifique com lsblk."
info "Partição root detectada : $ROOT_PART"
[[ -n "$BOOT_PART" ]] && info "Partição boot detectada : $BOOT_PART"

# ── montar rootfs ────────────────────────────────────────────────────────────
MOUNT_POINT="/mnt/rpi"
mkdir -p "$MOUNT_POINT"

if mountpoint -q "$MOUNT_POINT"; then
    warn "$MOUNT_POINT já estava montado. Desmontando antes de remontar..."
    umount -R "$MOUNT_POINT" || true
fi

info "Montando $ROOT_PART em $MOUNT_POINT ..."
mount "$ROOT_PART" "$MOUNT_POINT"

if [[ -n "$BOOT_PART" ]]; then
    mkdir -p "$MOUNT_POINT/boot"
    mount "$BOOT_PART" "$MOUNT_POINT/boot" 2>/dev/null || warn "Não foi possível montar $BOOT_PART em /boot (pode já estar montado ou não ser necessário)."
fi

# ── baixar pacotes ───────────────────────────────────────────────────────────
PKGS_DIR="/tmp/rpi-offline-pkgs"
mkdir -p "$PKGS_DIR"
info "Baixando pacotes .deb em $PKGS_DIR ..."

PACKAGES=(
    firmware-brcm80211
    network-manager
    wpasupplicant
)

# apt download precisa rodar sem root para escrever no diretório atual
REAL_USER="${SUDO_USER:-$USER}"
sudo -u "$REAL_USER" bash -c "
    cd '$PKGS_DIR'
    apt-get download ${PACKAGES[*]} 2>&1
" || {
    warn "apt download falhou. Tentando com apt-get install --download-only ..."
    apt-get install --download-only -y "${PACKAGES[@]}" 2>&1 || true
    cp /var/cache/apt/archives/firmware-brcm80211*.deb \
       /var/cache/apt/archives/network-manager*.deb \
       /var/cache/apt/archives/wpasupplicant*.deb \
       "$PKGS_DIR/" 2>/dev/null || error "Não foi possível baixar os pacotes. Verifique a conexão com a internet e os repositórios configurados."
}

DEB_COUNT=$(ls "$PKGS_DIR"/*.deb 2>/dev/null | wc -l)
[[ $DEB_COUNT -eq 0 ]] && error "Nenhum .deb encontrado em $PKGS_DIR."
info "$DEB_COUNT pacote(s) .deb baixado(s)."

# ── copiar para o microSD ────────────────────────────────────────────────────
DEST="$MOUNT_POINT/root/rpi-wifi-pkgs"
mkdir -p "$DEST"
info "Copiando pacotes para $DEST ..."
cp "$PKGS_DIR"/*.deb "$DEST/"

# Copiar o script de instalação para facilitar
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/install-wifi.sh" "$DEST/" 2>/dev/null && \
    chmod +x "$DEST/install-wifi.sh" && \
    info "install-wifi.sh copiado para $DEST/" || \
    warn "install-wifi.sh não encontrado ao lado deste script — copie manualmente se quiser."

ls -lh "$DEST"

# ── desmontar ────────────────────────────────────────────────────────────────
info "Desmontando partições..."
umount -R "$MOUNT_POINT" || warn "Falha ao desmontar — verifique manualmente com: umount -R $MOUNT_POINT"

echo ""
info "Pronto! Pacotes copiados para o microSD."
echo -e "${GREEN}Próximo passo:${NC} coloque o SD no Raspberry Pi e execute:"
echo "    sudo bash /root/rpi-wifi-pkgs/install-wifi.sh"
