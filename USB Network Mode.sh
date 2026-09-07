#!/bin/bash
# =============================================================================
#  USB Network Mode - networking over the USB OTG port (g_ether gadget)
#
#    Universal mode : the handheld hands out IPs (its own DHCP server).
#                     ssh ark@10.44.44.1 from ANY computer, zero setup.
#    Internet mode  : the handheld asks the PC for an IP, PC shares its
#                     connection. Gives the handheld real internet access.
#    Remote Services: Samba (network shares) + Filebrowser (web, port 80).
#
#  Credentials for everything: ark / ark
#
#  Tested on R36S and clones running ArkOS / ArkOS4Clone.
#  Option 1 checks whether YOUR device can do this at all - run it first.
# =============================================================================

CURR_TTY="/dev/tty1"
sudo chmod 666 $CURR_TTY
reset
printf "\e[?25l" > $CURR_TTY
dialog --clear

export TERM=linux
export XDG_RUNTIME_DIR=/run/user/$UID/

if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
  sudo setfont /usr/share/consolefonts/Lat7-TerminusBold22x11.psf.gz 2>/dev/null
else
  sudo setfont /usr/share/consolefonts/Lat7-Terminus16.psf.gz 2>/dev/null
fi

pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
printf "\033c" > $CURR_TTY

height="17"
width="42"
BACKTITLE="USB Network Mode - ArkOS"
REPORT="/tmp/usbnet-compat.txt"

ExitMenu() {
  printf "\033c" > $CURR_TTY
  pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
  if [[ ! -e "/dev/input/by-path/platform-odroidgo2-joypad-event-joystick" ]]; then
    sudo setfont /usr/share/consolefonts/Lat7-Terminus20x10.psf.gz 2>/dev/null
  fi
  exit 0
}

Mode() {
  if ! lsmod | grep -q g_ether; then
    echo "OFF"
  elif pgrep -f "dhclient.*usb0" > /dev/null; then
    echo "INTERNET"
  else
    echo "UNIVERSAL"
  fi
}

RS() {
  pgrep -x filebrowser > /dev/null && echo "ON" || echo "OFF"
}

Status() {
  IP=$(ip -4 addr show usb0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
  case $(Mode) in
    OFF)
      printf 'Status: OFF\\nDevice IP: -\\nweb/smb services: %s' "$(RS)" ;;
    INTERNET)
      printf 'Status: ON (internet via PC)\\nDevice IP: %s\\nweb/smb services: %s' "${IP:-no IP}" "$(RS)" ;;
    UNIVERSAL)
      NCLI=$(ip neigh show dev usb0 2>/dev/null | grep -vc FAILED)
      printf 'Status: ON (universal)\\nDevice IP: %s (PCs: %s)\\nweb/smb services: %s' "${IP:-no IP}" "$NCLI" "$(RS)" ;;
  esac
}

# ---------------------------------------------------------------------------
#  Compatibility check.
#
#  USB gadget mode needs four things, and a failure in any one of them looks
#  identical from the outside ("nothing happens when I plug the cable in").
#  This separates them so you know whether it is fixable or not:
#
#    1. Kernel modules   - g_ether, or libcomposite + a function driver
#    2. A UDC            - the USB Device Controller the gadget binds to.
#                          No UDC means the SoC USB port is not wired for
#                          device mode. NOT fixable from software.
#    3. dr_mode          - device-tree setting. "host" only will never work
#                          as a gadget; needs a patched DTB.
#    4. VBUS detection   - the PHY must see the cable. If the data lines are
#                          not connected to the SoC (some clone boards), the
#                          extcon state stays 0 forever no matter what.
#
#  Case in point: an R35S with identical firmware, identical modules and
#  dr_mode="otg" still fails, because its USB-C data lines never reach the
#  SoC in device mode. Steps 1-3 pass, step 4 never does.
# ---------------------------------------------------------------------------
CompatCheck() {
  dialog --backtitle "$BACKTITLE" --infobox "Checking compatibility...\nplease wait" 5 $width > $CURR_TTY

  local fatal=0 warn=0
  : > "$REPORT"
  {
    echo "USB GADGET COMPATIBILITY REPORT"
    echo "==============================="
    echo ""
    MODEL=$(cat /sys/firmware/devicetree/base/model 2>/dev/null | tr -d '\0')
    echo "Device : ${MODEL:-unknown}"
    echo "Kernel : $(uname -r)"
    echo ""
  } >> "$REPORT"

  # --- 1. kernel modules --------------------------------------------------
  echo "1. KERNEL MODULES" >> "$REPORT"
  local mods_ok=0
  if lsmod | grep -qw g_ether || modinfo g_ether >/dev/null 2>&1; then
    echo "   [OK]   g_ether available" >> "$REPORT"; mods_ok=1
  else
    echo "   [--]   g_ether NOT found" >> "$REPORT"
  fi
  for m in libcomposite usb_f_rndis usb_f_ecm; do
    if modinfo "$m" >/dev/null 2>&1; then
      echo "   [OK]   $m available" >> "$REPORT"; mods_ok=1
    else
      echo "   [--]   $m not found" >> "$REPORT"
    fi
  done
  [ "$mods_ok" = 0 ] && { echo "   >> FATAL: no USB gadget driver in this kernel." >> "$REPORT"; fatal=1; }
  echo "" >> "$REPORT"

  # --- 2. UDC -------------------------------------------------------------
  echo "2. USB DEVICE CONTROLLER (UDC)" >> "$REPORT"
  local udcs
  udcs=$(ls /sys/class/udc/ 2>/dev/null)
  if [ -n "$udcs" ]; then
    for u in $udcs; do
      echo "   [OK]   $u" >> "$REPORT"
      echo "          state: $(cat /sys/class/udc/$u/state 2>/dev/null)" >> "$REPORT"
      local drv
      drv=$(cat /sys/class/udc/$u/function 2>/dev/null)
      [ -n "$drv" ] && echo "          bound: $drv" >> "$REPORT"
    done
  else
    echo "   [--]   no UDC present" >> "$REPORT"
    echo "   >> FATAL: this port cannot act as a USB device." >> "$REPORT"
    echo "      Usually means the SoC USB is wired host-only." >> "$REPORT"
    fatal=1
  fi
  echo "" >> "$REPORT"

  # --- 3. dr_mode ---------------------------------------------------------
  echo "3. DEVICE TREE dr_mode" >> "$REPORT"
  local found=0 seen_nodes=""
  for f in /sys/firmware/devicetree/base/*usb*/dr_mode /proc/device-tree/*usb*/dr_mode; do
    [ -e "$f" ] || continue
    local m node
    m=$(tr -d '\0' < "$f")
    node=$(basename "$(dirname "$f")")
    # /sys/firmware/devicetree and /proc/device-tree are the same tree
    case " $seen_nodes " in *" $node "*) continue ;; esac
    seen_nodes="$seen_nodes $node"
    found=1
    case "$m" in
      otg|peripheral) echo "   [OK]   $node = $m" >> "$REPORT" ;;
      host)           echo "   [!!]   $node = host  (gadget disabled)" >> "$REPORT"; warn=1 ;;
      *)              echo "   [??]   $node = $m" >> "$REPORT" ;;
    esac
  done
  if [ "$found" = 0 ]; then
    echo "   [??]   dr_mode not exposed by this kernel" >> "$REPORT"
  fi
  echo "" >> "$REPORT"

  # --- 4. VBUS / cable ----------------------------------------------------
  echo "4. CABLE / LINK DETECTION" >> "$REPORT"
  # The UDC state is the authority here. extcon is NOT reliable on every
  # board: on an RK3326 clone the gadget can be fully enumerated and
  # serving SSH while extcon still reports USB=0 across the board. Trust
  # the controller, and print extcon only as extra context.
  local link="unknown" ustate=""
  for u in $(ls /sys/class/udc/ 2>/dev/null); do
    ustate=$(cat "/sys/class/udc/$u/state" 2>/dev/null)
    case "$ustate" in
      configured|addressed) link="up" ;;
      "not attached"|"")    [ "$link" = "unknown" ] && link="down" ;;
      *)                    [ "$link" = "unknown" ] && link="partial" ;;
    esac
  done
  case "$link" in
    up)
      echo "   [OK]   link is up (UDC state: $ustate)" >> "$REPORT"
      echo "          a host is connected and enumerated" >> "$REPORT" ;;
    partial)
      echo "   [!!]   UDC state: $ustate" >> "$REPORT"
      echo "          cable seen but not enumerated yet" >> "$REPORT"
      warn=1 ;;
    down)
      echo "   [--]   no host connected (UDC: $ustate)" >> "$REPORT"
      echo "          This is normal if no cable is plugged" >> "$REPORT"
      echo "          in. Plug a DATA cable into the OTG" >> "$REPORT"
      echo "          port and run this check again." >> "$REPORT"
      echo "          If it still says this with a known" >> "$REPORT"
      echo "          good data cable, the board does not" >> "$REPORT"
      echo "          wire the data lines for device mode" >> "$REPORT"
      echo "          and this will never work." >> "$REPORT" ;;
    *)
      echo "   [??]   no UDC to query" >> "$REPORT" ;;
  esac
  echo "" >> "$REPORT"
  echo "   extcon (informational, unreliable):" >> "$REPORT"
  local seen=0
  for e in /sys/class/extcon/*; do
    [ -e "$e/state" ] || continue
    seen=1
    tr '\n' ' ' < "$e/state" | fold -w 46 | sed 's/^/      /' >> "$REPORT"
    echo "" >> "$REPORT"
  done
  [ "$seen" = 0 ] && echo "      none present" >> "$REPORT"
  echo "" >> "$REPORT"

  # --- 5. userland tools --------------------------------------------------
  echo "5. REQUIRED TOOLS" >> "$REPORT"
  for c in ip dialog dnsmasq dhclient; do
    if command -v "$c" >/dev/null 2>&1; then
      echo "   [OK]   $c" >> "$REPORT"
    else
      echo "   [--]   $c MISSING" >> "$REPORT"; fatal=1
    fi
  done
  echo "" >> "$REPORT"
  echo "6. OPTIONAL (Remote Services)" >> "$REPORT"
  for c in filebrowser smbd; do
    command -v "$c" >/dev/null 2>&1 \
      && echo "   [OK]   $c" >> "$REPORT" \
      || echo "   [--]   $c missing (option 4 wont work)" >> "$REPORT"
  done
  echo "" >> "$REPORT"

  # --- verdict ------------------------------------------------------------
  {
    echo "==============================="
    if [ "$fatal" = 1 ]; then
      echo "VERDICT: NOT SUPPORTED"
      echo ""
      echo "Something required is missing. See the"
      echo "FATAL lines above. A different firmware"
      echo "may help if it is only a missing module."
    elif [ "$warn" = 1 ]; then
      echo "VERDICT: SHOULD WORK, BUT..."
      echo ""
      echo "The software side is fine. The warnings"
      echo "above are about the cable or the port."
      echo "Check that you are using a DATA cable in"
      echo "the OTG port, then run this again."
    else
      echo "VERDICT: SUPPORTED"
      echo ""
      echo "Everything needed is present."
      echo "Go ahead and use option 2 or 3."
    fi
    echo "==============================="
    echo ""
    echo "Report saved to $REPORT"
  } >> "$REPORT"

  dialog --backtitle "$BACKTITLE" --title " Compatibility " \
         --textbox "$REPORT" 19 56 > $CURR_TTY
}

# Shows a one-line progress box. Several of the steps below take a few
# seconds (module load, DHCP, starting daemons) and without this the screen
# just sits there blank, which reads as a freeze.
Busy() {
  dialog --backtitle "$BACKTITLE" --infobox "$1" 5 $width > $CURR_TTY
}

LoadGadget() {
  Busy "Loading USB gadget module..."
  sudo modprobe g_ether dev_addr=42:61:72:6b:6f:53 host_addr=42:61:72:6b:6f:54 iProduct=R36S iManufacturer=ArkOS
  sleep 2
  if ! ip link show usb0 > /dev/null 2>&1; then
    dialog --backtitle "$BACKTITLE" --msgbox "ERROR: usb0 did not appear.\n\nRun option 1 (compatibility\ncheck) to find out why." 9 $width > $CURR_TTY
    return 1
  fi
  return 0
}

StartUniversal() {
  sudo pkill -f "dhclient.*usb0" 2>/dev/null
  sudo kill "$(cat /tmp/dnsmasq-usbnet.pid 2>/dev/null)" 2>/dev/null
  LoadGadget || return
  Busy "Configuring interface..."
  sudo ip addr flush dev usb0 2>/dev/null
  sudo ip addr add 10.44.44.1/24 dev usb0
  sudo ip link set usb0 up
  Busy "Starting SSH..."
  sudo systemctl start ssh
  sudo kill "$(cat /tmp/dnsmasq-usbnet.pid 2>/dev/null)" 2>/dev/null
  sudo rm -f /tmp/usbnet.leases
  Busy "Starting DHCP server..."
  sudo dnsmasq --interface=usb0 --bind-interfaces --except-interface=lo \
    --port=0 --dhcp-range=10.44.44.10,10.44.44.100,12h \
    --dhcp-option=3 --dhcp-option=6 \
    --pid-file=/tmp/dnsmasq-usbnet.pid --dhcp-leasefile=/tmp/usbnet.leases \
    --conf-file=/dev/null
  dialog --backtitle "$BACKTITLE" --msgbox "UNIVERSAL MODE ACTIVE\n\n1. Plug the OTG port into any PC\n2. The PC gets an IP automatically\n3. On the PC:\n   ssh ark@10.44.44.1 (pass: ark)\n   sftp://ark@10.44.44.1" 12 $width > $CURR_TTY
}

StartInternet() {
  sudo pkill -f "dhclient.*usb0" 2>/dev/null
  sudo kill "$(cat /tmp/dnsmasq-usbnet.pid 2>/dev/null)" 2>/dev/null
  LoadGadget || return
  sudo ip addr flush dev usb0 2>/dev/null
  sudo ip link set usb0 up
  dialog --backtitle "$BACKTITLE" --infobox "Asking the PC for an IP...\n(the PC must ALREADY be\nsharing its connection)" 6 $width > $CURR_TTY
  sudo timeout 20 dhclient -1 usb0 2>/dev/null
  IP=$(ip -4 addr show usb0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
  if [ -z "$IP" ]; then
    dialog --backtitle "$BACKTITLE" --msgbox "No IP received.\n\nTurn on connection sharing\non the PC, then retry here." 9 $width > $CURR_TTY
    return
  fi
  sudo systemctl start ssh
  if sudo ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1 || sudo ping -c 2 -W 4 8.8.8.8 > /dev/null 2>&1; then
    NET="Internet: WORKING"
    sudo timedatectl set-ntp 1 2>/dev/null
  else
    NET="Internet: NO ROUTE (check the PC)"
  fi
  dialog --backtitle "$BACKTITLE" --msgbox "INTERNET MODE ACTIVE\n\nDevice IP: $IP\n$NET\n\nssh ark@$IP (pass: ark)" 11 $width > $CURR_TTY
}

ServicesOn() {
  if [ "$(Mode)" = "OFF" ]; then
    dialog --backtitle "$BACKTITLE" --msgbox "Start the network first\n(option 2 or 3)." 6 $width > $CURR_TTY
    return
  fi
  IP=$(ip -4 addr show usb0 2>/dev/null | grep -oP 'inet \K[0-9.]+')
  Busy "Starting SSH / SFTP..."
  sudo systemctl start ssh
  Busy "Starting Samba shares..."
  sudo systemctl start smbd 2>/dev/null
  sudo systemctl start nmbd 2>/dev/null
  Busy "Starting web file browser..."
  sudo pkill -x filebrowser 2>/dev/null
  sleep 1
  sudo filebrowser -a 0.0.0.0 -p 80 -d /home/ark/.config/filebrowser.db -r / > /dev/null 2>&1 &
  sleep 2
  Busy "Checking services..."
  pgrep -x filebrowser > /dev/null || Busy "Web server did not start"
  dialog --backtitle "$BACKTITLE" --msgbox "REMOTE SERVICES ACTIVE\n\nFrom the PC (user/pass: ark/ark):\n\n  Web:     http://${IP:-IP}\n  Windows: \\\\\\\\${IP:-IP}\n  Linux:   smb://${IP:-IP}\n  SFTP:    sftp://ark@${IP:-IP}" 13 $width > $CURR_TTY
}

ServicesOff() {
  Busy "Stopping services..."
  sudo systemctl stop smbd 2>/dev/null
  sudo systemctl stop nmbd 2>/dev/null
  sudo pkill -x filebrowser 2>/dev/null
  dialog --backtitle "$BACKTITLE" --msgbox "Remote Services stopped.\n(ssh is still running)" 6 $width > $CURR_TTY
}

ServicesToggle() {
  if [ "$(RS)" = "ON" ]; then ServicesOff; else ServicesOn; fi
}

StopAll() {
  if [ "$(Mode)" = "OFF" ]; then
    [ "$1" != "quiet" ] && dialog --backtitle "$BACKTITLE" --msgbox "Already off." 5 $width > $CURR_TTY
    return
  fi
  Busy "Shutting down USB networking..."
  sudo systemctl stop smbd 2>/dev/null
  sudo systemctl stop nmbd 2>/dev/null
  sudo pkill -x filebrowser 2>/dev/null
  sudo pkill -f "dhclient.*usb0" 2>/dev/null
  sudo kill "$(cat /tmp/dnsmasq-usbnet.pid 2>/dev/null)" 2>/dev/null
  sudo ip addr flush dev usb0 2>/dev/null
  sudo ip link set usb0 down 2>/dev/null
  sudo rmmod g_ether 2>/dev/null
  [ "$1" != "quiet" ] && dialog --backtitle "$BACKTITLE" --msgbox "USB networking stopped.\nOTG port back to normal." 6 $width > $CURR_TTY
}

Info() {
  LEASES=$(awk '{h=($4=="*")?$2:$4; printf "  %s (%s)\\n", $3, h}' /tmp/usbnet.leases 2>/dev/null)
  GW=$(ip route show dev usb0 2>/dev/null | grep -oP 'default via \K[0-9.]+')
  EXTRA=""
  [ "$(Mode)" = "INTERNET" ] && EXTRA="\nGateway (PC): ${GW:-?}"
  [ "$(Mode)" = "UNIVERSAL" ] && EXTRA="\nLeases handed out:\n${LEASES:-  none}"
  dialog --backtitle "$BACKTITLE" --msgbox "$(Status)$EXTRA" 13 $width > $CURR_TTY
}

MainMenu() {
  while true; do
    selection=(dialog \
      --backtitle "$BACKTITLE" \
      --title " USB Network Manager " \
      --no-collapse \
      --clear \
      --ok-label "OK" \
      --cancel-label "EXIT" \
      --menu "$(Status)" $height $width 15)
    options=(
      1 "Check compatibility"
      2 "Start (universal)"
      3 "Start (internet via PC)"
      4 "Remote Services web/smb: $(RS)"
      5 "Stop everything"
      6 "Show info"
      7 "Exit"
    )
    choice=$("${selection[@]}" "${options[@]}" 2>&1 > $CURR_TTY) || ExitMenu
    case $choice in
      1) CompatCheck ;;
      2) StartUniversal ;;
      3) StartInternet ;;
      4) ServicesToggle ;;
      5) StopAll ;;
      6) Info ;;
      7) ExitMenu ;;
    esac
  done
}

sudo chmod 666 /dev/uinput 2>/dev/null
export SDL_GAMECONTROLLERCONFIG_FILE="/opt/inttools/gamecontrollerdb.txt"
pgrep -f gptokeyb | sudo xargs kill -9 2>/dev/null
/opt/inttools/gptokeyb -1 "USB Network Mode.sh" -c "/opt/inttools/keys.gptk" > /dev/null 2>&1 &
printf "\033c" > $CURR_TTY
dialog --clear
trap ExitMenu EXIT

MainMenu
