#!/bin/bash
work_dir=$(pwd)
source $work_dir/functions.sh

FILE_JSON="$work_dir/bin/ddevice/data/devices.json"
KEY="${1:-$(cat $work_dir/bin/ddevice/device_f.txt)}"

# Find the exact key with correct capitalization from the reference lists
EXACT_KEY=$(grep -ix "$KEY" "$work_dir/bin/ddevice/data/devices_data.txt" 2>/dev/null || grep -ix "$KEY" "$work_dir/bin/ddevice/data/pad_data.txt" 2>/dev/null)

if [ -z "$EXACT_KEY" ]; then
  # Fallback to key itself if not matched in the lists
  EXACT_KEY="$KEY"
fi

VALUE=$(jq -r --arg key "$EXACT_KEY" '.[$key] // "Không tìm thấy key"' "$FILE_JSON")

# FIX: build.sh (va cac script khac) doc ten thiet bi tu device_name.txt,
# nhung ban cu chi ghi vao name_devices.txt nen ten khong bao gio duoc cap nhat.
# Ghi ca 2 file de dam bao tuong thich voi moi noi dang doc.
echo "$VALUE" > $work_dir/bin/ddevice/name_devices.txt

if [[ "$VALUE" != "Không tìm thấy key" && -n "$VALUE" ]]; then
    echo "$VALUE" > $work_dir/bin/ddevice/device_name.txt
else
    warn "Khong tim thay ten thiet bi cho key '$KEY' (EXACT_KEY='$EXACT_KEY') trong devices.json"
fi
