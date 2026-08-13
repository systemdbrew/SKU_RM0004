#!/usr/bin/env bash

set -euo pipefail

readonly SERVICE_NAME="uctronics-display.service"
readonly SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}"
readonly INSTALL_PATH="/usr/local/bin/uctronics-display"
readonly I2C_CONFIG="dtparam=i2c_arm=on,i2c_arm_baudrate=400000"

status() {
    printf '[uctronics] %s\n' "$*"
}

if [[ ! -f Makefile ]]; then
    printf 'Error: run this script from the SKU_RM0004 repository directory.\n' >&2
    exit 1
fi

if [[ ! -r /proc/device-tree/model ]]; then
    printf 'Error: unable to read the Raspberry Pi model.\n' >&2
    exit 1
fi

MODEL=$(tr -d '\0' </proc/device-tree/model)
case "$MODEL" in
    *"Raspberry Pi 5"*) PI_GENERATION=5 ;;
    *"Raspberry Pi 4"*) PI_GENERATION=4 ;;
    *)
        printf 'Error: unsupported model: %s. Raspberry Pi 4 or 5 is required.\n' "$MODEL" >&2
        exit 1
        ;;
esac
status "Detected Raspberry Pi ${PI_GENERATION}: ${MODEL}"

# shellcheck disable=SC1091
source /etc/os-release
DEBIAN_VERSION=${VERSION_ID:-unknown}
DEBIAN_MAJOR=${DEBIAN_VERSION%%.*}
if [[ "$DEBIAN_MAJOR" =~ ^[0-9]+$ ]] && (( DEBIAN_MAJOR >= 12 )); then
    BOOT_CONFIG=/boot/firmware/config.txt
else
    BOOT_CONFIG=/boot/config.txt
fi
status "Debian/Raspberry Pi OS version: ${DEBIAN_VERSION}"
status "Boot configuration: ${BOOT_CONFIG}"

if [[ ! -f "$BOOT_CONFIG" ]]; then
    printf 'Error: boot configuration not found at %s.\n' "$BOOT_CONFIG" >&2
    exit 1
fi

if (( PI_GENERATION == 5 )); then
    SHUTDOWN_OVERLAY="dtoverlay=gpio-shutdown,gpio_pin=4,active_low=1,gpio_pull=up,debounce=1000"
else
    SHUTDOWN_OVERLAY="dtoverlay=gpio-shutdown,gpio_pin=4,active_low=1,gpio_pull=up"
fi

if ! grep -Eq '^[[:space:]]*dtoverlay=gpio-shutdown,gpio_pin=4([,[:space:]]|$)' "$BOOT_CONFIG"; then
    printf '%s\n' "$SHUTDOWN_OVERLAY" | sudo tee -a "$BOOT_CONFIG" >/dev/null
    status "Added gpio-shutdown overlay for Raspberry Pi ${PI_GENERATION}."
else
    status "gpio-shutdown overlay is already configured."
fi

if command -v raspi-config >/dev/null 2>&1; then
    status "Enabling I2C with raspi-config."
    sudo raspi-config nonint do_i2c 0
else
    status "raspi-config is not installed; enabling I2C in ${BOOT_CONFIG}."
fi

# Replace all existing i2c_arm settings with one canonical line. This makes
# repeated installer runs idempotent and removes conflicting duplicate entries.
sudo sed -i -E '/^[[:space:]]*#?[[:space:]]*dtparam=i2c_arm=/d' "$BOOT_CONFIG"
printf '%s\n' "$I2C_CONFIG" | sudo tee -a "$BOOT_CONFIG" >/dev/null
status "I2C boot configuration is set to: ${I2C_CONFIG}"

sudo modprobe i2c-dev
if [[ ! -f /etc/modules-load.d/i2c-dev.conf ]]; then
    printf 'i2c-dev\n' | sudo tee /etc/modules-load.d/i2c-dev.conf >/dev/null
    status "Configured i2c-dev to load at boot."
elif ! grep -Fxq 'i2c-dev' /etc/modules-load.d/i2c-dev.conf; then
    printf 'i2c-dev\n' | sudo tee -a /etc/modules-load.d/i2c-dev.conf >/dev/null
    status "Added i2c-dev to the existing modules-load configuration."
else
    status "i2c-dev is already configured to load at boot."
fi

I2C_AVAILABLE=false
if [[ -e /dev/i2c-1 ]]; then
    I2C_AVAILABLE=true
    status "I2C status: /dev/i2c-1 is available."
else
    status "I2C status: /dev/i2c-1 is still missing after configuration."
    status "A reboot is required before the display service can run."
fi

status "Building uctronics-display (make clean && make)."
make clean && make
status "Build status: successful."

sudo install -m 0755 display "$INSTALL_PATH"
status "Binary install status: installed ${INSTALL_PATH}."

sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=UCTRONICS Display
After=multi-user.target

[Service]
ExecStart=${INSTALL_PATH}
Restart=on-failure
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

if [[ "$I2C_AVAILABLE" == true ]]; then
    status "I2C is ready; starting/restarting ${SERVICE_NAME}."
    if sudo systemctl restart "$SERVICE_NAME"; then
        status "systemd status: ${SERVICE_NAME} is enabled and running."
    else
        status "systemd status: ${SERVICE_NAME} is enabled but failed to start."
        printf 'Check: systemctl status %s\n' "$SERVICE_NAME" >&2
        exit 1
    fi
else
    status "systemd status: ${SERVICE_NAME} is enabled but was not started."
    status "Reboot, then verify it with: systemctl status ${SERVICE_NAME}"
fi
