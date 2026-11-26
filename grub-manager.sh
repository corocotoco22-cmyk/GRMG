#!/usr/bin/env bash
set -e

on_interrupt() {
clear
echo ""
echo "Operacao cancelada pelo usuario (Ctrl + C)."
exit 130
}
trap 'on_interrupt' INT TERM

GRUB_DEFAULT_FILE="/etc/default/grub"
GRUB_MAIS_FILE="/etc/default/grub-mais"
GRUB_MAIS_ITENS_FILE="/etc/default/grub-mais-itens.conf"
GRUB_42_MAIS_FILE="/etc/grub.d/42_mais"
GRUB_CFG_FILE="/boot/grub/grub.cfg"
THEMES_DIR="/boot/grub/themes"

require_whiptail() {
if ! command -v whiptail >/dev/null 2>&1; then
    echo "Erro: 'whiptail' nao encontrado. Instale com: sudo pacman -S libnewt"
    exit 1
fi
}

pick_editor() {
if command -v nvim >/dev/null 2>&1; then
    echo "nvim"
elif command -v nano >/dev/null 2>&1; then
    echo "nano"
elif command -v vim >/dev/null 2>&1; then
    echo "vim"
else
    echo "vi"
fi
}

show_tips_before_edit() {
local target="$1"
local editor_bin="$2"
local tips=""

case "$editor_bin" in
    nvim|vim)
        tips="DICAS RAPIDAS PARA VIM / NEOVIM:\n\n- Pressione 'i' para entrar no modo de insercao e digitar.\n- Pressione 'Esc' para voltar ao modo normal.\n- Digite ':wq' e Enter para salvar e sair.\n- Digite ':q!' e Enter para sair SEM salvar (no aviso de swap, use 'x' para excluir)."
        ;;
    nano)
        tips="DICAS RAPIDAS PARA NANO:\n\n- Digite normalmente para editar o texto.\n- Ctrl + O e Enter para salvar as alteracoes.\n- Ctrl + X para sair do editor."
        ;;
    *)
        tips="DICAS RAPIDAS DO EDITOR ($editor_bin):\n\n- Confira as aspas antes de sair.\n- Salve o arquivo antes de regenerar o grub.cfg."
        ;;
esac

whiptail --title "Dicas antes de editar: $target" \
    --msgbox "Arquivo alvo: $target\nEditor selecionado: $editor_bin\n\n$tips\n\nAo fechar este aviso, o editor sera aberto." \
    18 76
}

seed_empty_file() {
local target="$1"
if [ "$target" = "$GRUB_MAIS_ITENS_FILE" ]; then
    printf '%s\n' \
        "Reiniciar | reboot" \
        "Desligar | halt" \
        "Ignorar GRUB (proximo boot) | exit" \
        "" \
        ":: Energia e Boot" \
        "Reiniciar agora | reboot" \
        "Desligar agora | halt" \
        ":: Opcoes Avancadas" \
        "Linha de comando | commandline" \
        "Recarregar GRUB | configfile /boot/grub/grub.cfg" \
        "::end" \
        "::end" | sudo tee "$target" >/dev/null
elif [ "$target" = "$GRUB_MAIS_FILE" ]; then
    printf '%s\n' \
        'SUBMENU_TITULO="Mais"' \
        'OP1_TITULO="Reiniciar"' \
        'OP1_CMD="reboot"' \
        'OP2_TITULO="Desligar"' \
        'OP2_CMD="halt"' \
        'OP3_TITULO="Ignorar GRUB (proximo boot)"' \
        'OP3_CMD="exit"' | sudo tee "$target" >/dev/null
elif [ "$target" = "$GRUB_DEFAULT_FILE" ]; then
    printf '%s\n' \
        "GRUB_DEFAULT=0" \
        "GRUB_TIMEOUT=5" \
        'GRUB_DISTRIBUTOR="Arch"' \
        'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' \
        'GRUB_CMDLINE_LINUX=""' | sudo tee "$target" >/dev/null
fi
}

edit_with_tips() {
local target="$1"
local editor_bin
local backup_file
local hash_before
local hash_after
local ed_rc=0

editor_bin="$(pick_editor)"
sudo mkdir -p "$(dirname "$target")"
if [ ! -s "$target" ]; then
    seed_empty_file "$target"
fi

backup_file="${target}.bak.$(date +%Y%m%d-%H%M%S)"
sudo cp "$target" "$backup_file"
hash_before="$(sudo sha256sum "$target" | awk '{print $1}')"

while true; do
    show_tips_before_edit "$target" "$editor_bin"
    clear
    ed_rc=0
    sudo "$editor_bin" "$target" || ed_rc=$?

    if [ "$ed_rc" -eq 130 ]; then
        on_interrupt
    fi

    hash_after="$(sudo sha256sum "$target" | awk '{print $1}')"

    if [ "$hash_before" = "$hash_after" ]; then
        if whiptail --title "Nenhuma alteracao detectada" \
            --yesno "Nenhuma alteracao foi salva em:\n$target\n\nDeseja reabrir o editor ($editor_bin)?" \
            12 72; then
            continue
        else
            sudo rm -f "$backup_file"
            return 0
        fi
    else
        whiptail --title "Alteracoes salvas" \
            --msgbox "Alteracoes detectadas e mantidas em:\n$target\n\nBackup criado em:\n$backup_file" \
            12 72 || true
        return 0
    fi
done
}

write_42_mais() {
local mode="$1"
local titulo="Mais"
local op1_t="Reiniciar"
local op1_c="reboot"
local op2_t="Desligar"
local op2_c="halt"
local op3_t="Ignorar GRUB (proximo boot)"
local op3_c="exit"

if [ -f "$GRUB_MAIS_FILE" ]; then
    # shellcheck disable=SC1090
    . "$GRUB_MAIS_FILE" 2>/dev/null || true
    titulo="${SUBMENU_TITULO:-Mais}"
    op1_t="${OP1_TITULO:-Reiniciar}"
    op1_c="${OP1_CMD:-reboot}"
    op2_t="${OP2_TITULO:-Desligar}"
    op2_c="${OP2_CMD:-halt}"
    op3_t="${OP3_TITULO:-Ignorar GRUB (proximo boot)}"
    op3_c="${OP3_CMD:-exit}"
fi

cat << EOF | sudo tee "$GRUB_42_MAIS_FILE" >/dev/null
#!/bin/sh
set -e

TITULO_SUBMENU="$titulo"
LISTA_ARQUIVO="$GRUB_MAIS_ITENS_FILE"
MODO_GERACAO="$mode"
PROFUNDIDADE=1

printf 'submenu "%s" {\n' "\$TITULO_SUBMENU"

if [ "\$MODO_GERACAO" != "fixo" ] && [ -s "\$LISTA_ARQUIVO" ]; then
while IFS= read -r linha || [ -n "\$linha" ]; do
    limpa=\$(printf '%s' "\$linha" | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')

    case "\$limpa" in
        ""|\#*) continue ;;
    esac

    if [ "\$limpa" = "::end" ]; then
        if [ "\$PROFUNDIDADE" -gt 1 ]; then
            PROFUNDIDADE=\$((PROFUNDIDADE - 1))
            pad=\$(printf '%*s' \$((PROFUNDIDADE * 4)) '')
            printf '%s}\n' "\$pad"
        fi
        continue
    fi

    case "\$limpa" in
        "::"*)
            sub_titulo=\$(printf '%s' "\$limpa" | sed 's/^::[[:space:]]*//')
            [ -n "\$sub_titulo" ] || continue
            pad=\$(printf '%*s' \$((PROFUNDIDADE * 4)) '')
            printf '%ssubmenu "%s" {\n' "\$pad" "\$sub_titulo"
            PROFUNDIDADE=\$((PROFUNDIDADE + 1))
            continue
            ;;
    esac

    titulo_item=\$(printf '%s' "\$limpa" | awk -F'|' '{print \$1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')
    cmd_item=\$(printf '%s' "\$limpa" | awk -F'|' '{\$1=""; sub(/^[[:space:]]*\\|[[:space:]]*/, ""); print \$0}' | sed 's/^[[:space:]]*//;s/[[:space:]]*\$//')

    [ -n "\$titulo_item" ] && [ -n "\$cmd_item" ] || continue
    pad=\$(printf '%*s' \$((PROFUNDIDADE * 4)) '')
    printf '%smenuentry "%s" {\n%s    %s\n%s}\n' "\$pad" "\$titulo_item" "\$pad" "\$cmd_item" "\$pad"
done < "\$LISTA_ARQUIVO"
else
printf '    menuentry "%s" {\n        %s\n    }\n' "$op1_t" "$op1_c"
printf '    menuentry "%s" {\n        %s\n    }\n' "$op2_t" "$op2_c"
printf '    menuentry "%s" {\n        %s\n    }\n' "$op3_t" "$op3_c"
fi

while [ "\$PROFUNDIDADE" -gt 1 ]; do
PROFUNDIDADE=\$((PROFUNDIDADE - 1))
pad=\$(printf '%*s' \$((PROFUNDIDADE * 4)) '')
printf '%s}\n' "\$pad"
done

printf '}\n'
EOF
sudo chmod +x "$GRUB_42_MAIS_FILE"
}

find_all_themes() {
find "$HOME" "$THEMES_DIR" -name "theme.txt" 2>/dev/null | sort -u
}

apply_theme_path() {
local chosen="$1"
local theme_parent
local theme_folder_name
local dest_dir

theme_parent="$(dirname "$chosen")"
theme_folder_name="$(basename "$theme_parent")"
dest_dir="$THEMES_DIR/$theme_folder_name"

sudo mkdir -p "$THEMES_DIR"
if [ "$theme_parent" != "$dest_dir" ]; then
    sudo rm -rf "$dest_dir"
    sudo cp -r "$theme_parent" "$THEMES_DIR/"
fi
sudo chmod -R a+rX "$THEMES_DIR"

sudo sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT_FILE"
echo "GRUB_THEME=\"$dest_dir/theme.txt\"" | sudo tee -a "$GRUB_DEFAULT_FILE" >/dev/null
}

apply_theme_menu() {
local found_themes=()
while IFS= read -r file; do
    [ -n "$file" ] && found_themes+=("$file" "theme.txt encontrado")
done < <(find_all_themes)

if [ "${#found_themes[@]}" -eq 0 ]; then
    whiptail --title "Nenhum tema encontrado" \
        --msgbox "Nenhum arquivo theme.txt foi encontrado em ~ ou em $THEMES_DIR." \
        10 65
    return
fi

local chosen
chosen=$(whiptail --title "Selecionar tema GRUB" \
    --menu "Escolha o theme.txt para aplicar:" \
    20 82 10 "${found_themes[@]}" 3>&1 1>&2 2>&3) || return

apply_theme_path "$chosen"
regenerate_grub_cfg_direct
}

reset_classic_grub() {
if whiptail --title "Confirmar GRUB classico" \
    --yesno "Deseja remover GRUB_THEME de /etc/default/grub, limpar $THEMES_DIR/* e voltar ao menu classico?" \
    12 72; then
    sudo cp "$GRUB_DEFAULT_FILE" "${GRUB_DEFAULT_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
    sudo sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT_FILE"
    sudo rm -rf "${THEMES_DIR:?}/"*
    regenerate_grub_cfg_direct
fi
}

run_grub_mkconfig_now() {
clear
echo "Atualizando $GRUB_CFG_FILE..."
if sudo grub-mkconfig -o "$GRUB_CFG_FILE"; then
    whiptail --title "Sucesso" \
        --msgbox "Configuracao do GRUB atualizada com sucesso em:\n$GRUB_CFG_FILE" \
        10 65
else
    whiptail --title "Erro no grub-mkconfig" \
        --msgbox "Ocorreu um erro ao gerar $GRUB_CFG_FILE. Verifique o terminal." \
        10 65
fi
}

regenerate_grub_cfg_direct() {
if [ -s "$GRUB_MAIS_ITENS_FILE" ]; then
    write_42_mais "auto"
else
    write_42_mais "fixo"
fi
run_grub_mkconfig_now
}

regenerate_mode_auto() {
if [ -s "$GRUB_MAIS_ITENS_FILE" ]; then
    write_42_mais "auto"
else
    write_42_mais "fixo"
fi
run_grub_mkconfig_now
}

regenerate_mode_padrao() {
if [ ! -s "$GRUB_MAIS_ITENS_FILE" ]; then
    seed_empty_file "$GRUB_MAIS_ITENS_FILE"
fi
write_42_mais "padrao"
run_grub_mkconfig_now
}

regenerate_mode_personalizado() {
local theme_choice
theme_choice=$(whiptail --title "Personalizado - Tema GRUB" \
    --menu "Como deseja tratar o tema do GRUB?" \
    16 76 5 \
    "1" "Manter tema atual / padrao configurado" \
    "2" "Remover tema (GRUB classico / texto)" \
    "3" "Escolher tema baixado (theme.txt)" \
    "4" "Digitar caminho de tema manualmente" 3>&1 1>&2 2>&3) || return

case "$theme_choice" in
    1)
        if ! grep -q '^GRUB_THEME=' "$GRUB_DEFAULT_FILE" 2>/dev/null; then
            local first_theme
            first_theme="$(find_all_themes | head -n 1)"
            [ -n "$first_theme" ] && apply_theme_path "$first_theme"
        fi
        ;;
    2)
        sudo cp "$GRUB_DEFAULT_FILE" "${GRUB_DEFAULT_FILE}.bak.$(date +%Y%m%d-%H%M%S)"
        sudo sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT_FILE"
        ;;
    3)
        local found_themes=()
        while IFS= read -r file; do
            [ -n "$file" ] && found_themes+=("$file" "theme.txt encontrado")
        done < <(find_all_themes)

        if [ "${#found_themes[@]}" -gt 0 ]; then
            local chosen
            chosen=$(whiptail --title "Selecionar tema baixado" \
                --menu "Escolha um theme.txt:" \
                20 82 10 "${found_themes[@]}" 3>&1 1>&2 2>&3) || return
            apply_theme_path "$chosen"
        else
            whiptail --title "Sem temas" \
                --msgbox "Nenhum theme.txt encontrado. Mantendo configuracao atual." \
                10 60
        fi
        ;;
    4)
        local manual_theme
        manual_theme=$(whiptail --title "Caminho do tema" \
            --inputbox "Digite o caminho completo para o theme.txt (ou deixe vazio para sem tema):" \
            10 74 "" 3>&1 1>&2 2>&3) || return
        if [ -n "$manual_theme" ]; then
            apply_theme_path "$manual_theme"
        else
            sudo sed -i '/^GRUB_THEME=/d' "$GRUB_DEFAULT_FILE"
        fi
        ;;
esac

local source_choice
source_choice=$(whiptail --title "Personalizado - Origem do submenu Mais" \
    --menu "Qual origem usar para o submenu Mais?" \
    16 78 5 \
    "1" "Usar grub-mais-itens.conf (se existir)" \
    "2" "Usar grub-mais (variaveis / opcoes fixas)" \
    "3" "Editar grub-mais-itens.conf antes de gerar" \
    "4" "Editar grub-mais antes de gerar" 3>&1 1>&2 2>&3) || return

case "$source_choice" in
    1)
        if [ -s "$GRUB_MAIS_ITENS_FILE" ]; then
            write_42_mais "auto"
        else
            write_42_mais "fixo"
        fi
        ;;
    2)
        [ -s "$GRUB_MAIS_FILE" ] || seed_empty_file "$GRUB_MAIS_FILE"
        write_42_mais "fixo"
        ;;
    3)
        edit_with_tips "$GRUB_MAIS_ITENS_FILE"
        write_42_mais "auto"
        ;;
    4)
        edit_with_tips "$GRUB_MAIS_FILE"
        write_42_mais "fixo"
        ;;
esac

local timeout_val
timeout_val=$(whiptail --title "Personalizado - Tempo do menu (GRUB_TIMEOUT)" \
    --inputbox "Digite o tempo de espera em segundos (ex: 5, 10, -1):" \
    10 68 "5" 3>&1 1>&2 2>&3) || return
if [[ "$timeout_val" =~ ^-?[0-9]+$ ]]; then
    sudo sed -i '/^GRUB_TIMEOUT=/d' "$GRUB_DEFAULT_FILE"
    echo "GRUB_TIMEOUT=$timeout_val" | sudo tee -a "$GRUB_DEFAULT_FILE" >/dev/null
fi

if whiptail --title "Personalizado - Outros ajustes" \
    --yesno "Deseja tambem editar /etc/default/grub manualmente antes de gerar o grub.cfg?" \
    10 68; then
    edit_with_tips "$GRUB_DEFAULT_FILE"
fi

run_grub_mkconfig_now
}

regenerate_grub_menu() {
local regen_choice
regen_choice=$(whiptail --title "Regerar /boot/grub/grub.cfg" \
    --menu "Escolha o modo de geracao:" \
    16 78 4 \
    "1" "Automatico (respeita tema; usa grub-mais-itens ou opcoes fixas)" \
    "2" "Padrao (respeita tema; exibe grub-mais-itens se existir)" \
    "3" "Personalizado (tema, texto/baixados, grub-mais-itens/grub-mais, tempo)" \
    "4" "Voltar" 3>&1 1>&2 2>&3) || return

case "$regen_choice" in
    1) regenerate_mode_auto ;;
    2) regenerate_mode_padrao ;;
    3) regenerate_mode_personalizado ;;
    4) return 0 ;;
esac
}

require_whiptail

while true; do
CHOICE=$(whiptail --title "Gerenciador GNU GRUB (Terminal)" \
    --menu "Escolha uma acao:" \
    20 78 8 \
    "1" "Editar /etc/default/grub (com dicas + editor)" \
    "2" "Editar /etc/default/grub-mais-itens.conf (submenu Mais)" \
    "3" "Editar /etc/default/grub-mais (variaveis)" \
    "4" "Aplicar tema (procura theme.txt e configura)" \
    "5" "Voltar ao GRUB classico (remove tema)" \
    "6" "Regerar /boot/grub/grub.cfg (Auto / Padrao / Personalizado)" \
    "7" "Sair" 3>&1 1>&2 2>&3) || exit 0

case "$CHOICE" in
    1) edit_with_tips "$GRUB_DEFAULT_FILE" ;;
    2) edit_with_tips "$GRUB_MAIS_ITENS_FILE" ;;
    3) edit_with_tips "$GRUB_MAIS_FILE" ;;
    4) apply_theme_menu ;;
    5) reset_classic_grub ;;
    6) regenerate_grub_menu ;;
    7) exit 0 ;;
esac
done
