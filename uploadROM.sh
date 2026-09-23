Work_dir=$(pwd)
source $work_dir/functions.sh

os_type=$(cat $work_dir/bin/ddevice/os_type.txt 2>/dev/null)
base_rom_code=$(cat $work_dir/bin/ddevice/base_rom_code.txt 2>/dev/null)
androidVER=$(cat $work_dir/bin/ddevice/androidver.txt 2>/dev/null)
rom_os=$(cat $work_dir/bin/ddevice/rom_os.txt 2>/dev/null)
regionTYPE=$(cat $work_dir/bin/ddevice/device_type.txt 2>/dev/null)
baserom_type=$(cat $work_dir/bin/ddevice/romtype.txt 2>/dev/null)

# ƯU TIÊN LẤY CODENAME CHUẨN ĐÃ ĐƯỢC XỬ LÝ
device_f=$(cat $work_dir/bin/ddevice/device_f.txt 2>/dev/null)
if [[ -z "$device_f" || "$device_f" == "missing" ]]; then
    device_f=$(cat $work_dir/bin/ddevice/device_code.txt 2>/dev/null)
fi
device_code="$device_f"

if [[ $(git branch --show-current) == "beta" ]]; then
    polyxver="$(cat Version)"
    status="Development"
else
    polyxver="$(cat Version)"
    status="UnOfficial"
fi

# ========================================================
# LOGIC NHẬN DIỆN HỆ ĐIỀU HÀNH CHUẨN XÁC 100%
if [[ "$base_rom_code" == OS* ]]; then
    true_os="HyperOS"
else
    true_os="MIUI"
fi

os_type=$true_os
# ========================================================

target_out_dir="$work_dir/out/${os_type}_${device_f}_${base_rom_code}"
mkdir -p "$target_out_dir/images/"

repack "Compressing super.img"
if [ -f "$work_dir/build/baserom/images/super.img" ]; then
    zstd --rm $work_dir/build/baserom/images/super.img -o $work_dir/build/baserom/images/super.img.zst > /dev/null 2>&1
elif [ -f "$work_dir/build/baserom/super.img" ]; then
    zstd --rm $work_dir/build/baserom/super.img -o $work_dir/build/baserom/images/super.img.zst > /dev/null 2>&1
fi

repack "Generating flashing script"
# Gom file ảnh hệ thống theo từng kiểu ROM nguồn
if [[ ${baserom_type} == 'payload' ]]; then
    mv -f $work_dir/build/baserom/images/super.img.zst "$target_out_dir/" 2>/dev/null || true
    mv -f $work_dir/build/baserom/images/*.img "$target_out_dir/images/" 2>/dev/null || true
elif [[ ${baserom_type} == 'br' ]]; then
    mv -f $work_dir/build/baserom/firmware-update/* "$target_out_dir/images/" 2>/dev/null || true
    mv -f $work_dir/build/baserom/images/super.img.zst "$target_out_dir/" 2>/dev/null || true
else
    # Nhánh cho Xiaomi.eu hoặc các bản build trích xuất super.img
    mv -f $work_dir/build/baserom/images/super.img.zst "$target_out_dir/" 2>/dev/null || true
    # Chuyển toàn bộ các partition img đi kèm (boot, dtbo, vendor_boot, cust...)
    find $work_dir/build/baserom/ -maxdepth 2 -type f -name "*.img" -exec mv -f {} "$target_out_dir/images/" \; 2>/dev/null || true
fi

# Generate dynamic script flash
cp -rf $work_dir/bin/script2flash/META-INF "$target_out_dir/"
cp -rf $work_dir/bin/script2flash/*.bat "$target_out_dir/" 2>/dev/null || true
cp -rf $work_dir/bin/script2flash/*.sh "$target_out_dir/" 2>/dev/null || true
cp -rf $work_dir/bin/script2flash/cust.img "$target_out_dir/images/" 2>/dev/null || true

mkdir -p "$target_out_dir/META-INF/Data"
echo "$device_f" > "$target_out_dir/META-INF/Data/DeviceCode"
repack "Done"

find "$target_out_dir" | xargs touch
pushd "$target_out_dir/" || exit
zip -r "${os_type}_${device_f}_${base_rom_code}.zip" ./*
mv "${os_type}_${device_f}_${base_rom_code}.zip" ../
popd || exit

# 1. Lấy ngày tháng năm hiện tại (YYYYMMDD)
current_date=$(date +"%Y%m%d")

# 2. In hoa tên thiết bị (ví dụ: onyx -> ONYX)
device_upper=$(echo "$device_f" | tr '[:lower:]' '[:upper:]')

# 3. Xóa chữ "OS" ở đầu mã ROM (ví dụ: OS3.0.305.0 -> 3.0.305.0)
clean_rom_code=${base_rom_code#OS}

# 4. Ghép thành tên file chuẩn theo yêu cầu
final_zip_name="BugOS_1.0_${device_upper}_${clean_rom_code}_${current_date}.zip"

# Đổi tên file zip
mv "out/${os_type}_${device_f}_${base_rom_code}.zip" "out/$final_zip_name"

repack "Build completed"
repack "Output: $(pwd)/out/$final_zip_name"
output_file="out/$final_zip_name"
echo "$final_zip_name" > $work_dir/bin/ddevice/output_zip.txt

# ============================================================
# Tải lên Pixeldrain (Lấy link tải xuất ra output_url.txt)
# ============================================================
upload "Đang kết nối API Pixeldrain..."

if [ -z "${PIXELDRAIN_API_KEY:-}" ]; then
    upload "CANH BAO: Bien PIXELDRAIN_API_KEY chua duoc set, tien hanh upload an danh (anonymous)..."
    AUTH_HEADER=""
else
    AUTH_HEADER="-u :${PIXELDRAIN_API_KEY}"
fi

if [ ! -f "$output_file" ]; then
    upload "LOI: Khong tim thay file output: $output_file"
    echo "" > $work_dir/bin/ddevice/output_url.txt
else
    upload "Bắt đầu tải file $final_zip_name lên Pixeldrain..."
    
    # Upload qua API Pixeldrain (PUT request qua Basic Auth)
    UPLOAD_RESPONSE=$(curl -s -# -T "$output_file" $AUTH_HEADER "https://pixeldrain.com/api/file/$final_zip_name")
    
    # Bóc tách ID file từ JSON response
    PIXELDRAIN_ID=$(echo "$UPLOAD_RESPONSE" | grep -oP '"id":"\K[^"]+' | head -n 1)

    if [ -n "$PIXELDRAIN_ID" ] && [ "$PIXELDRAIN_ID" != "null" ]; then
        PIXELDRAIN_LINK="https://pixeldrain.com/u/$PIXELDRAIN_ID"
        upload "Tải lên Pixeldrain thành công! Link: $PIXELDRAIN_LINK"
        
        # Ghi link vào output_url.txt để notify.py tự lấy gửi đi
        echo "$PIXELDRAIN_LINK" > $work_dir/bin/ddevice/output_url.txt
    else
        upload "Lỗi khi upload lên Pixeldrain. Phản hồi: $UPLOAD_RESPONSE"
        echo "" > $work_dir/bin/ddevice/output_url.txt
    fi
fi

upload "Clean Workflow.."
rm -rf $work_dir/out
rm -rf $work_dir/build

upload "Build ${os_type}_${polyxver} for ${device_f} successful!"
if [ -n "$PIXELDRAIN_LINK" ]; then
    upload "Download: $PIXELDRAIN_LINK"
fi
