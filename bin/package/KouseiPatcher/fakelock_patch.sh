#!/bin/bash
# SPDX-License-Identifier: GPL-3.0

work_dir=$(pwd)
magiskboot="$work_dir/bin/magiskboot"
prop="$work_dir/bin/package/KouseiPatcher/prop"
SEARCH_DIR="build/baserom/images"

# 1. Patch vendor_boot.img (chỉ bổ sung cờ fake lock vào cuối cmdline)
if [ -f "$work_dir/$SEARCH_DIR/vendor_boot.img" ]; then 
  echo "[IMGPATCH] - PATCHING vendor_boot.img"
  mkdir -p "$work_dir/temp_boot"

  echo "[IMGPATCH] - Stage 1 Patching..."
  cp -rf "$work_dir/$SEARCH_DIR/vendor_boot.img" "$work_dir"
  cp -rf "$work_dir/$SEARCH_DIR/vendor_boot.img" "$work_dir/temp_boot"
  
  $magiskboot unpack -h "$work_dir/vendor_boot.img" >/dev/null 2>&1

  # Chỉ nối các cờ androidboot cần thiết vào cuối cmdline hiện có
  sed -i '/^cmdline=/ s/$/ androidboot.verifiedbootstate=green androidboot.flash.locked=1 androidboot.vbmeta.device_state=locked/' "$work_dir/header"

  echo "[IMGPATCH] - Stage 2 Patching..."
  $magiskboot repack "$work_dir/vendor_boot.img" >/dev/null 2>&1
  mv "$work_dir/new-boot.img" "$work_dir/vendor_boot.img"

  echo "[IMGPATCH] - Stage 3 Cleanup..."
  rm -rf "$work_dir/dtb" "$work_dir/header" "$work_dir/ramdisk.cpio"
  rm -rf "$work_dir/$SEARCH_DIR/vendor_boot.img"
  mv "$work_dir/vendor_boot.img" "$work_dir/$SEARCH_DIR"

  if [ -f "$work_dir/$SEARCH_DIR/vendor_boot.img" ]; then
    echo "[IMGPATCH] - Patched vendor_boot.img successfully!"
    rm -rf "$work_dir/temp_boot"
  else
    echo "[IMGPATCH] - Failed to patch vendor_boot.img! Reverting..."
    mv "$work_dir/temp_boot/vendor_boot.img" "$work_dir/$SEARCH_DIR"
    rm -rf "$work_dir/temp_boot"
  fi
fi

# 2. Xử lý XEUToolbox cho API < 33
BUILD_PROP=$(find "$SEARCH_DIR" -type f -name "build.prop" | head -n 1)
if [ -n "$BUILD_PROP" ]; then
  first_api=$(grep "ro.product.first_api_level" "$BUILD_PROP" | awk 'NR==1' | cut -d '=' -f 2 | tr -d ' \r')
  if [ -n "$first_api" ] && [ "$first_api" -lt 33 ]; then
    mods "API lower than 33! Inject XEUToolbox by Xiaomi.eu"
    echo "/system_ext/xbin/xeu_toolbox  u:object_r:toolbox_exec:s0" >> build/baserom/images/config/system_ext_file_contexts
    echo "/system_ext/xbin/xeu_toolbox  u:object_r:toolbox_exec:s0" >> build/baserom/images/system_ext/etc/selinux/system_ext_file_contexts
    echo "(allow init toolbox_exec (file ((execute_no_trans))))" >> build/baserom/images/system_ext/etc/selinux/system_ext_sepolicy.cil
    cp -rf "$work_dir/bin/package/KouseiPatcher/bin/xeu_toolbox/"* "$work_dir/build/baserom/images/system_ext"
    mods "Done!"
  fi
fi

# 3. Nối build.prop
if [ -f "$prop/build.prop" ]; then
  cat "$prop/build.prop" >> "$work_dir/$SEARCH_DIR/system/system/build.prop"
fi

# 4. Quét và inject cust.prop vào tất cả file cust_prop_white_keys_list (bỏ check sdkLevel)
echo "[IMGPATCH] - Scanning for cust_prop_white_keys_list..."
if [ -f "$prop/cust.prop" ]; then
  find "$SEARCH_DIR" -type f -name "cust_prop_white_keys_list" | while read -r target_file; do
    cat "$prop/cust.prop" >> "$target_file"
    echo "[IMGPATCH] - Injected cust.prop into: $target_file"
  done
fi

# 5. Ép đổi thông số ROM gốc thành BugOS 1.0 trên toàn bộ ROM
echo "[IMGPATCH] - Renaming OS to BugOS 1.0..."

# Đổi biến hiển thị tên phiên bản trong Giới thiệu điện thoại
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.build.display.id=.*/ro.build.display.id=BugOS 1.0/g' {} +

# Đổi mã phiên bản cập nhật (incremental)
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.build.version.incremental=.*/ro.build.version.incremental=1.0/g' {} +

# Đổi tên giao diện người dùng
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.miui.ui.version.name=.*/ro.miui.ui.version.name=BugOS/g' {} +

# Đổi tên người build và máy chủ build
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.build.user=.*/ro.build.user=BugOS/g' {} +
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.build.host=.*/ro.build.host=BugOS-Team/g' {} +
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/^ro.build.flavor=.*/ro.build.flavor=BugOS/g' {} +

# Thay thế các cụm từ hiển thị rõ ràng của Xiaomi thành "BugOS"
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/Xiaomi HyperOS/BugOS/g' {} +
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/Xiaomi MIUI/BugOS/g' {} +
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/MIUI Global/BugOS/g' {} +

# "Nhuộm" chữ MIUI thành BugOS (Tuyệt chiêu: CHỈ đổi chữ MIUI nằm SAU dấu "=" để không làm hỏng biến hệ thống ro.miui.*)
find "$SEARCH_DIR" -type f -name "*.prop" -exec sed -i 's/\(=.*\)MIUI/\1BugOS/g' {} +

patch "Done"
