#!/usr/bin/env bash
# prepare-sd.sh
# Executa no PC Linux (com adaptador microSD e acesso à internet).
#
# Modos:
#   --boot   Copia para a partição FAT32 (/boot) → compatível com celular
#            (padrão quando bloqueio corporativo impede download direto no PC)
#   --root   Copia para a partição root (ext4) — requer PC Linux com acesso de escrita
#
# Uso:
#   sudo bash prepare-sd.sh /dev/sdb           (padrão: --root)
#   sudo bash prepare-sd.sh /dev/sdb --boot    (copia para FAT32/boot)

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── verificar root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute com sudo: sudo bash $0 <dispositivo> [--boot|--root]"

# ── argumentos ───────────────────────────────────────────────────────────────
DEVICE="${1:-}"
MODE="${2:---root}"

[[ -z "$DEVICE" ]]    && error "Informe o dispositivo. Exemplo: sudo bash $0 /dev/sdb [--boot|--root]"
[[ ! -b "$DEVICE" ]]  && error "Dispositivo não encontrado: $DEVICE"
[[ "$MODE" != "--boot" && "$MODE" != "--root" ]] && error "Modo inválido: $MODE. Use --boot ou --root."

info "Dispositivo : $DEVICE"
info "Modo        : $MODE"
echo ""

# ── listar partições ─────────────────────────────────────────────────────────
step "Partições detectadas em $DEVICE"
lsblk "$DEVICE"
echo ""

BOOT_PART=$(lsblk -lno NAME,TYPE,FSTYPE "$DEVICE" | awk '$2=="part" && $3=="vfat" {print "/dev/"$1}' | head -1)
ROOT_PART=$(lsblk -lno NAME,TYPE,FSTYPE "$DEVICE" | awk '$2=="part" && ($3=="ext4" || $3=="ext3") {print "/dev/"$1}' | head -1)

[[ -z "$BOOT_PART" ]] && error "Partição boot (FAT32/vfat) não encontrada em $DEVICE."
info "Partição boot detectada : $BOOT_PART"
[[ -n "$ROOT_PART" ]] && info "Partição root detectada : $ROOT_PART"

# ── montar partições ─────────────────────────────────────────────────────────
step "Montando partições"
MOUNT_BOOT="/mnt/rpi-boot"
MOUNT_ROOT="/mnt/rpi-root"

mkdir -p "$MOUNT_BOOT"
mountpoint -q "$MOUNT_BOOT" && umount "$MOUNT_BOOT" 2>/dev/null || true
mount "$BOOT_PART" "$MOUNT_BOOT"
info "Boot montado em $MOUNT_BOOT"

if [[ "$MODE" == "--root" ]]; then
    [[ -z "$ROOT_PART" ]] && error "Partição root (ext4) não encontrada. Use --boot para copiar para FAT32."
    mkdir -p "$MOUNT_ROOT"
    mountpoint -q "$MOUNT_ROOT" && umount "$MOUNT_ROOT" 2>/dev/null || true
    mount "$ROOT_PART" "$MOUNT_ROOT"
    info "Root montado em $MOUNT_ROOT"
fi

# ── baixar pacotes ───────────────────────────────────────────────────────────
step "Baixando pacotes .deb"
PKGS_DIR="/tmp/rpi-offline-pkgs"
mkdir -p "$PKGS_DIR"

PACKAGES=(firmware-brcm80211 network-manager wpasupplicant)
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
       "$PKGS_DIR/" 2>/dev/null || \
        error "Não foi possível baixar os pacotes. Verifique internet e repositórios."
}

DEB_COUNT=$(ls "$PKGS_DIR"/*.deb 2>/dev/null | wc -l)
[[ $DEB_COUNT -eq 0 ]] && error "Nenhum .deb encontrado em $PKGS_DIR."
info "$DEB_COUNT pacote(s) .deb baixado(s)."

# ── copiar para o SD ─────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ "$MODE" == "--boot" ]]; then
    step "Copiando para partição boot (FAT32) — compatível com celular"
    # Verificar espaço disponível (~8 MB necessários)
    AVAILABLE=$(df -m "$MOUNT_BOOT" | awk 'NR==2 {print $4}')
    info "Espaço disponível em boot: ${AVAILABLE} MB"
    [[ "$AVAILABLE" -lt 10 ]] && warn "Espaço baixo na partição boot (${AVAILABLE} MB). Pode não caber todos os pacotes."

    DEST="$MOUNT_BOOT/rpi-wifi-pkgs"
    mkdir -p "$DEST"
    cp "$PKGS_DIR"/*.deb "$DEST/"
    cp "$SCRIPT_DIR/install-wifi.sh" "$DEST/" 2>/dev/null || warn "install-wifi.sh não encontrado."
    [[ -f "$SCRIPT_DIR/wpa_supplicant.conf.template" ]] && \
        cp "$SCRIPT_DIR/wpa_supplicant.conf.template" "$DEST/" && \
        info "Template wpa_supplicant.conf copiado."
    ls -lh "$DEST"

    echo ""
    info "Pronto! Arquivos copiados para a partição BOOT (FAT32)."
    echo -e "${GREEN}Como finalizar no Raspberry Pi:${NC}"
    echo "    sudo bash /boot/rpi-wifi-pkgs/install-wifi.sh"
    echo ""
    echo -e "${CYAN}Esta pasta também pode ser preenchida diretamente pelo celular${NC}"
    echo -e "${CYAN}(veja DOWNLOAD_LINKS.md no repositório).${NC}"

else
    step "Copiando para partição root (ext4)"
    DEST="$MOUNT_ROOT/root/rpi-wifi-pkgs"
    mkdir -p "$DEST"
    cp "$PKGS_DIR"/*.deb "$DEST/"
    cp "$SCRIPT_DIR/install-wifi.sh" "$DEST/" 2>/dev/null || warn "install-wifi.sh não encontrado."
    [[ -f "$SCRIPT_DIR/wpa_supplicant.conf.template" ]] && \
        cp "$SCRIPT_DIR/wpa_supplicant.conf.template" "$DEST/"
    ls -lh "$DEST"

    echo ""
    info "Pronto! Arquivos copiados para a partição ROOT."
    echo -e "${GREEN}Como finalizar no Raspberry Pi:${NC}"
    echo "    sudo bash /root/rpi-wifi-pkgs/install-wifi.sh"
fi

# ── desmontar ────────────────────────────────────────────────────────────────
step "Desmontando partições"
umount "$MOUNT_BOOT" 2>/dev/null && info "$MOUNT_BOOT desmontado." || warn "Falha ao desmontar $MOUNT_BOOT"
[[ "$MODE" == "--root" && -n "$ROOT_PART" ]] && \
    umount "$MOUNT_ROOT" 2>/dev/null && info "$MOUNT_ROOT desmontado." || true

echo ""
info "SD pronto para uso."
