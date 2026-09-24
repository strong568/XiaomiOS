#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh

# Kiểm tra nếu tham số truyền vào là link URL
if [ ! -f "${baserom}" ] && [ "$(echo "$baserom" | grep -E '^https?://')" != "" ]; then
    info "Download link detected, starting a download..."

    # Tự động fix link SourceForge nếu thiếu /download
    if [[ "$baserom" == *"sourceforge.net/projects/"* && "$baserom" == *"/files/"* && "$baserom" != *"/download" ]]; then
        info "SourceForge direct file detected, appending /download..."
        baserom="${baserom}/download"
    fi

    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    # Tải bằng aria2c với đầy đủ cờ điều hướng và headers
    aria2c --max-download-limit=1024M \
           --file-allocation=none \
           --check-certificate=false \
           --allow-overwrite=true \
           --auto-file-renaming=false \
           -s16 -x16 -j16 \
           --content-disposition \
           -U "$USER_AGENT" \
           "${baserom}"

    # Bóc tách tên file dự kiến từ URL
    clean_baserom=$(basename "${baserom%%\?*}" | sed 's/\/download$//')

    # Ưu tiên lấy file zip thực tế vừa tải về trong thư mục
    downloaded_zip=$(ls -t *.zip 2>/dev/null | head -n 1)

    if [ -f "$work_dir/$clean_baserom" ]; then
        baserom="$clean_baserom"
    elif [ -n "$downloaded_zip" ] && [ -f "$downloaded_zip" ]; then
        baserom="$downloaded_zip"
    elif [ -f "$work_dir/topaz-ota_full-OS3.0.2.0.WMGCNXM-user-16.0-b487e82659.zip" ]; then
        baserom="topaz-ota_full-OS3.0.2.0.WMGCNXM-user-16.0-b487e82659.zip"
    elif [ -f "$work_dir/munch-ota_full-OS2.0.215.0.VLMCNXM-user-15.0-7df6d5ee94.zip" ]; then
        baserom="munch-ota_full-OS2.0.215.0.VLMCNXM-user-15.0-7df6d5ee94.zip"
    else
        error "Download error!"
        exit 1
    fi
    info "BASEROM: ${baserom}"

elif [ -f "${baserom}" ]; then
    info "BASEROM: ${baserom}"
else
    error "BASEROM: Invalid parameter"
    exit 1
fi

# ==================== Nhận diện thông tin ROM ====================
if [ "$(echo "$baserom" | grep 'miui_')" != "" ]; then
    device_code=$(basename "$baserom" | cut -d '_' -f 2)
    base_rom_code=$(echo "$baserom" | awk -F'_' '{print $3}')
elif [ "$(echo "$baserom" | grep 'xiaomi.eu_')" != "" ]; then
    device_code=$(basename "$baserom" | cut -d '_' -f 2)
    # Nếu vị trí 2 là chữ MUNCH, POCO... thì lấy chuỗi OS/V ở vị trí 3 hoặc lọc Regex
    base_rom_code=$(echo "$baserom" | grep -o -E '(OS[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+|V[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+)')
    if [ -z "$base_rom_code" ]; then
        base_rom_code=$(basename "$baserom" | cut -d '_' -f 3)
    fi


    # Dự phòng nếu vị trí gạch dưới khác format
    if [[ "$base_rom_code" != OS* && "$base_rom_code" != V* ]]; then
        base_rom_code=$(echo "$baserom" | grep -o -E '(OS[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+|V[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+)')
    fi
elif [ "$(echo "$baserom" | grep -E '.*-ota_full-.*')" != "" ]; then
    device_code=$(basename "$baserom" | cut -d '-' -f 1)
    base_rom_code=$(basename "$baserom" | cut -d '-' -f 3)

    # Chuẩn hóa device_code
    device_code=$(echo "$device_code" | awk -F '_' '{
        if (NF == 1) {
            print toupper($1)
        } else if (NF == 2) {
            print toupper($1) toupper(substr($2, 1, 1)) substr($2, 2)
        } else if (NF == 3) {
            printf toupper($1) toupper($2) toupper(substr($3, 1, 1)) substr($3, 2)
        }
    }')
else
    device_code="YourDevice"
    base_rom_code="Unknown"
fi

device_f=$(echo "$device_code" | sed 's/\(Global\|EEAGlobal\|INGlobal\|IDGlobal\|RUGlobal\|TWGlobal\|TRGlobal\|JPGlobal\)$//' | tr '[:upper:]' '[:lower:]')

# ==================== Xác định khu vực (Region) ====================
info "Get Device Type"
if echo "$device_code" | grep -q 'EEAGlobal'; then
    DEVICE_TYPE="EEAGlobal"
elif echo "$device_code" | grep -q 'INGlobal'; then
    DEVICE_TYPE="INGlobal"
elif echo "$device_code" | grep -q 'IDGlobal'; then
    DEVICE_TYPE="IDGlobal"
elif echo "$device_code" | grep -q 'RUGlobal'; then
    DEVICE_TYPE="RUGlobal"
elif echo "$device_code" | grep -q 'JPGlobal'; then
    DEVICE_TYPE="JPGlobal"
elif echo "$device_code" | grep -q 'Global'; then
    DEVICE_TYPE="Global"
elif echo "$device_code" | grep -q 'TWGlobal'; then
    DEVICE_TYPE="TWGlobal"
elif echo "$device_code" | grep -q 'TRGlobal'; then
    DEVICE_TYPE="TRGlobal"
else
    DEVICE_TYPE="China"
fi

# ==================== Nhận diện OS ====================
if echo "$base_rom_code" | grep -q "OS1"; then
    ROM_OS="OS1"
elif echo "$base_rom_code" | grep -q "OS2"; then
    ROM_OS="OS2"
elif echo "$base_rom_code" | grep -q "OS3"; then
    ROM_OS="OS3"
elif echo "$base_rom_code" | grep -q "V14"; then
    ROM_OS="MIUI"
elif echo "$base_rom_code" | grep -q "V13"; then
    ROM_OS="MIUI"
else
    # Dự phòng nếu là xiaomi.eu hoặc format đặc biệt
    if echo "$baserom" | grep -q "OS1"; then
        ROM_OS="OS1"
    elif echo "$baserom" | grep -q "OS2"; then
        ROM_OS="OS2"
    elif echo "$baserom" | grep -q "OS3"; then
        ROM_OS="OS3"
    elif echo "$baserom" | grep -q "V14"; then
        ROM_OS="MIUI"
    else
        echo "Unsupport ROM Exiting..."
        exit 1
    fi
fi

mkdir -p "$work_dir/bin/ddevice"
echo "$base_rom_code" > "$work_dir/bin/ddevice/base_rom_code.txt"
echo "$base_rom_code" > "$work_dir/bin/ddevice/os_code.txt"
echo "$device_code" > "$work_dir/bin/ddevice/device_code.txt"
echo "$DEVICE_TYPE" > "$work_dir/bin/ddevice/device_type.txt"
echo "$ROM_OS" > "$work_dir/bin/ddevice/rom_os.txt"
