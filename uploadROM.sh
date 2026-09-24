#!/usr/bin/env bash

# ========================================================
# Thiết lập thư mục gốc & nạp hàm / PATH
# ========================================================
work_dir=$(pwd)
tools_dir="${work_dir}/bin/$(uname)/$(uname -m)"
export PATH="${tools_dir}:$PATH"

if [ -f "$work_dir/functions.sh" ]; then
    source "$work_dir/functions.sh"
else
    repack() { echo "[REPACK] - $*"; }
    upload() { echo "[UPLOAD] - $*"; }
fi

# ========================================================
# Đọc các thông số thiết bị từ file tạm
# ========================================================
os_type=$(cat "$work_dir/bin/ddevice/os_type.txt" 2>/dev/null || echo "")
base_rom_code=$(cat "$work_dir/bin/ddevice/base_rom_code.txt" 2>/dev/null || echo "")
androidVER=$(cat "$work_dir/bin/ddevice/androidver.txt" 2>/dev/null || echo "")
rom_os=$(cat "$work_dir/bin/ddevice/rom_os.txt" 2>/dev/null || echo "")
regionTYPE=$(cat "$work_dir/bin/ddevice/device_type.txt" 2>/dev/null || echo "")
baserom_type=$(cat "$work_dir/bin/ddevice/romtype.txt" 2>/dev/null || echo "")

# Ưu tiên lấy Codename chuẩn viết thường (peridot)
device_f=$(cat "$work_dir/bin/ddevice/device_f.txt" 2>/dev/null || echo "")
if [[ -z "$device_f" || "$device_f" == "missing" || "$device_f" == "miproduct" ]]; then
    device_f=$(cat "$work_dir/bin/ddevice/device_code.txt" 2>/dev/null || echo "peridot")
fi
device_lower=$(echo "$device_f" | tr '[:upper:]' '[:lower:]')

if [[ -f "$work_dir/Version" ]]; then
    polyxver="$(cat "$work_dir/Version")"
else
    polyxver="1.0"
fi

if [[ "$base_rom_code" == OS* ]]; then
    true_os="HyperOS"
else
    true_os="MIUI"
fi
os_type="${os_type:-$true_os}"

target_out_dir="$work_dir/out/${os_type}_${device_lower}_${base_rom_code}"
mkdir -p "$target_out_dir/images/"

# ========================================================
# Nén super.img bằng zstd
# ========================================================
repack "Compressing super.img"
if [ -f "$work_dir/build/baserom/images/super.img" ]; then
    zstd --rm "$work_dir/build/baserom/images/super.img" -o "$work_dir/build/baserom/images/super.img.zst" > /dev/null 2>&1
elif [ -f "$work_dir/build/baserom/super.img" ]; then
    zstd --rm "$work_dir/build/baserom/super.img" -o "$work_dir/build/baserom/images/super.img.zst" > /dev/null 2>&1
fi

# ========================================================
# Gom file ảnh hệ thống & flash scripts
# ========================================================
repack "Generating flashing script"
if [[ "${baserom_type}" == 'payload' ]]; then
    mv -f "$work_dir/build/baserom/images/super.img.zst" "$target_out_dir/" 2>/dev/null || true
    mv -f "$work_dir/build/baserom/images/"*.img "$target_out_dir/images/" 2>/dev/null || true
elif [[ "${baserom_type}" == 'br' ]]; then
    mv -f "$work_dir/build/baserom/firmware-update/"* "$target_out_dir/images/" 2>/dev/null || true
    mv -f "$work_dir/build/baserom/images/super.img.zst" "$target_out_dir/" 2>/dev/null || true
else
    mv -f "$work_dir/build/baserom/images/super.img.zst" "$target_out_dir/" 2>/dev/null || true
    find "$work_dir/build/baserom/" -maxdepth 2 -type f -name "*.img" -exec mv -f {} "$target_out_dir/images/" \; 2>/dev/null || true
fi

# Sao chép flash scripts từ bin
if [ -d "$work_dir/bin/script2flash/META-INF" ]; then
    cp -rf "$work_dir/bin/script2flash/META-INF" "$target_out_dir/"
fi
cp -rf "$work_dir/bin/script2flash/"*.bat "$target_out_dir/" 2>/dev/null || true
cp -rf "$work_dir/bin/script2flash/"*.sh "$target_out_dir/" 2>/dev/null || true
cp -rf "$work_dir/bin/script2flash/cust.img" "$target_out_dir/images/" 2>/dev/null || true

mkdir -p "$target_out_dir/META-INF/Data"
echo "$device_lower" > "$target_out_dir/META-INF/Data/DeviceCode"
repack "Done"

# ========================================================
# Chuẩn hóa tên file xuất xưởng & Đóng gói ZIP
# ========================================================
find "$target_out_dir" -exec touch {} + 2>/dev/null || true

current_date=$(date +"%Y%m%d")
rom_code="$base_rom_code"

# Tự động nhận diện bản ROM xiaomi.eu qua tên URL, cờ biến hoặc file tạm
if [[ "$baserom" == *"xiaomi.eu"* || "$is_base_rom_eu" == "true" || -f "$work_dir/bin/ddevice/is_eu.txt" ]]; then
    final_zip_name="XiaomiOS_xiaomi.eu_${device_lower}_${rom_code}_mod_${current_date}.zip"
else
    final_zip_name="XiaomiOS_${device_lower}_${rom_code}_mod_${current_date}.zip"
fi

pushd "$target_out_dir" > /dev/null || exit 1
zip -r "../${final_zip_name}" ./*
popd > /dev/null || exit 1

# Dọn dẹp thư mục staging, giữ nguyên file ZIP hoàn chỉnh
rm -rf "$target_out_dir"

output_file="$work_dir/out/$final_zip_name"
repack "Build completed"
repack "Output: $output_file"

mkdir -p "$work_dir/bin/ddevice"
echo "$final_zip_name" > "$work_dir/bin/ddevice/output_zip.txt"

# Reset file URL
> "$work_dir/bin/ddevice/output_url.txt"

# ========================================================
# 1. Tải lên Pixeldrain
# ========================================================
upload "Đang kết nối API Pixeldrain..."

if [ -z "${PIXELDRAIN_API_KEY:-}" ]; then
    upload "CẢNH BÁO: Không tìm thấy PIXELDRAIN_API_KEY, upload ẩn danh..."
    AUTH_HEADER=""
else
    AUTH_HEADER="-u :${PIXELDRAIN_API_KEY}"
fi

PIXELDRAIN_LINK=""
if [ ! -f "$output_file" ]; then
    upload "LỖI: Không tìm thấy file output: $output_file"
else
    upload "Bắt đầu tải file $final_zip_name lên Pixeldrain..."
    UPLOAD_RESPONSE=$(curl -s -# -T "$output_file" $AUTH_HEADER "https://pixeldrain.com/api/file/$final_zip_name")
    PIXELDRAIN_ID=$(echo "$UPLOAD_RESPONSE" | grep -oP '"id":"\K[^"]+' | head -n 1)

    if [ -n "$PIXELDRAIN_ID" ] && [ "$PIXELDRAIN_ID" != "null" ]; then
        PIXELDRAIN_LINK="https://pixeldrain.com/u/$PIXELDRAIN_ID"
        upload "Tải lên Pixeldrain thành công!"
        echo "Pixeldrain: $PIXELDRAIN_LINK" >> "$work_dir/bin/ddevice/output_url.txt"
    else
        upload "Lỗi khi upload lên Pixeldrain: $UPLOAD_RESPONSE"
    fi
fi

# ========================================================
# 2. Tải lên Hugging Face (Strong568/XiaomiOS-ROM)
# ========================================================
upload "Đang chuẩn bị tải lên Hugging Face..."

pip install -q --no-cache-dir huggingface_hub

HF_REPO_ID="Strong568/XiaomiOS-ROM"
HF_REPO_TYPE="model"
HF_DIRECT_URL="https://huggingface.co/${HF_REPO_ID}/resolve/main/releases/${final_zip_name}"
HF_LINK=""

if [ -z "${HF_TOKEN:-}" ]; then
    upload "CẢNH BÁO: Không tìm thấy biến môi trường HF_TOKEN, bỏ qua bước upload Hugging Face."
else
    if [ ! -f "$output_file" ]; then
        upload "LỖI: Không tìm thấy file output: $output_file"
    else
        upload "Bắt đầu tải file $final_zip_name lên Hugging Face ($HF_REPO_ID)..."

        python3 - <<EOF
import os
import sys
from huggingface_hub import HfApi

hf_token = os.environ.get("HF_TOKEN")
file_path = "$output_file"
file_name = "$final_zip_name"
repo_id = "$HF_REPO_ID"
repo_type = "$HF_REPO_TYPE"

api = HfApi(token=hf_token)

try:
    api.upload_file(
        path_or_fileobj=file_path,
        path_in_repo=f"releases/{file_name}",
        repo_id=repo_id,
        repo_type=repo_type,
    )
    print("\n[UPLOAD SUCCESS] File đã tải lên Hugging Face thành công!")
except Exception as e:
    print(f"\n[UPLOAD ERROR] Hugging Face thất bại: {e}", file=sys.stderr)
    sys.exit(1)
EOF

        if [ $? -eq 0 ]; then
            HF_LINK="$HF_DIRECT_URL"
            upload "Tải lên Hugging Face thành công!"
            echo "HuggingFace: $HF_LINK" >> "$work_dir/bin/ddevice/output_url.txt"
        else
            upload "Upload Hugging Face thất bại!"
        fi
    fi
fi

# ========================================================
# Dọn dẹp môi trường & Hiển thị liên kết
# ========================================================
upload "Cleaning build temporary files..."
rm -rf "$work_dir/build"

upload "=============================================="
upload "Build ${os_type} for ${device_lower} hoàn tất!"
[ -n "$PIXELDRAIN_LINK" ] && upload "Pixeldrain : $PIXELDRAIN_LINK"
[ -n "$HF_LINK" ]          && upload "Hugging Face: $HF_LINK"
upload "=============================================="
