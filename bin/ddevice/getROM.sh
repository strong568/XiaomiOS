#!/bin/bash

baserom="$1"
work_dir=$(pwd)
source $work_dir/functions.sh

# Kiểm tra nếu tham số truyền vào là link URL
if [ ! -f "${baserom}" ] && [ "$(echo "$baserom" | grep -E '^https?://')" != "" ]; then
    info "Download link detected, starting a download..."

    USER_AGENT="Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"

    # ==================== 1. XỬ LÝ LINK GOFILE ====================
    if [[ "$baserom" == *"gofile.io"* ]]; then
        info "Gofile link detected, resolving direct download link..."
        content_id=$(echo "$baserom" | grep -oP 'gofile\.io\/d\/\K[a-zA-Z0-9]+')
        download_done=false

        # Cách 1: Giải mã API bằng Python (chỉ chạy nếu là link dạng folder /d/)
        if [ -n "$content_id" ]; then
            python_res=$(python3 - <<EOF
import sys, json, urllib.request

content_id = "$content_id"
ua = "$USER_AGENT"
headers_base = {
    "User-Agent": ua,
    "Accept": "application/json",
    "Origin": "https://gofile.io",
    "Referer": f"https://gofile.io/d/{content_id}"
}

try:
    # 1. Tạo guest token
    req_acc = urllib.request.Request("https://api.gofile.io/accounts", headers=headers_base, method="POST")
    with urllib.request.urlopen(req_acc) as resp:
        acc_data = json.loads(resp.read().decode())
        token = acc_data.get("data", {}).get("token", "")

    if not token:
        sys.exit(1)

    # 2. Lấy nội dung thư mục
    url_content = f"https://api.gofile.io/contents/{content_id}"
    headers_content = headers_base.copy()
    headers_content["Authorization"] = f"Bearer {token}"
    headers_content["Cookie"] = f"accountToken={token}"

    req_content = urllib.request.Request(url_content, headers=headers_content)
    with urllib.request.urlopen(req_content) as resp:
        c_data = json.loads(resp.read().decode())
        children = c_data.get("data", {}).get("children", {})
        
        direct_link = ""
        file_name = ""
        
        if isinstance(children, dict):
            for item_id, item in children.items():
                if item.get("name", "").endswith(".zip") or item.get("type") == "file":
                    direct_link = item.get("link", "")
                    file_name = item.get("name", "")
                    break
        elif isinstance(children, list):
            for item in children:
                if item.get("name", "").endswith(".zip") or item.get("type") == "file":
                    direct_link = item.get("link", "")
                    file_name = item.get("name", "")
                    break

        if direct_link:
            print(f"{token}|{direct_link}|{file_name}")
        else:
            sys.exit(1)
except Exception:
    sys.exit(1)
EOF
)
            if [ -n "$python_res" ]; then
                guest_token=$(echo "$python_res" | cut -d'|' -f1)
                direct_gofile_url=$(echo "$python_res" | cut -d'|' -f2)
                file_name=$(echo "$python_res" | cut -d'|' -f3)

                info "Direct link resolved: $direct_gofile_url"
                info "Downloading $file_name via aria2c..."

                if aria2c --header="Cookie: accountToken=${guest_token}" \
                          --header="User-Agent: $USER_AGENT" \
                          --check-certificate=false \
                          --allow-overwrite=true \
                          --auto-file-renaming=false \
                          -s16 -x16 -j16 \
                          -o "$file_name" \
                          "$direct_gofile_url"; then
                    download_done=true
                fi
            fi
        fi

        # Cách 2: Dự phòng bằng gofile-dl nếu cách 1 thất bại hoặc link không phải dạng /d/
        if [ "$download_done" = false ]; then
            warn "API resolve failed or direct link provided, fallback to gofile-dl..."
            python3 -m pip install -q --no-cache-dir gofile-dl 2>/dev/null || pip3 install -q gofile-dl
            
            if python3 -m gofile_dl "$baserom"; then
                download_done=true
            fi
        fi

        if [ "$download_done" = false ]; then
            error "Không thể tải file từ Gofile! Vui lòng dùng link Pixeldrain."
            exit 1
        fi

    # ==================== 2. XỬ LÝ LINK PIXELDRAIN ====================
    elif [[ "$baserom" == *"pixeldrain.com"* ]]; then
        info "Pixeldrain link detected, downloading via API..."
        pixel_id=$(echo "$baserom" | grep -oP '(u\/|file\/)\K[a-zA-Z0-9]+')
        if [ -n "$pixel_id" ]; then
            direct_pixel="https://pixeldrain.com/api/file/${pixel_id}"
            aria2c --header="User-Agent: $USER_AGENT" \
                   --check-certificate=false \
                   --allow-overwrite=true \
                   --auto-file-renaming=false \
                   --content-disposition \
                   -s16 -x16 -j16 \
                   "$direct_pixel" || curl -L -k -A "$USER_AGENT" -O -J "$direct_pixel"
        fi

    # ==================== 3. XỬ LÝ LINK GOOGLE DRIVE ====================
    elif [[ "$baserom" == *"drive.google.com"* || "$baserom" == *"drive.usercontent.google.com"* ]]; then
        info "Google Drive link detected, using gdown..."
        
        python3 -m pip install -q --no-cache-dir gdown 2>/dev/null || pip3 install -q gdown

        # Bóc tách ID file từ link (bắt được cả dạng id= và /d/)
        GDRIVE_ID=$(echo "$baserom" | grep -oP '(id=|\/d\/)\K[a-zA-Z0-9_-]+')

        if [ -n "$GDRIVE_ID" ]; then
            gdown "https://drive.google.com/uc?id=${GDRIVE_ID}"
        else
            gdown "$baserom"
        fi

    # ==================== 4. XỬ LÝ NGUỒN TẢI SOURCEFORGE ====================
    elif [[ "$baserom" == *"sourceforge.net"* ]]; then
        info "SourceForge detected. Resolving direct mirror host..."

        clean_sf_url="${baserom%%\?*}"
        clean_sf_url="${clean_sf_url%/download}"

        project_name=$(echo "$clean_sf_url" | sed -n 's|.*projects/\([^/]*\)/files/.*|\1|p')
        file_subpath=$(echo "$clean_sf_url" | sed -n 's|.*projects/[^/]*/files/\(.*\)|\1|p')

        expected_filename=$(basename "$file_subpath")
        if [ -z "$expected_filename" ]; then
            expected_filename="rom_baserom.zip"
        fi

        MIRRORS=(
            "https://master.dl.sourceforge.net/project/${project_name}/${file_subpath}"
            "https://versaweb.dl.sourceforge.net/project/${project_name}/${file_subpath}"
            "https://ixpeering.dl.sourceforge.net/project/${project_name}/${file_subpath}"
            "https://twds.dl.sourceforge.net/project/${project_name}/${file_subpath}"
            "https://downloads.sourceforge.net/project/${project_name}/${file_subpath}"
        )

        download_success=false

        for mirror_url in "${MIRRORS[@]}"; do
            info "Trying mirror: $mirror_url"
            rm -f "$expected_filename"
            
            aria2c --header="User-Agent: $USER_AGENT" \
                   --header="Referer: https://sourceforge.net/" \
                   --check-certificate=false \
                   --allow-overwrite=true \
                   --auto-file-renaming=false \
                   --max-tries=2 \
                   --retry-wait=1 \
                   --timeout=15 \
                   -s16 -x16 -j16 \
                   -o "$expected_filename" \
                   "$mirror_url"

            if [ -f "$expected_filename" ]; then
                filesize=$(stat -c%s "$expected_filename" 2>/dev/null || stat -f%z "$expected_filename" 2>/dev/null || echo 0)
                if [ "$filesize" -gt 104857600 ]; then
                    download_success=true
                    baserom="$expected_filename"
                    info "Download successfully from mirror: $mirror_url"
                    break
                else
                    warn "Tải thất bại (file nhận được không hợp lệ: $filesize bytes)."
                    rm -f "$expected_filename"
                fi
            fi
        done

        if [ "$download_success" = false ]; then
            error "Tất cả các mirror của SourceForge đều bị chặn trên GitHub Runner!"
            exit 1
        fi

    # ==================== 5. LINK TẢI TRỰC TIẾP KHÁC (Gofile direct, OTA Aliyun...) ====================
    else
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

    # Bắt file zip ROM vừa tải về (ưu tiên file dung lượng lớn nhất)
    downloaded_zip=$(ls -S *.zip 2>/dev/null | head -n 1)
    if [ -n "$downloaded_zip" ] && [ -f "$downloaded_zip" ]; then
        baserom="$downloaded_zip"
    else
        error "Download error: Không tìm thấy file zip ROM hợp lệ!"
        exit 1
    fi

    info "BASEROM: ${baserom}"

elif [ -f "${baserom}" ]; then
    info "BASEROM: ${baserom}"
else
    error "BASEROM: Invalid parameter"
    exit 1
fi

# ==================== NHẬN DIỆN THÔNG TIN ROM ====================
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

# ==================== XÁC ĐỊNH KHU VỰC (REGION) ====================
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

# ==================== NHẬN DIỆN OS ====================
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
