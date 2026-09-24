#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh

# Kiểm tra nếu tham số truyền vào là link URL
if [ ! -f "${baserom}" ] && [ "$(echo "$baserom" | grep -E '^https?://')" != "" ]; then
    info "Download link detected, starting a download..."

    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    # Xử lý đặc thù cho SourceForge để không bị chặn mã 403 và không bị tải nhầm trang HTML
    if [[ "$baserom" == *"sourceforge.net"* ]]; then
        [[ "$baserom" != *"/download" ]] && baserom="${baserom}/download"
        
        info "SourceForge direct file detected, resolving redirect mirror..."
        
        # Bóc tách tên file dự kiến từ URL
        expected_filename=$(echo "$baserom" | grep -oP 'files/[^/]+/(?:[^/]+/)*\K[^/]+(?=/download)')
        if [ -z "$expected_filename" ]; then
            expected_filename=$(basename "${baserom%/download}")
        fi

        # Tìm URL mirror trực tiếp qua header Location
        DIRECT_URL=$(curl -sIL -A "$USER_AGENT" -e "https://sourceforge.net/" "$baserom" | grep -i "^location:" | tail -n 1 | awk '{print $2}' | tr -d '\r\n')
        
        if [[ -n "$DIRECT_URL" && "$DIRECT_URL" =~ ^https?:// ]]; then
            info "Downloading from resolved mirror: $DIRECT_URL"
            aria2c --header="User-Agent: $USER_AGENT" \
                   --header="Referer: https://sourceforge.net/" \
                   --check-certificate=false \
                   --allow-overwrite=true \
                   -x16 -s16 -j16 \
                   -o "$expected_filename" \
                   "$DIRECT_URL" || curl -L -k -A "$USER_AGENT" -e "https://sourceforge.net/" -o "$expected_filename" "$DIRECT_URL"
        else
            info "Fallback: Direct stream with curl..."
            curl -L -k -A "$USER_AGENT" -e "https://sourceforge.net/" -o "$expected_filename" "$baserom"
        fi
    else
        # Link tải trực tiếp bình thường (Aliyun, direct host...)
        aria2c --max-download-limit=1024M \
               --file-allocation=none \
               --check-certificate=false \
               --allow-overwrite=true \
               --auto-file-renaming=false \
               -s16 -x16 -j16 \
               --content-disposition \
               -U "$USER_AGENT" \
               "${baserom}"
    fi

    # Ưu tiên lấy file zip có dung lượng lớn nhất vừa tải về
    downloaded_zip=$(ls -S *.zip 2>/dev/null | head -n 1)

    if [ -n "$downloaded_zip" ] && [ -f "$downloaded_zip" ]; then
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
    base_rom_code=$(echo "$baserom" | grep -o -E '(OS[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+|V[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+\.[A-Z]+)')
    if [ -z "$base_rom_code" ]; then
        base_rom_code=$(basename "$baserom" | cut -d '_' -f 3)
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
