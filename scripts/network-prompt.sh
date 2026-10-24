#!/usr/bin/env bash
# NetworkManager discovery for the optional Bash executor; no changes are made here.
prompt_network_settings() {
  local -a devices=() uuids=() names=() kinds=()
  local i uuid kind device name state choice index=-1 default_address='' default_gateway='' default_dns=1.1.1.1 value
  printf '\n  Configuração da rede IPv4\n'
  if command -v nmcli >/dev/null 2>&1; then
    while IFS=: read -r uuid kind device; do
      [[ -n "$device" && "$device" != lo ]] || continue
      case "$kind" in
        wifi|802-11-wireless) kind=Wi-Fi ;;
        ethernet|802-3-ethernet) kind=cabo ;;
        *) continue ;;
      esac
      state="$(nmcli -g GENERAL.STATE device show "$device" 2>/dev/null)" || continue
      [[ "$state" == 100* ]] || continue
      name="$(nmcli -e no -g connection.id connection show uuid "$uuid" 2>/dev/null)" || name="$device"
      name="$(printf '%s' "$name" | tr '\000-\037\177' ' ')"
      devices+=("$device"); uuids+=("$uuid"); names+=("${name:-$device}"); kinds+=("$kind")
    done < <(nmcli -t -f UUID,TYPE,DEVICE connection show --active 2>/dev/null)
  fi
  if [[ -n "$network_interface" ]]; then
    for i in "${!devices[@]}"; do [[ "${devices[i]}" == "$network_interface" ]] && index=$i; done
  elif ((${#devices[@]} == 1)); then
    index=0
  elif ((${#devices[@]} > 1)); then
    printf '  Escolha a rede que receberá o IP fixo:\n'
    for i in "${!devices[@]}"; do printf '    %d) %s (%s)\n' "$((i+1))" "${names[i]}" "${kinds[i]}"; done
    while true; do
      read -r -p "  Rede [1–${#devices[@]}, Q cancela]: " choice || return 1
      [[ "$choice" != q && "$choice" != Q ]] || return 1
      if [[ "$choice" =~ ^[0-9]{1,3}$ ]] && ((10#$choice >= 1 && 10#$choice <= ${#devices[@]})); then index=$((10#$choice-1)); break; fi
      printf '  Digite o número de uma das redes acima.\n'
    done
  fi
  if ((index>=0)); then
    network_interface="${devices[index]}"; network_uuid="${uuids[index]}"
    printf '  Rede selecionada: %s (%s)\n' "${names[index]}" "${kinds[index]}"
    default_address="$(nmcli -g IP4.ADDRESS device show "$network_interface" 2>/dev/null | head -1)" || default_address=''
    default_gateway="$(nmcli -g IP4.GATEWAY device show "$network_interface" 2>/dev/null | head -1)" || default_gateway=''
    default_dns="$(nmcli -g IP4.DNS device show "$network_interface" 2>/dev/null | head -1)" || default_dns=''
    default_dns="${default_dns:-1.1.1.1}"
  elif [[ -z "$network_interface" ]]; then
    printf '  Nenhuma rede Wi-Fi/cabo ativa detectada; informe a interface manualmente.\n'
    read -r -p '  Interface de rede: ' network_interface || return 1
  fi
  if [[ -z "$network_address" ]]; then
    read -r -p "  Endereço IPv4/CIDR${default_address:+ [$default_address]}: " value || return 1
    network_address="${value:-$default_address}"
  fi
  if [[ -z "$network_gateway" ]]; then
    read -r -p "  Gateway IPv4${default_gateway:+ [$default_gateway]}: " value || return 1
    network_gateway="${value:-$default_gateway}"
  fi
  if [[ -z "$network_dns" ]]; then
    read -r -p "  DNS IPv4 [$default_dns]: " value || return 1
    network_dns="${value:-$default_dns}"
  fi
}
