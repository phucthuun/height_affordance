# Make a True Desktop Shortcut (No Terminal Needed!)
# If you want to open this application like any normal software app without ever touching PowerShell again:

# Right-click on your Windows Desktop, go to New > Shortcut.

# In the location box, paste this exact single-line string (which packages your exact Python executable and the script path together):

# Plaintext
# C:\Users\nguyen\AppData\Local\Python\pythoncore-3.14-64\pythonw.exe "\\mpib-berlin.mpg.de\Share\Projects\1130-id-grap\private\02_Task\height_affordance\script\s02_LSL_mouse-click.py"
# "C:\Python39\pythonw.exe" "\\mpib-berlin.mpg.de\Share\Projects\1130-id-grap\private\02_Task\height_affordance\script\s02_LSL_mouse-click.py"

# (Note: We use pythonw.exe instead of python.exe here because it hides the ugly black terminal background window, leaving only your sleek app panel visible!)

# Click Next, name the shortcut LSL Mouse Streamer, and click Finish.



import tkinter as tk
from tkinter import scrolledtext
import sys
import threading
from pylsl import StreamInfo, StreamOutlet
from pynput import mouse

class LSLMouseApp:
    def __init__(self, root):
        self.root = root
        self.root.title("LSL Global Mouse Tracker")
        self.root.geometry("500x400")
        self.root.configure(bg="#2c3e50")
        
        self.outlet = None
        self.listener = None
        self.is_streaming = False

        # --- UI LAYOUT ---
        # Title Label
        title = tk.Label(root, text="LSL Mouse Click Streamer", font=("Arial", 16, "bold"), fg="#ecf0f1", bg="#2c3e50")
        title.pack(pady=10)

        # Status Indicator
        self.status_label = tk.Label(root, text="Status: NOT STREAMING", font=("Arial", 11, "bold"), fg="#e74c3c", bg="#2c3e50")
        self.status_label.pack(pady=5)

        # Control Button
        self.btn_toggle = tk.Button(root, text="START STREAM", font=("Arial", 12, "bold"), bg="#2ecc71", fg="white", 
                                   command=self.toggle_streaming, height=2, width=20, activebackground="#27ae60")
        self.btn_toggle.pack(pady=10)

        # Console Log Label (Fixed typo from px to padx here)
        log_label = tk.Label(root, text="Live Click Log:", font=("Arial", 10), fg="#bdc3c7", bg="#2c3e50")
        log_label.pack(anchor="w", padx=20, pady=(10,0))

        # Scrolled Text Box for logs (Fixed typo from px to padx here)
        self.log_box = scrolledtext.ScrolledText(root, width=55, height=12, bg="#34495e", fg="#ecf0f1", font=("Courier New", 9))
        self.log_box.pack(pady=5, padx=20)
        self.log_message("System idle. Click 'START STREAM' to initialize LSL outlet.")

        # Protocol handle for clean window closing
        self.root.protocol("WM_DELETE_WINDOW", self.on_closing)

    def log_message(self, message):
        """Safely appends text onto the GUI display."""
        self.log_box.insert(tk.END, message + "\n")
        self.log_box.see(tk.END)

    def on_click(self, x, y, button, pressed):
        """Background background loop listener callback."""
        if pressed and self.is_streaming:
            marker_string = f"Click_{button.name.upper()}_X{x}_Y{y}"
            
            # Broadcast over LSL network
            self.outlet.push_sample([marker_string])
            
            # Print to GUI console log safely using thread-safe execution
            self.root.after(0, self.log_message, f"[SENT TO LSL] -> {marker_string}")

    def start_lsl(self):
        """Initializes LSL and begins background global mouse trapping thread."""
        try:
            info = StreamInfo('Mouse_Clicks', 'Markers', 1, 0, 'string', 'mouse_click_marker_001')
            self.outlet = StreamOutlet(info)
            
            # Start global pynput mouse listener thread
            self.listener = mouse.Listener(on_click=self.on_click)
            self.listener.start()
            
            self.root.after(0, self.update_ui_running)
        except Exception as e:
            self.root.after(0, self.log_message, f"Initialization Error: {str(e)}")

    def update_ui_running(self):
        self.status_label.config(text="Status: STREAMING LIVE", fg="#2ecc71")
        self.btn_toggle.config(text="STOP STREAM", bg="#e74c3c", activebackground="#c0392b")
        self.log_message("[SUCCESS] LSL Stream 'Mouse_Clicks' active globally across screen.")
        self.is_streaming = True

    def toggle_streaming(self):
        if not self.is_streaming:
            self.log_message("Launching stream services...")
            # Spin up LSL inside a parallel background thread so the GUI window doesn't freeze
            threading.Thread(target=self.start_lsl, daemon=True).start()
        else:
            self.stop_streaming()

    def stop_streaming(self):
        self.is_streaming = False
        if self.listener:
            self.listener.stop()
        self.status_label.config(text="Status: NOT STREAMING", fg="#e74c3c")
        self.btn_toggle.config(text="START STREAM", bg="#2ecc71", activebackground="#27ae60")
        self.log_message("[STOPPED] Stream paused. No markers will stream.")

    def on_closing(self):
        self.stop_streaming()
        self.root.destroy()
        sys.exit(0)

if __name__ == "__main__":
    root = tk.Tk()
    app = LSLMouseApp(root)
    
    # AUTO-START:
    # This waits exactly 3000 milliseconds for the window to draw itself, 
    # then automatically fires the streaming thread without requiring a mouse click!
    root.after(3000, app.toggle_streaming)
    
    root.mainloop()