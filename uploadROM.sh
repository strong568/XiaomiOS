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

# ========================================================
# Tải lên Pixeldrain
# ========================================================
upload "Đang kết nối API Pixeldrain..."

if [ -z "${PIXELDRAIN_API_KEY:-}" ]; then
    upload "CANH BAO: Khong tim thay PIXELDRAIN_API_KEY, upload an danh (anonymous)..."
    AUTH_HEADER=""
else
    AUTH_HEADER="-u :${PIXELDRAIN_API_KEY}"
fi

if [ ! -f "$output_file" ]; then
    upload "LOI: Khong tim thay file output: $output_file"
    echo "" > "$work_dir/bin/ddevice/output_url.txt"
else
    upload "Bắt đầu tải file $final_zip_name lên Pixeldrain..."
    
    UPLOAD_RESPONSE=$(curl -s -# -T "$output_file" $AUTH_HEADER "https://pixeldrain.com/api/file/$final_zip_name")
    PIXELDRAIN_ID=$(echo "$UPLOAD_RESPONSE" | grep -oP '"id":"\K[^"]+' | head -n 1)

    if [ -n "$PIXELDRAIN_ID" ] && [ "$PIXELDRAIN_ID" != "null" ]; then
        PIXELDRAIN_LINK="https://pixeldrain.com/u/$PIXELDRAIN_ID"
        upload "Tải lên Pixeldrain thành công! Link: $PIXELDRAIN_LINK"
        echo "$PIXELDRAIN_LINK" > "$work_dir/bin/ddevice/output_url.txt"
    else
        upload "Lỗi khi upload lên Pixeldrain. Phản hồi: $UPLOAD_RESPONSE"
        echo "" > "$work_dir/bin/ddevice/output_url.txt"
    fi
fi

# ========================================================
# Dọn dẹp môi trường (Giữ thư mục out/ cho Artifact/Release)
# ========================================================
upload "Cleaning build temporary files..."
rm -rf "$work_dir/build"

upload "Build ${os_type} for ${device_lower} successful!"
if [ -n "${PIXELDRAIN_LINK:-}" ]; then
    upload "Download: $PIXELDRAIN_LINK"
fi
