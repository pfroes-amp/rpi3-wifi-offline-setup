# rpi3-wifi-offline-setup

Prepara o microSD do **Raspberry Pi 3** com os pacotes necessários para ativar o Wi-Fi interno (`wlan0`) sem conexão de internet na placa.

Útil quando o Pi não tem Ethernet disponível e o Wi-Fi ainda não está funcionando — você usa um **adaptador microSD no seu PC Linux** para preparar tudo offline.

---

## O que este repositório faz

| Script | Onde roda | O que faz |
|--------|-----------|-----------|
| `prepare-sd.sh` | PC Linux (com adaptador microSD) | Monta o SD, baixa os `.deb` e os copia para o rootfs |
| `install-wifi.sh` | Raspberry Pi (após reinserção do SD) | Instala os pacotes, configura país BR e ativa o NetworkManager |

### Pacotes instalados
- `firmware-brcm80211` — firmware do chip Wi-Fi Broadcom presente no Pi 3
- `wpasupplicant` — autenticação WPA/WPA2
- `network-manager` — gerenciamento de rede (nmcli)

---

## Pré-requisitos

### No PC Linux
- Adaptador microSD conectado ao PC
- Acesso à internet (apenas para baixar os `.deb`)
- `apt` disponível (Debian/Ubuntu/Raspberry Pi OS Desktop)
- `sudo`

### No Raspberry Pi
- Raspberry Pi 3 (Model B ou B+)
- Raspberry Pi OS (Bullseye, Bookworm ou compatível)
- Acesso a um terminal (HDMI + teclado, ou serial)

---

## Uso

### Passo 1 — Clonar o repositório no PC

```bash
git clone https://github.com/pfroes-amp/rpi3-wifi-offline-setup.git
cd rpi3-wifi-offline-setup
```

### Passo 2 — Identificar o dispositivo microSD

Conecte o microSD via adaptador e rode:

```bash
lsblk
```

Exemplo de saída típica:

```
NAME   MAJ:MIN RM  SIZE RO TYPE MOUNTPOINT
sdb      8:16   1 29,7G  0 disk
├─sdb1   8:17   1  256M  0 part          ← boot (FAT32)
└─sdb2   8:18   1 29,4G  0 part          ← root (ext4)
```

> **Atenção:** certifique-se de usar o dispositivo correto (`/dev/sdb`, `/dev/sdc`, etc.).  
> Usar o dispositivo errado pode sobrescrever dados do seu PC.

### Passo 3 — Executar o script no PC

```bash
sudo bash prepare-sd.sh /dev/sdb
```

O script irá:
1. Detectar automaticamente as partições boot e root
2. Montar o rootfs em `/mnt/rpi`
3. Baixar `firmware-brcm80211`, `network-manager` e `wpasupplicant`
4. Copiar os `.deb` e o `install-wifi.sh` para `/root/rpi-wifi-pkgs/` no SD
5. Desmontar o SD com segurança

### Passo 4 — Inserir o SD no Raspberry Pi e ligar

Acesse o terminal do Pi (via HDMI+teclado ou serial/SSH por Ethernet).

### Passo 5 — Executar o script no Raspberry Pi

```bash
sudo bash /root/rpi-wifi-pkgs/install-wifi.sh
```

O script irá:
1. Instalar os pacotes `.deb` offline via `dpkg`
2. Configurar `country=BR` no wpa_supplicant e no domínio regulatório
3. Habilitar e reiniciar o NetworkManager
4. Recarregar o módulo `brcmfmac`
5. Exibir status das interfaces

### Passo 6 — Reiniciar e verificar

```bash
sudo reboot
```

Após reiniciar:

```bash
iw dev
nmcli dev status
ip link
```

`wlan0` deve aparecer. Para conectar a uma rede:

```bash
nmcli dev wifi list
nmcli dev wifi connect 'NOME_DA_REDE' password 'SENHA'
```

---

## Solução de problemas

### `wlan0` não aparece após reboot

Verifique se o firmware foi carregado:
```bash
dmesg | grep brcmfmac
lsmod | grep brcm
```

Tente recarregar o módulo:
```bash
sudo modprobe -r brcmfmac && sudo modprobe brcmfmac
```

### Conflito com `ifupdown`

Se `/etc/network/interfaces` tiver entradas para `wlan0`, elas podem conflitar com o NetworkManager. O `install-wifi.sh` já remove essas entradas automaticamente (com backup), mas você pode conferir:

```bash
cat /etc/network/interfaces
```

### `apt download` falha no PC

Se seu PC não tiver o repositório Raspberry Pi configurado, baixe os `.deb` manualmente de:
- https://packages.debian.org/firmware-brcm80211
- https://packages.debian.org/network-manager
- https://packages.debian.org/wpasupplicant

Coloque os arquivos `.deb` numa pasta e copie manualmente para `/root/rpi-wifi-pkgs/` no SD.

### Usar `raspi-config` manualmente

Se preferir configurar o país pelo menu interativo após instalar os pacotes:

```bash
sudo raspi-config
# Localisation Options → WLAN Country → BR
```

---

## Estrutura do repositório

```
rpi3-wifi-offline-setup/
├── prepare-sd.sh      # Roda no PC Linux — monta SD, baixa e copia pacotes
├── install-wifi.sh    # Roda no Raspberry Pi — instala e configura Wi-Fi
└── README.md          # Este arquivo
```

---

## Compatibilidade testada

| Sistema | Status |
|---------|--------|
| Raspberry Pi OS Bookworm (12) | ✓ |
| Raspberry Pi OS Bullseye (11) | ✓ |
| Raspberry Pi 3 Model B | ✓ |
| Raspberry Pi 3 Model B+ | ✓ |

---

## Licença

MIT — use livremente.
