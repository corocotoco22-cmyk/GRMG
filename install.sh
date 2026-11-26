#!/usr/bin/env bash
set -e

UNSUPPORTED_MSG="Ops, esse sistema não é suportado, infelizmente."

fail_unsupported() {
    echo "$UNSUPPORTED_MSG" >&2
    exit 1
}

if [ ! -r /etc/os-release ]; then
    fail_unsupported
fi

OS_ID=""
OS_LIKE=""
while IFS='=' read -r key val; do
    val="${val%\"}"
    val="${val#\"}"
    val="${val%\'}"
    val="${val#\'}"
    case "$key" in
        ID) OS_ID="$val" ;;
        ID_LIKE) OS_LIKE="$val" ;;
    esac
done < /etc/os-release

# Pacotes necessários (incluindo curl para baixar junto com os demais)
ARCH_PKGS=("base-devel" "git" "curl")
DEBIAN_PKGS=("build-essential" "git" "curl")
FEDORA_PKGS=("@development-tools" "git" "curl")

detect_family() {
    case " $OS_ID $OS_LIKE " in
        *" arch "*|*" manjaro "*|*" endeavour"*|*" garuda "*)
            echo "arch"
            ;;
        *" debian "*|*" ubuntu "*|*" linuxmint "*|*" pop "*)
            echo "debian"
            ;;
        *" fedora "*)
            echo "fedora"
            ;;
        *)
            echo "unknown"
            ;;
    esac
}

FAMILY="$(detect_family)"

case "$FAMILY" in
    arch)
        command -v pacman >/dev/null 2>&1 || fail_unsupported
        ;;
    debian)
        command -v apt-get >/dev/null 2>&1 || fail_unsupported
        ;;
    fedora)
        command -v dnf >/dev/null 2>&1 || fail_unsupported
        ;;
    *)
        fail_unsupported
        ;;
esac

echo "Sistema detectado: $FAMILY ($OS_ID)."
printf "Posso instalar ou atualizar os pacotes necessários agora? [s/N]: "
read -r resposta

case "$resposta" in
    [sS]|[sS][iI][mM])
        ;;
    *)
        echo "Operação cancelada pelo usuário."
        exit 0
        ;;
esac

case "$FAMILY" in
    arch)
        sudo pacman -Syu --needed --noconfirm "${ARCH_PKGS[@]}"
        ;;
    debian)
        sudo apt-get update -y
        sudo apt-get upgrade -y
        sudo apt-get install -y "${DEBIAN_PKGS[@]}"
        ;;
    fedora)
        sudo dnf upgrade -y
        sudo dnf install -y "${FEDORA_PKGS[@]}"
        ;;
esac

# --- BAIXAR COM CURL, DAR CHMOD E EXECUTAR ---
SCRIPT_URL="https://exemplo.com/seu-script.sh"
TARGET_SCRIPT="$HOME/seu-script.sh"

echo "Baixando script com curl..."
curl -fsSL "$SCRIPT_URL" -o "$TARGET_SCRIPT"

echo "Aplicando permissão de execução (chmod)..."
chmod +x "$TARGET_SCRIPT"

echo "Executando o script..."
"$TARGET_SCRIPT"

echo "Processo concluído!"
