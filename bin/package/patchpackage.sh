work_dir=$(pwd)
source $work_dir/functions.sh

mods "Add Package..."
target_dir="$work_dir/bin/package/"

# Đã vô hiệu hóa Core Patch trên tất cả các phiên bản Android
# bash $target_dir/COREPATCH/update.sh

bash $target_dir/DISABLE_AVB/DISABLEavb.sh
bash $target_dir/KouseiPatcher/update.sh
bash $target_dir/NOTIFICATION_FIX/notificationFIX.sh
bash $target_dir/RefreshRate/1hz.sh

mods "Add Package Done"
