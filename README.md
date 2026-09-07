# ArkOS USB Network Mode

Use your ArkOS handheld over a plain USB cable — no WiFi dongle, no soldering,
no extra hardware.

Turns the OTG port into a network interface so you can:

- copy ROMs and saves (web browser, Samba or SFTP)
- get an SSH shell on the device
- optionally give the handheld **internet** through your PC

Known to work on **R36S and clones** running ArkOS / ArkOS4Clone.
It may or may not work on yours — the tool tells you.

---

## Check compatibility first

On the handheld: **Options → USB Network Mode → option 1**

Not every clone can do this. The board has to route the USB-C data lines to
the SoC in device mode, and plenty of them do not — even when the firmware,
the kernel modules and the device tree all look correct.

Option 1 checks the four requirements separately, because **failing any one
of them looks identical from the outside** ("nothing happens when I plug the
cable in"):

| # | Requirement | If it fails |
|---|---|---|
| 1 | Kernel gadget modules (`g_ether`, `libcomposite`) | different firmware may fix it |
| 2 | A **UDC** in `/sys/class/udc` | fatal — the port is not wired as a device |
| 3 | `dr_mode` in the device tree | fixable with a patched DTB |
| 4 | Link detection (UDC state) | fatal if a known-good data cable still shows nothing |

It ends with a plain verdict: `SUPPORTED`, `SHOULD WORK, BUT...` or
`NOT SUPPORTED`. It only reads — it changes nothing.

<details>
<summary>Why this check exists</summary>

An R35S with the same firmware, the same modules present and `dr_mode="otg"`
still fails. Steps 1–3 pass; the USB-C data lines simply never reach the SoC
in device mode, so no host ever appears. Without a check like this you would
spend hours swapping cables and reflashing for a problem that has no software
fix.

Note that `extcon` is **not** a reliable signal: on an RK3326 clone the gadget
can be fully enumerated and serving SSH while extcon still reports `USB=0`
across the board. The UDC state is the authority.
</details>

---

## Install

**On the handheld** — copy `USB Network Mode.sh` to `/opt/system/`
(or `/roms2/tools/` if you use the SD2 layout) and make it executable:

```sh
chmod +x "/opt/system/USB Network Mode.sh"
```

It then shows up in the Options menu. No reboot needed.

```
option 1  check compatibility     <- run this first
option 2  universal   (the handheld hands out IPs)
option 3  internet    (the PC shares its connection)
option 4  Remote Services (web + Samba)
option 5  stop everything
```

**On the PC**

- Windows — run `setup-windows.bat`. **It does not change any setting.**
  It is a walkthrough plus a connectivity test; the one thing Windows needs
  configuring for (internet sharing) is done by hand, and the script tells
  you where to click.
- Linux — `sudo ./setup-linux.sh`. This one *does* change things: it names
  the interface `arkos0`, stops NetworkManager from creating duplicate
  profiles, adds a firewall workaround for Docker, and creates two network
  profiles.

### What is automatic and what is not

| | Windows | Linux |
|---|---|---|
| Install the script on the handheld | by hand | by hand |
| USB network driver | automatic | automatic |
| Stable interface name | n/a | `setup-linux.sh` |
| Avoid duplicate profiles | n/a | `setup-linux.sh` |
| Docker firewall workaround | n/a | `setup-linux.sh` |
| Network profiles | n/a | `setup-linux.sh` |
| **File mode** (universal) | nothing to do | nothing to do |
| **Internet sharing** | **by hand** (ICS, 6 clicks) | switch the profile on, by hand |

The short version: for copying files you configure nothing on either OS.
Only internet sharing needs a human, and on Linux the script has already
prepared everything so it is one toggle.

> Plug the cable into the **OTG port**, not the charge-only one, and use a
> **data cable**. Charge-only cables leave you stuck at "connecting" forever
> and are by far the most common cause of "it doesn't work".

---

## Which mode do I want?

| | Use it for | PC setup needed |
|---|---|---|
| **Universal** | moving files, SSH, using it on someone else's computer | none |
| **Internet** | the handheld itself needs the network (PortMaster, clock) | connection sharing |

## Access

User / password: **`ark` / `ark`**

Universal mode:

```
Browser    http://10.44.44.1
Windows    \\10.44.44.1
Linux      smb://10.44.44.1
SFTP       sftp://ark@10.44.44.1
SSH        ssh ark@10.44.44.1
```

Internet mode: the PC assigns the IP — `192.168.137.x` on Windows,
`10.42.0.x` on Linux. The handheld shows it on screen when it connects.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| Stuck at "connecting" | charge-only cable — swap it |
| Nothing shows up on the PC | wrong port, use the OTG one |
| Web page dead but SSH works | turn on option 4 |
| Worked once, not any more | option 5, then start again |
| Check reports no link with a good data cable | the board does not wire data lines for device mode — nothing to be done in software |

---

## Notes

The gadget is loaded with a **fixed MAC address** and identifies itself as
`R36S / ArkOS`. This matters more than it sounds: with a random MAC,
NetworkManager creates a brand new *"Wired connection N"* profile on every
reconnect, and that profile comes up link-local instead of DHCP — which looks
exactly like the handheld not responding.

`setup-linux.sh` also works around Docker: it sets the `FORWARD` chain policy
to `DROP`, which silently breaks NetworkManager's shared connection. The
dispatcher script re-opens it only for the handheld's interface, only while
it is up.

Everything runs from RAM. Nothing is installed permanently on the handheld,
and option 5 unloads the module and puts the OTG port back to normal.
