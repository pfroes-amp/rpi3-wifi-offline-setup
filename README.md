# rpi3-wifi-offline-setup

Ativa o Wi-Fi interno (`wlan0`) do **Raspberry Pi 3** sem precisar de internet na placa — usando apenas um **celular** como intermediário.

---

## Como funciona

O microSD do Raspberry Pi tem **duas partições**:

| Partição | Formato | Acessível por |
|----------|---------|---------------|
| `/boot` (~256 MB) | **FAT32** | Celular, Windows, Mac, Linux |
| root (~resto) | ext4 | Somente Linux |

A estratégia é colocar os pacotes `.deb` na partição **boot (FAT32)**, que qualquer celular consegue ler e escrever, e depois instalá-los diretamente do Raspberry Pi.

---

## Fluxo via Celular (sem PC corporativo)

> Use este fluxo quando você não tem acesso ao PC ou ele está bloqueado por políticas corporativas.

### Passo 1 — Baixar os arquivos no celular

Acesse o arquivo **[DOWNLOAD_LINKS.md](./DOWNLOAD_LINKS.md)** pelo celular e baixe:

- `firmware-brcm80211_*.deb` (~5 MB) — firmware do chip Wi-Fi
- `wpasupplicant_*_armhf.deb` (~1,2 MB) — autenticação WPA
- `install-wifi.sh` — script de instalação

> Os links de download estão na página [DOWNLOAD_LINKS.md](./DOWNLOAD_LINKS.md).

### Passo 2 — Copiar para o microSD

1. Insira o microSD no celular (slot ou adaptador OTG/USB-C)
2. Abra o **gerenciador de arquivos** do celular
3. Localize o volume **`boot`** (a partição menor, ~256 MB)
4. Crie uma pasta chamada `rpi-wifi-pkgs` dentro do `boot`
5. Copie os arquivos `.deb` e o `install-wifi.sh` para essa pasta

A estrutura deve ficar assim:

```
boot/
└── rpi-wifi-pkgs/
    ├── firmware-brcm80211_*.deb
    ├── wpasupplicant_*_armhf.deb
    ├── network-manager_*_armhf.deb   (opcional)
    └── install-wifi.sh
```

### Passo 3 — Inserir o SD no Raspberry Pi e ligar

Acesse o terminal do Pi via HDMI + teclado ou serial.

### Passo 4 — Executar o script de instalação

```bash
sudo bash /boot/rpi-wifi-pkgs/install-wifi.sh
```

O script irá:
- Encontrar automaticamente os pacotes em `/boot/rpi-wifi-pkgs/`
- Instalar via `dpkg`
- Configurar `country=BR`
- Habilitar e reiniciar o NetworkManager
- Desbloquear rfkill
- Exibir o status das interfaces

### Passo 5 — Reiniciar e verificar

```bash
sudo reboot
```

Após reiniciar:

```bash
iw dev
nmcli dev status
```

`wlan0` deve aparecer. Para conectar:

```bash
nmcli dev wifi list
nmcli dev wifi connect 'NOME_DA_REDE' password 'SENHA'
```

---

## Fluxo via PC Linux (com adaptador microSD)

> Use este fluxo quando tiver acesso a um PC Linux com internet e um adaptador microSD.

### Passo 1 — Clonar o repositório

```bash
git clone https://github.com/pfroes-amp/rpi3-wifi-offline-setup.git
cd rpi3-wifi-offline-setup
```

### Passo 2 — Identificar o dispositivo

```bash
lsblk
# Exemplo: /dev/sdb com sdb1 (FAT32/boot) e sdb2 (ext4/root)
```

> **Atenção:** certifique-se do dispositivo correto antes de executar.

### Passo 3a — Copiar para a partição boot (recomendado — sem necessidade de root ext4)

```bash
sudo bash prepare-sd.sh /dev/sdb --boot
```

### Passo 3b — Copiar para a partição root (alternativa, requer Linux)

```bash
sudo bash prepare-sd.sh /dev/sdb --root
```

### Passo 4 — Instalar no Pi

No Raspberry Pi:

```bash
# Se usou --boot:
sudo bash /boot/rpi-wifi-pkgs/install-wifi.sh

# Se usou --root:
sudo bash /root/rpi-wifi-pkgs/install-wifi.sh
```

---

## Arquivos do repositório

```
rpi3-wifi-offline-setup/
├── DOWNLOAD_LINKS.md             ← Links diretos para baixar pelo celular
├── install-wifi.sh               ← Roda no Raspberry Pi — instala e configura
├── prepare-sd.sh                 ← Roda no PC Linux — baixa e copia pacotes
├── wpa_supplicant.conf.template  ← Template de configuração Wi-Fi (opcional)
└── README.md
```

---

## Solução de problemas

### `wlan0` não aparece após reboot

```bash
dmesg | grep brcmfmac          # firmware carregou?
lsmod | grep brcm              # módulo está ativo?
rfkill list                    # interface está bloqueada por rfkill?
sudo rfkill unblock wifi       # desbloquear se necessário
```

### Interface bloqueada (rfkill: yes)

Geralmente indica que o país WLAN não foi configurado:

```bash
sudo raspi-config
# Localisation Options → WLAN Country → BR
sudo reboot
```

### Conflito com `ifupdown` / `dhcpcd`

Se o sistema usar `dhcpcd` junto com NetworkManager:

```bash
# Ver qual gerenciador está ativo:
systemctl status NetworkManager dhcpcd

# Desativar dhcpcd se quiser usar só NetworkManager:
sudo systemctl disable dhcpcd
sudo systemctl stop dhcpcd
sudo systemctl restart NetworkManager
```

### Espaço insuficiente na partição boot

A partição `/boot` tem ~256 MB. Os pacotes ocupam ~8 MB no total — deve sobrar espaço.

Se necessário, libere espaço removendo arquivos antigos de kernel de `/boot` antes de copiar:

```bash
ls -lh /boot/*.deb 2>/dev/null   # ver se já há .deb antigos para remover
```

### Baixar apenas o firmware (solução mínima)

Se `wpa_supplicant` e `network-manager` já estiverem instalados, pode ser suficiente apenas o firmware:

```bash
sudo dpkg -i /boot/rpi-wifi-pkgs/firmware-brcm80211_*.deb
sudo raspi-config nonint do_wifi_country BR
sudo reboot
```

---

## Compatibilidade

| Sistema | Status |
|---------|--------|
| Raspberry Pi OS Bookworm (12) | ✓ |
| Raspberry Pi OS Bullseye (11) | ✓ |
| Raspberry Pi 3 Model B | ✓ |
| Raspberry Pi 3 Model B+ | ✓ |

---

## Licença

MIT — use livremente.
