#!/usr/bin/env bash
# install-wifi.sh
# Executa NO Raspberry Pi (após colocar o microSD de volta e ligar a placa).
# Instala os pacotes .deb copiados pelo prepare-sd.sh e configura o Wi-Fi BR.
# Uso: sudo bash /root/rpi-wifi-pkgs/install-wifi.sh

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }
step()  { echo -e "\n${CYAN}══ $* ══${NC}"; }

# ── verificar root ───────────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && error "Execute com sudo: sudo bash $0"

# ── localizar pacotes ────────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGS=("$SCRIPT_DIR"/*.deb)

[[ ${#PKGS[@]} -eq 0 || ! -f "${PKGS[0]}" ]] && \
    error "Nenhum .deb encontrado em $SCRIPT_DIR. Execute primeiro o prepare-sd.sh no PC."

step "Pacotes encontrados"
ls -lh "$SCRIPT_DIR"/*.deb

# ── limpar gerenciadores conflitantes ────────────────────────────────────────
step "Limpando configurações antigas de rede"

# Remover entradas estáticas em /etc/network/interfaces que possam bloquear wlan0
IFACES_FILE="/etc/network/interfaces"
if grep -q "wlan0" "$IFACES_FILE" 2>/dev/null; then
    warn "Encontrado wlan0 em $IFACES_FILE — fazendo backup e removendo para evitar conflito com NetworkManager."
    cp "$IFACES_FILE" "${IFACES_FILE}.bak-$(date +%Y%m%d%H%M%S)"
    sed -i '/wlan0/,/^$/d' "$IFACES_FILE"
    info "Backup salvo em ${IFACES_FILE}.bak-*"
fi

# Desativar ifupdown para wlan se ainda estiver rodando
systemctl stop ifupdown 2>/dev/null || true

# ── instalar pacotes ─────────────────────────────────────────────────────────
step "Instalando pacotes .deb offline"

# Ordem importa: firmware antes dos gerenciadores
ORDER=(
    firmware-brcm80211
    wpasupplicant
    network-manager
)

for pkg in "${ORDER[@]}"; do
    found=$(ls "$SCRIPT_DIR/${pkg}"*.deb 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
        info "Instalando: $(basename "$found")"
        dpkg -i "$found" || {
            warn "dpkg reportou erro em $pkg — tentando corrigir dependências..."
            apt-get install -f -y 2>/dev/null || true
        }
    else
        warn "Pacote $pkg não encontrado — pulando."
    fi
done

# ── configurar país do Wi-Fi ─────────────────────────────────────────────────
step "Configurando país Wi-Fi para BR"

# Método 1: wpa_supplicant.conf
WPA_CONF="/etc/wpa_supplicant/wpa_supplicant.conf"
if [[ -f "$WPA_CONF" ]]; then
    if grep -q "country=" "$WPA_CONF"; then
        sed -i 's/^country=.*/country=BR/' "$WPA_CONF"
    else
        echo "country=BR" >> "$WPA_CONF"
    fi
    info "country=BR definido em $WPA_CONF"
fi

# Método 2: /etc/default/crda (regulatório)
CRDA_FILE="/etc/default/crda"
if [[ -f "$CRDA_FILE" ]]; then
    sed -i 's/^REGDOMAIN=.*/REGDOMAIN=BR/' "$CRDA_FILE"
    info "REGDOMAIN=BR definido em $CRDA_FILE"
fi

# Método 3: raspi-config não-interativo (disponível no Raspberry Pi OS)
if command -v raspi-config &>/dev/null; then
    raspi-config nonint do_wifi_country BR 2>/dev/null && \
        info "WLAN Country configurado via raspi-config." || \
        warn "raspi-config retornou erro (não crítico)."
fi

# ── ativar NetworkManager ────────────────────────────────────────────────────
step "Ativando NetworkManager"
systemctl enable NetworkManager 2>/dev/null && \
    info "NetworkManager habilitado no boot." || \
    warn "systemctl enable falhou — verifique manualmente."

systemctl restart NetworkManager 2>/dev/null && \
    info "NetworkManager reiniciado." || \
    warn "NetworkManager não reiniciou — verifique com: journalctl -u NetworkManager -n 50"

# ── carregar firmware manualmente ────────────────────────────────────────────
step "Recarregando módulo brcmfmac"
modprobe -r brcmfmac 2>/dev/null || true
sleep 1
modprobe brcmfmac 2>/dev/null && info "brcmfmac carregado." || warn "modprobe brcmfmac falhou — pode ser carregado no próximo boot."

# ── verificação rápida ───────────────────────────────────────────────────────
step "Verificação de interfaces"
sleep 2

echo ""
info "=== iw dev ==="
iw dev 2>/dev/null || echo "(iw não disponível ou nenhum dispositivo Wi-Fi)"

echo ""
info "=== ip link (interfaces) ==="
ip link show 2>/dev/null || true

echo ""
info "=== nmcli dev status (se NetworkManager estiver rodando) ==="
nmcli dev status 2>/dev/null || echo "(nmcli não disponível ainda — reinicie e tente novamente)"

echo ""
if ip link show wlan0 &>/dev/null; then
    echo -e "${GREEN}[SUCESSO]${NC} wlan0 detectado!"
else
    warn "wlan0 ainda não aparece. Reinicie o Raspberry Pi com: sudo reboot"
    warn "Após reiniciar, execute: iw dev  e  nmcli dev status"
fi

echo ""
echo -e "${CYAN}Próximo passo recomendado:${NC}"
echo "    sudo reboot"
echo ""
echo "Após reiniciar, para conectar ao Wi-Fi:"
echo "    nmcli dev wifi list"
echo "    nmcli dev wifi connect 'NOME_DA_REDE' password 'SENHA'"
