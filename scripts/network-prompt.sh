#!/usr/bin/env bash
# Personal network preset: no interactive input.
configure_network_settings() {
  network_address="${network_address:-192.168.1.77/24}"
  network_gateway="${network_gateway:-192.168.1.1}"
  network_dns="${network_dns:-1.1.1.1}"
  local uuid kind device state selected_device='' selected_uuid=''
  if command -v nmcli >/dev/null 2>&1; then
    while IFS=: read -r uuid kind device; do
      [[ -n "$device" && "$device" != lo ]] || continue
      case "$kind" in
        wifi|802-11-wireless|ethernet|802-3-ethernet) ;;
        *) continue ;;
      esac
      state="$(nmcli -g GENERAL.STATE device show "$device" 2>/dev/null)" || continue
      [[ "$state" == 100* ]] || continue
      if [[ -n "$network_interface" ]]; then
        [[ "$device" == "$network_interface" ]] || continue
        selected_device="$device"; selected_uuid="$uuid"
        break
      fi
      if [[ -z "$selected_device" || "$kind" == ethernet || "$kind" == 802-3-ethernet ]]; then
        selected_device="$device"; selected_uuid="$uuid"
        [[ "$kind" != ethernet && "$kind" != 802-3-ethernet ]] || break
      fi
    done < <(nmcli -t -f UUID,TYPE,DEVICE connection show --active 2>/dev/null)
  fi
  if [[ -n "$selected_device" ]]; then
    network_interface="$selected_device"; network_uuid="$selected_uuid"
  fi
  return 0
}
