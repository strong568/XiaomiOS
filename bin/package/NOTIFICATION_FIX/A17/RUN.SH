work_dir=$(pwd)
MAIN_FOLDER="$work_dir/build/baserom/images/"
bash $work_dir/bin/package/NOTIFICATION_FIX/A17/PowerKeeper.sh
bash $work_dir/bin/package/NOTIFICATION_FIX/A17/patchMIUIServices.sh
