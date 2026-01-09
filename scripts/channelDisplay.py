import time
import json
import os
import tm1637

display = tm1637.TM1637(clk=26, dio=21)
status_file = "/home/analog/FieldStation42/runtime/play_status.socket"

last_value = None
last_mtime = 0

print("TM1637 channel display monitor started.")

while True:
    try:
        mtime = os.path.getmtime(status_file)
        if mtime != last_mtime:
            with open(status_file, "r") as f:
                data = json.load(f)
            channel_num = data.get("channel_number")
            if channel_num is not None:
                if channel_num != last_value:
                    ch_num = int(channel_num)
                    disp_str = f"Ch0{ch_num}" if ch_num < 10 else f"Ch{ch_num}"
                    disp_str = disp_str[:4]
                    display.show(disp_str)
                    print(f"Display updated to '{disp_str}'")
                    last_value = channel_num
            last_mtime = mtime
    except FileNotFoundError:
        print(f"Error: File '{status_file}' not found.")
    except json.JSONDecodeError:
        print(f"Error: Could not decode JSON from '{status_file}'.")
    except Exception as e:
        print(f"Unexpected error: {e}")
    time.sleep(1)
