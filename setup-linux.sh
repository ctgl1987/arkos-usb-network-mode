#!/bin/bash
# ==========================================================================
#  ArkOS USB Network - one-time setup for a Linux PC (NetworkManager)
#
#  Run once:  sudo ./setup-linux.sh
#
#  Nothing here is needed just to copy files - universal mode works out of
#  the box. This exists so that (a) the interface gets a stable name,
#  (b) NetworkManager stops inventing duplicate profiles, and (c) sharing
#  the PC's internet actually reaches the handheld even with Docker
#  installed.
# ==========================================================================
set -e
[ "$(id -u)" = 0 ] || { echo "Run with sudo:  sudo ./setup-linux.sh"; exit 1; }
command -v nmcli >/dev/null || { echo "This machine does not use NetworkManager."; exit 1; }

echo ">> 1/4  Naming the handheld's USB interface 'arkos0'..."
# Without a fixed name the kernel picks things like enp0s20f0u1c2i1, which
# changes between ports and reboots and makes every rule below useless.
cat > /etc/udev/rules.d/99-arkos-usbnet.rules << 'UDEV'
SUBSYSTEM=="net", ACTION=="add", ATTRS{idVendor}=="0525", ATTRS{idProduct}=="a4a2", NAME="arkos0"
UDEV
udevadm control --reload

echo ">> 2/4  Preventing duplicate 'Wired connection N' profiles..."
# NetworkManager auto-creates a default profile for any unmanaged wired
# device. That profile comes up link-local instead of DHCP, which looks
# exactly like "the console is not responding".
cat > /etc/NetworkManager/conf.d/99-arkos-no-auto-default.conf << 'NMCONF'
[main]
no-auto-default=arkos0
NMCONF

echo ">> 3/4  Firewall fix (share internet even with Docker installed)..."
# Docker sets the FORWARD chain policy to DROP, which silently kills
# NetworkManager's shared-connection routing. These rules re-open it only
# for the handheld's interface, and only while it is up.
cat > /etc/NetworkManager/dispatcher.d/50-arkos-inet << 'DISP'
#!/bin/bash
[ "$1" = "arkos0" ] || exit 0
case "$2" in
  up)
    iptables -C FORWARD -i arkos0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i arkos0 -j ACCEPT
    iptables -C FORWARD -o arkos0 -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -o arkos0 -j ACCEPT ;;
  down)
    iptables -D FORWARD -i arkos0 -j ACCEPT 2>/dev/null
    iptables -D FORWARD -o arkos0 -j ACCEPT 2>/dev/null ;;
esac
DISP
chmod 755 /etc/NetworkManager/dispatcher.d/50-arkos-inet
systemctl reload NetworkManager 2>/dev/null || true
sleep 1

echo ">> 4/4  Creating the two network profiles..."
nmcli connection delete "ArkOS USB (files)"    2>/dev/null || true
nmcli connection delete "ArkOS USB (internet)" 2>/dev/null || true
# files: the handheld runs the DHCP server, the PC just takes an address
nmcli connection add type ethernet con-name "ArkOS USB (files)" \
  connection.interface-name arkos0 ipv4.method auto ipv6.method ignore \
  connection.autoconnect yes connection.autoconnect-priority 10 >/dev/null
# internet: the PC runs DHCP and NATs; manual so it never fights the above
nmcli connection add type ethernet con-name "ArkOS USB (internet)" \
  connection.interface-name arkos0 ipv4.method shared ipv6.method ignore \
  connection.autoconnect no >/dev/null

echo ""
echo "=========================================================="
echo " DONE."
echo "   Files/ssh:     handheld option 2  ->  http://10.44.44.1"
echo "   Give internet: switch on 'ArkOS USB (internet)' in the"
echo "                  network applet, then use option 3 on the"
echo "                  handheld"
echo ""
echo " To undo: delete the two profiles with nmcli, plus"
echo "   /etc/udev/rules.d/99-arkos-usbnet.rules"
echo "   /etc/NetworkManager/conf.d/99-arkos-no-auto-default.conf"
echo "   /etc/NetworkManager/dispatcher.d/50-arkos-inet"
echo "=========================================================="
