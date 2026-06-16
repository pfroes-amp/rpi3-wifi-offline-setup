# Links de Download — Pacotes para Raspberry Pi 3 Wi-Fi

Use esta página no **celular** para baixar os arquivos `.deb` e copiá-los para a partição `/boot` do microSD (FAT32 — legível por qualquer celular).

---

## Arquitetura do Raspberry Pi 3

| Modelo | Arquitetura | OS alvo |
|--------|-------------|---------|
| Pi 3 Model B | **armhf** (32-bit ARM) | Raspberry Pi OS Bookworm/Bullseye |
| Pi 3 Model B+ | **armhf** (32-bit ARM) | Raspberry Pi OS Bookworm/Bullseye |

---

## Pacotes para baixar

### 1. firmware-brcm80211 (firmware do chip Wi-Fi)
> Arquivo único — funciona em qualquer arquitetura (`_all.deb`)

**[⬇ Baixar firmware-brcm80211 (5,1 MB)](https://ftp.debian.org/debian/pool/non-free-firmware/f/firmware-nonfree/firmware-brcm80211_20250410-2_all.deb)**

Fonte alternativa (build específico para Raspberry Pi):

**[⬇ Baixar firmware-brcm80211 RPi build (5,1 MB)](https://archive.raspberrypi.org/debian/pool/main/f/firmware-nonfree/firmware-brcm80211_20240709-2~bpo12+1+rpt3_all.deb)**

---

### 2. wpasupplicant (autenticação WPA/WPA2) — somente armhf

**[⬇ Baixar wpasupplicant armhf (1,2 MB)](http://ftp.debian.org/debian/pool/main/w/wpa/wpasupplicant_2.10-12+deb12u3_armhf.deb)**

---

### 3. network-manager (gerenciamento de rede)
> O network-manager tem muitas dependências — em muitos casos já está instalado no Raspberry Pi OS.
> Baixe apenas se necessário.

Acesse a página abaixo e clique no link `armhf` para baixar:

**[→ packages.debian.org/bookworm/network-manager](https://packages.debian.org/bookworm/armhf/network-manager/download)**

---

### 4. Script de instalação (install-wifi.sh)

Baixe diretamente do repositório:

**[⬇ Baixar install-wifi.sh](https://raw.githubusercontent.com/pfroes-amp/rpi3-wifi-offline-setup/main/install-wifi.sh)**

---

## O que fazer depois de baixar

1. Coloque o microSD no celular (slot ou adaptador OTG)
2. Abra o gerenciador de arquivos do celular
3. Navegue até a partição **`boot`** do microSD (a menor, geralmente ~256 MB, formato FAT32)
4. Crie uma pasta chamada **`rpi-wifi-pkgs`** dentro de `/boot`
5. Copie todos os arquivos `.deb` baixados e o `install-wifi.sh` para essa pasta
6. Ejete o SD com segurança e insira no Raspberry Pi
7. No terminal do Pi:

```bash
sudo bash /boot/rpi-wifi-pkgs/install-wifi.sh
```

---

## Verificação rápida de arquitetura no Pi

Se tiver dúvida sobre qual arquitetura está rodando, execute no Pi:

```bash
uname -m
# armv7l  → use armhf
# aarch64 → use arm64
```

---

## Tamanho total dos downloads

| Arquivo | Tamanho |
|---------|---------|
| firmware-brcm80211 | ~5,1 MB |
| wpasupplicant | ~1,2 MB |
| network-manager | ~1,5 MB |
| install-wifi.sh | < 5 KB |
| **Total** | **~8 MB** |
