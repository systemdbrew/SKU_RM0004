# SKU_RM0004

The project supports running on Raspberry Pi, Ubuntu, and [Home Assistant](https://github.com/systemdbrew/UCTRONICS_RM0004_HA). You can also use Python to call compiled libraries on these platforms.

## Raspberry Pi

Raspberry Pi 4 and Raspberry Pi 5 are supported, including Debian 12 Bookworm, Debian 13 Trixie, and their corresponding modern Raspberry Pi OS releases.

The display requires I²C and uses `/dev/i2c-1`. The installer enables I²C, loads `i2c-dev`, builds the application, installs it in `/usr/local/bin`, and creates and enables the systemd service.

### Install

```bash
git clone https://github.com/systemdbrew/SKU_RM0004.git
cd SKU_RM0004
./deployment_service.sh
```

If I²C was not previously enabled, `/dev/i2c-1` might not appear until after a reboot. The installer will say when this is required. Reboot once, and the enabled service will start automatically:

```bash
sudo reboot
```

### Troubleshooting

Confirm that the I²C device exists and inspect the service and its current-boot logs:

```bash
ls -l /dev/i2c*
systemctl status uctronics-display.service
journalctl -u uctronics-display.service -b
```

### Uninstall the service

```bash
sudo systemctl disable uctronics-display.service
sudo rm /etc/systemd/system/uctronics-display.service
sudo systemctl daemon-reload
```

## NVMe

NVMe support applies only to Raspberry Pi 5 with the UC-B86 NVMe HAT. See the [NVMe user guide](https://github.com/UCTRONICS/SKU_RM0004/blob/main/data/NVMe_User_Guide.md).
