#!/usr/bin/env bash
# install-wifi.sh
# Executa NO Raspberry Pi (após colocar o microSD de volta e ligar a placa).
# Instala os pacotes .deb copiados e configura o Wi-Fi para o país BR.
#
# Uso (fluxo celular — pacotes em /boot/rpi-wifi-pkgs/):
#   sudo bash /boot/rpi-wifi-pkgs/install-wifi.sh
#
# Uso (fluxo PC — pacotes no mesmo diretório do script):
#   sudo bash /root/rpi-wifi-pkgs/install-wifi.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── verificar root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute com sudo: sudo bash $0"

# ── localizar pacotes ────────────────────────────────────────────────────────
# Procura em ordem: diretório do script, /boot/rpi-wifi-pkgs, /boot
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SEARCH_DIRS=(
    "$SCRIPT_DIR"
    "/boot/rpi-wifi-pkgs"
    "/boot"
)

PKGS_DIR=""
for dir in "${SEARCH_DIRS[@]}"; do
    if ls "$dir"/*.deb &>/dev/null 2>&1; then
        PKGS_DIR="$dir"
        break
    fi
done

if [[ -z "$PKGS_DIR" ]]; then
    echo ""
    error "Nenhum arquivo .deb encontrado. Verifique se copiou os pacotes para o microSD.
Locais verificados:
$(printf '  - %s\n' "${SEARCH_DIRS[@]}")

Acesse https://github.com/pfroes-amp/rpi3-wifi-offline-setup/blob/main/DOWNLOAD_LINKS.md
para baixar os pacotes pelo celular."
fi

step "Pacotes encontrados em: $PKGS_DIR"
ls -lh "$PKGS_DIR"/*.deb

# ── mostrar arquitetura atual ────────────────────────────────────────────────
ARCH=$(uname -m)
info "Arquitetura do sistema: $ARCH"
[[ "$ARCH" == "armv7l" ]] && info "Tipo esperado de pacotes: armhf"
[[ "$ARCH" == "aarch64" ]] && info "Tipo esperado de pacotes: arm64"

# ── limpar gerenciadores conflitantes ────────────────────────────────────────
step "Limpando configurações antigas de rede"

IFACES_FILE="/etc/network/interfaces"
if grep -q "wlan0" "$IFACES_FILE" 2>/dev/null; then
    warn "Encontrado wlan0 em $IFACES_FILE — fazendo backup e removendo para evitar conflito com NetworkManager."
    cp "$IFACES_FILE" "${IFACES_FILE}.bak-$(date +%Y%m%d%H%M%S)"
    sed -i '/wlan0/,/^$/d' "$IFACES_FILE"
    info "Backup salvo em ${IFACES_FILE}.bak-*"
fi

systemctl stop ifupdown 2>/dev/null || true

# ── instalar pacotes ─────────────────────────────────────────────────────────
step "Instalando pacotes .deb offline"

# Instala em ordem de dependência: firmware → wpa → network-manager
ORDER=(
    firmware-brcm80211
    wpasupplicant
    network-manager
)

INSTALLED=0
for pkg in "${ORDER[@]}"; do
    found=$(ls "$PKGS_DIR/${pkg}"*.deb 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
        info "Instalando: $(basename "$found")"
        dpkg -i "$found" && INSTALLED=$((INSTALLED + 1)) || {
            warn "dpkg reportou erro em $pkg — tentando corrigir dependências..."
            apt-get install -f -y 2>/dev/null || true
        }
    else
        warn "Pacote $pkg não encontrado em $PKGS_DIR — pulando."
    fi
done

[[ $INSTALLED -eq 0 ]] && warn "Nenhum pacote foi instalado. Verifique os nomes dos arquivos .deb."

# ── configurar país do Wi-Fi ─────────────────────────────────────────────────
step "Configurando país Wi-Fi para BR"

# Método 1: wpa_supplicant.conf
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
WPA_BOOT="/boot/rpi-wifi-pkgs/wpa_supplicant.conf.template"
WPA_BOOT2="/boot/wpa_supplicant.conf"

# Detecta se há um template de wpa_supplicant no /boot (colocado pelo celular)
if [[ -f "$WPA_BOOT2" ]]; then
    info "wpa_supplicant.conf encontrado em /boot — aplicando..."
    cp "$WPA_BOOT2" "$WPA_CONF"
    info "Copiado para $WPA_CONF"
elif [[ -f "$WPA_BOOT" ]]; then
    info "Template wpa_supplicant.conf encontrado — aplicando..."
    cp "$WPA_BOOT" "$WPA_CONF"
    info "Copiado para $WPA_CONF"
elif [[ -f "$WPA_CONF" ]]; then
    if grep -q "country=" "$WPA_CONF"; then
        sed -i 's/^country=.*/country=BR/' "$WPA_CONF"
    else
        sed -i '1s/^/country=BR\n/' "$WPA_CONF"
    fi
    info "country=BR definido em $WPA_CONF"
else
    mkdir -p "$(dirname "$WPA_CONF")"
    cat > "$WPA_CONF" <<'EOF'
country=BR
ctrl_interface=DIR=/var/run/wpa_supplicant GROUP=netdev
update_config=1
EOF
    info "$WPA_CONF criado com country=BR"
fi

# Método 2: /etc/default/crda (domínio regulatório)
CRDA_FILE="/etc/default/crda"
if [[ -f "$CRDA_FILE" ]]; then
    sed -i 's/^REGDOMAIN=.*/REGDOMAIN=BR/' "$CRDA_FILE"
    info "REGDOMAIN=BR definido em $CRDA_FILE"
fi

# Método 3: raspi-config não-interativo
if command -v raspi-config &>/dev/null; then
    raspi-config nonint do_wifi_country BR 2>/dev/null && \
        info "WLAN Country configurado via raspi-config." || \
        warn "raspi-config retornou erro (não crítico)."
fi

# ── ativar NetworkManager ────────────────────────────────────────────────────
step "Ativando NetworkManager"
if systemctl list-unit-files | grep -q "NetworkManager.service"; then
    systemctl enable NetworkManager 2>/dev/null && \
        info "NetworkManager habilitado no boot." || \
        warn "systemctl enable falhou."
    systemctl restart NetworkManager 2>/dev/null && \
        info "NetworkManager reiniciado." || \
        warn "NetworkManager não reiniciou — verifique com: journalctl -u NetworkManager -n 50"
else
    warn "NetworkManager não encontrado — pode ser necessário instalar o pacote network-manager."
fi

# ── recarregar firmware ──────────────────────────────────────────────────────
step "Recarregando módulo brcmfmac"
modprobe -r brcmfmac 2>/dev/null || true
sleep 1
modprobe brcmfmac 2>/dev/null && info "brcmfmac carregado." || \
    warn "modprobe brcmfmac falhou — será carregado no próximo boot."

# Desbloquear rfkill se Wi-Fi estiver bloqueado por software
if command -v rfkill &>/dev/null; then
    rfkill unblock wifi 2>/dev/null && info "rfkill: Wi-Fi desbloqueado." || true
fi

# ── verificação rápida ───────────────────────────────────────────────────────
step "Verificação de interfaces"
sleep 2

echo ""
info "=== iw dev ==="
iw dev 2>/dev/null || echo "(iw não disponível ou nenhum dispositivo Wi-Fi detectado ainda)"

echo ""
info "=== ip link (interfaces) ==="
ip link show 2>/dev/null || true

echo ""
info "=== rfkill list ==="
rfkill list 2>/dev/null || echo "(rfkill não disponível)"

echo ""
info "=== nmcli dev status ==="
nmcli dev status 2>/dev/null || echo "(nmcli não disponível ainda — reinicie e tente novamente)"

echo ""
if ip link show wlan0 &>/dev/null; then
    echo -e "${GREEN}[SUCESSO]${NC} wlan0 detectado!"
    echo ""
    echo -e "${CYAN}Para conectar ao Wi-Fi após o reboot:${NC}"
    echo "    nmcli dev wifi list"
    echo "    nmcli dev wifi connect 'NOME_DA_REDE' password 'SENHA'"
else
    warn "wlan0 ainda não aparece. Reinicie o Raspberry Pi com:"
    echo "    sudo reboot"
    echo ""
    warn "Após reiniciar, execute para verificar:"
    echo "    iw dev"
    echo "    nmcli dev status"
    echo "    dmesg | grep brcmfmac"
fi

echo ""
echo -e "${CYAN}Próximo passo:${NC} sudo reboot"
