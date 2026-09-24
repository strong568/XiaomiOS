#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh

# Kiểm tra nếu tham số truyền vào là link URL
if [ ! -f "${baserom}" ] && [ "$(echo "$baserom" | grep -E '^https?://')" != "" ]; then
    info "Download link detected, starting a download..."

    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    # Chuyển đổi link SourceForge thành Direct Mirror URL chuẩn
    if [[ "$baserom" == *"sourceforge.net"* ]]; then
        # Chuẩn hóa link: bỏ đuôi /download và tham số ?...
        clean_sf_url="${baserom%%\?*}"
        clean_sf_url="${clean_sf_url%/download}"
        
        # Bóc tách tên project và đường dẫn file
        # Ví dụ: https://sourceforge.net/projects/xiaomi-eu-multilang-miui-roms/files/xiaomi.eu/...
        project_name=$(echo "$clean_sf_url" | sed -n 's|.*projects/\([^/]*\)/files/.*|\1|p')
        file_subpath=$(echo "$clean_sf_url" | sed -n 's|.*projects/[^/]*/files/\(.*\)|\1|p')

        if [[ -n "$project_name" && -n "$file_subpath" ]]; then
            baserom="https://downloads.sourceforge.net/project/${project_name}/${file_subpath}"
            info "SourceForge direct mirror converted: $baserom"
        fi
    fi

    # Tải file trực tiếp bằng aria2c (Hỗ trợ tự động chuyển hướng và giữ kết nối)
    aria2c --max-download-limit=1024M \
           --file-allocation=none \
           --check-certificate=false \
           --allow-overwrite=true \
           --auto-file-renaming=false \
           --max-file-not-found=5 \
           --max-tries=5 \
           --retry-wait=2 \
           -s16 -x16 -j16 \
           --content-disposition \
           -U "$USER_AGENT" \
           "${baserom}" || {
               info "aria2c failed, falling back to curl -L..."
               curl -L -k -A "$USER_AGENT" -O -J "${baserom}"
           }

    # Bắt file zip có kích thước lớn nhất (> 500MB) vừa tải về trong thư mục
    downloaded_zip=$(find . -maxdepth 1 -type f -name "*.zip" -size +500M -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -1 | cut -f2- -d" " | sed 's|^\./||')

    if [ -n "$downloaded_zip" ] && [ -f "$downloaded_zip" ]; then
        baserom="$downloaded_zip"
    else
        # Dự phòng tìm file zip bất kỳ vừa tạo nếu file dung lượng nhỏ hơn
        downloaded_zip=$(ls -t *.zip 2>/dev/null | head -n 1)
        if [ -n "$downloaded_zip" ] && [ -f "$downloaded_zip" ]; then
            baserom="$downloaded_zip"
        else
            error "Download error: No zip file was downloaded!"
            exit 1
        fi
    fi
    info "BASEROM downloaded: ${baserom}"

elif [ -f "${baserom}" ]; then
    info "BASEROM local file: ${baserom}"
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
