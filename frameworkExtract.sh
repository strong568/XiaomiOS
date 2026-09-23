#!/usr/bin/env bash
set -e

work_dir=$(pwd)
base_img_dir="$work_dir/build/baserom/images"
extract_dir="$work_dir/framework_dump"
output_dir="$work_dir/out_artifacts"

# $1: Nhãn (stock hoặc mod), mặc định là generic
STAGE_TAG="${1:-dump}"
# $2: URL của ROM (hoặc lấy từ biến môi trường INPUT_URL)
ROM_URL="${2:-$INPUT_URL}"

# Chuyển tag thành in hoa (STOCK / MOD)
TAG_UPPER=$(echo "$STAGE_TAG" | tr '[:lower:]' '[:upper:]')

echo "[EXTRACT] Bắt đầu trích xuất Framework cho giai đoạn: [$TAG_UPPER]..."

# Dọn dẹp thư mục tạm của lần trích xuất này
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
mkdir -p "$output_dir"

# Danh sách file cần lấy
declare -A FILES_TO_COPY=(
    ["system/framework/framework.jar"]="system/framework/framework.jar"
    ["system/framework/services.jar"]="system/framework/services.jar"
    ["system/build.prop"]="system/build.prop"
    ["system_ext/framework/miui-framework.jar"]="system_ext/framework/miui-framework.jar"
    ["system_ext/framework/miui-services.jar"]="system_ext/framework/miui-services.jar"
    ["system_ext/etc/build.prop"]="system_ext/etc/build.prop"
    ["system_ext/etc/cust_prop_white_keys_list"]="system_ext/etc/cust_prop_white_keys_list"
)

for rel_path in "${!FILES_TO_COPY[@]}"; do
    src_file="$base_img_dir/$rel_path"
    dest_file="$extract_dir/$rel_path"

    # Kiểm tra trường hợp phân vùng lồng system/system
    if [ ! -f "$src_file" ] && [[ "$rel_path" == system/* ]]; then
        alt_path="system/${rel_path}"
        if [ -f "$base_img_dir/$alt_path" ]; then
            src_file="$base_img_dir/$alt_path"
        fi
    fi

    if [ -f "$src_file" ]; then
        mkdir -p "$(dirname "$dest_file")"
        cp -f "$src_file" "$dest_file"
        echo "[FOUND] -> $rel_path"
    else
        echo "[WARNING] Không tìm thấy file: $src_file"
    fi
done

# ==================== ĐẶT TÊN FILE ZIP ====================
raw_filename=$(basename "${ROM_URL%%\?*}")

if [[ "$raw_filename" =~ \.zip$ ]]; then
    zip_name="Framework_${TAG_UPPER}_${raw_filename}"
else
    device_f=$(cat "$work_dir/bin/ddevice/device_f.txt" 2>/dev/null || echo "device")
    current_date=$(date +"%Y%m%d_%H%M%S")
    zip_name="Framework_${TAG_UPPER}_${device_f}_${current_date}.zip"
fi

# ==================== ĐÓNG GÓI ZIP ====================
if [ -d "$extract_dir" ] && [ "$(ls -A "$extract_dir")" ]; then
    pushd "$extract_dir" > /dev/null
    zip -r "$output_dir/$zip_name" ./*
    popd > /dev/null
    rm -rf "$extract_dir"

    echo "[SUCCESS] Đã nén thành công: $output_dir/$zip_name"
    
    # Xuất biến ra GitHub Env (phân theo nhãn để không ghi đè nhau)
    if [ -n "$GITHUB_ENV" ]; then
        echo "DUMP_${TAG_UPPER}_PATH=$output_dir/$zip_name" >> "$GITHUB_ENV"
        echo "DUMP_${TAG_UPPER}_NAME=$zip_name" >> "$GITHUB_ENV"
    fi
else
    echo "[ERROR] Không có file nào được trích xuất tại bước $TAG_UPPER!"
    exit 1
fi
