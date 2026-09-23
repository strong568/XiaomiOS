import os
import sys
import requests
import random
import string
import json

# Đảm bảo mã hóa UTF-8 cho stdout và stderr
if hasattr(sys.stdout, 'reconfigure'):
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
if hasattr(sys.stderr, 'reconfigure'):
    try:
        sys.stderr.reconfigure(encoding='utf-8')
    except Exception:
        pass

def read_file_if_exists(path, default=""):
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as f:
                val = f.read().strip()
                return val if val else default
        except Exception:
            return default
    return default

def get_status_info(status):
    status = status.lower()
    if status == 'start': 
        return "[ 5% ]"
    if status == 'download': 
        return "[ 15% ]"
    if status == 'unpack': 
        return "[ 30% ]"
    if status == 'build': 
        return "[ 60% ]"
    if status == 'pack': 
        return "[ 85% ]"
    if status == 'upload': 
        return "[ 95% ]"
    if status == 'success': 
        return "HOÀN TẤT"
    if status == 'fail': 
        return "THẤT BẠI"
    
    return f"[ {status} ]"

def is_available(value):
    if not value:
        return False
    val_lower = value.strip().lower()
    if val_lower in ["", "chưa rõ", "unknown", "đang xác định...", "⏳ đang quét..."]:
        return False
    return True

def send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id=None, build_id="Unknown", builder_name="", builder_id=""):
    progress_text = get_status_info(status)

    codename = read_file_if_exists("bin/ddevice/device_code.txt")
    if not codename:
        codename = read_file_if_exists("bin/ddevice/device_model.txt")
    if is_available(codename):
        codename = codename.capitalize()
    else:
        codename = "Unknown"

    device_name = read_file_if_exists("bin/ddevice/name_devices.txt")
    if not is_available(device_name):
        device_name = "Đang xác định..."

    version_rom = read_file_if_exists("bin/ddevice/rom_version.txt")
    if not version_rom:
        version_rom = read_file_if_exists("bin/ddevice/base_rom_code.txt")
    if not is_available(version_rom):
        version_rom = "Đang xác định..."
        
    android_ver = read_file_if_exists("bin/ddevice/androidver.txt")
    sdk_level = read_file_if_exists("bin/ddevice/sdkLevel.txt")
    
    android_text = ""
    if is_available(android_ver):
        android_text += f"Android {android_ver}"
    if is_available(sdk_level):
        if android_text:
            android_text += f" | SDK {sdk_level}"
        else:
            android_text += f"SDK {sdk_level}"
            
    if not android_text:
        android_text = "Đang xác định..."

    version_tool = read_file_if_exists("Version")
    if not is_available(version_tool):
        version_tool = "BugOS 1.0"
        
    builder_text = builder_name if builder_name else os.environ.get("GITHUB_ACTOR", "iabi")

    # Xây dựng nội dung tin nhắn HTML
    message = f"""👾 <b>TIẾN TRÌNH BUILD ROM</b>
<code>──────────────────────────────</code>
👤 Người thực hiện: {builder_text}
📍 Device: {device_name}
🛠 Phiên bản: {version_tool}
📱 Codename: {codename}
💿 Hệ điều hành: {version_rom}
🤖 Android: {android_text}
<code>──────────────────────────────</code>
📈 Tiến trình: {progress_text}
🆔 Build ID: {build_id}"""

    if is_available(rom_link) and rom_link.startswith("http"):
        message += f"\n🔗 Base ROM (Nguồn): <a href='{rom_link}'>Link</a>"
    else:
         message += f"\n🔗 Base ROM (Nguồn): Đang lấy link..."

    # Khởi tạo Payload gửi lên Telegram
    payload = {
        "chat_id": channel_id,
        "text": message,
        "parse_mode": "HTML",
        "disable_web_page_preview": True
    }

    if msg_id:
        payload["message_id"] = msg_id
        url = f"https://api.telegram.org/bot{bot_token}/editMessageText"
    else:
        url = f"https://api.telegram.org/bot{bot_token}/sendMessage"

    # NẾU BUILD THÀNH CÔNG -> THÊM NÚT BẤM (INLINE KEYBOARD)
    if status.lower() == 'success':
        output_zip = read_file_if_exists("bin/ddevice/output_url.txt")
        if is_available(output_zip) and output_zip.startswith("http"):
            reply_markup = {
                "inline_keyboard": [
                    [
                        {"text": "📦 TẢI XUỐNG ROM", "url": output_zip}
                    ]
                ]
            }
            # Gắn nút bấm vào Payload
            payload["reply_markup"] = json.dumps(reply_markup)

    try:
        response = requests.post(url, json=payload)
        response.raise_for_status()
        res_data = response.json()
        
        new_msg_id = res_data.get('result', {}).get('message_id')
        
        if not msg_id and new_msg_id and "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_MSG_ID={new_msg_id}\n")
            print(f"Đã lưu TELEGRAM_MSG_ID={new_msg_id} vào GITHUB_ENV để tự động update tin nhắn.")
            
        print("Đã gửi/cập nhật thông báo lên kênh thành công!")

    except Exception as e:
        print(f"Lỗi khi gửi thông báo: {e}")
        if 'response' in locals():
            print(response.text)

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("Sử dụng: python notify.py <status> <repo_name> <rom_link> [prefix_id] [builder_name] [builder_id]")
        sys.exit(1)

    status = sys.argv[1]
    repo_name = sys.argv[2]
    rom_link = sys.argv[3]
    
    prefix = sys.argv[4] if len(sys.argv) > 4 else "build"
    builder_name = sys.argv[5] if len(sys.argv) > 5 else ""
    builder_id = sys.argv[6] if len(sys.argv) > 6 else ""
    
    bot_token = os.environ.get("TELEGRAM_BOT_TOKEN")
    channel_id = os.environ.get("TELEGRAM_CHANNEL_ID")
    msg_id = os.environ.get("TELEGRAM_MSG_ID") 
    build_id = os.environ.get("TELEGRAM_BUILD_ID")

    if not build_id:
        random_digits = ''.join(random.choices(string.digits, k=8))
        build_id = f"{random_digits}"
        
        if "GITHUB_ENV" in os.environ:
            with open(os.environ["GITHUB_ENV"], "a", encoding="utf-8") as f:
                f.write(f"TELEGRAM_BUILD_ID={build_id}\n")

    if not bot_token or not channel_id:
        print("Lỗi: Thiếu TELEGRAM_BOT_TOKEN hoặc TELEGRAM_CHANNEL_ID trong biến môi trường.")
        sys.exit(1)

    send_notification(status, repo_name, rom_link, channel_id, bot_token, msg_id, build_id, builder_name, builder_id)
    
