#!/bin/bash
# Bash wrapper that runs the embedded Python Tkinter app
exec python3 - <<'END_PYTHON'

#!/usr/bin/env python3

import os
import subprocess
import tkinter as tk
from tkinter import ttk, filedialog
from tkinter import messagebox
import shutil
import threading
import glob

HOME = os.path.expanduser("~")
DEFAULT_COMPATDATA = os.path.join(HOME, ".steam/steam/steamapps/compatdata")
DEFAULT_STEAMAPPS = os.path.join(HOME, ".steam/steam/steamapps")


class ProtonManager:

    def __init__(self, root):
        self.root = root
        root.title("Steam Proton Prefix Manager")

        self.compatdata_path = tk.StringVar(value=DEFAULT_COMPATDATA)
        self.search_var = tk.StringVar()

        self.prefix_cache = []

        self.build_ui()
        self.scan_prefixes()

    # ---------------- UI ----------------

    def add_context_menu(self, widget):

        menu = tk.Menu(self.root, tearoff=0)

        menu.add_command(label="Cut", command=lambda: widget.event_generate("<<Cut>>"))
        menu.add_command(label="Copy", command=lambda: widget.event_generate("<<Copy>>"))
        menu.add_command(label="Paste", command=lambda: widget.event_generate("<<Paste>>"))
        menu.add_separator()
        menu.add_command(label="Select All", command=lambda: widget.select_range(0, 'end'))

        def show_menu(event):
            widget.focus_set()
            menu.tk_popup(event.x_root, event.y_root)

        widget.bind("<Button-3>", show_menu)

    def build_ui(self):

        top = ttk.Frame(self.root)
        top.pack(fill="x", padx=10, pady=5)

        ttk.Label(top, text="Compatdata").pack(side="left")

        path_entry = ttk.Entry(top, textvariable=self.compatdata_path, width=45)
        path_entry.pack(side="left", padx=5)
        self.add_context_menu(path_entry)

        ttk.Button(top, text="Browse", command=self.browse).pack(side="left")
        ttk.Button(top, text="Scan", command=self.scan_prefixes).pack(side="left", padx=5)

        search_frame = ttk.Frame(self.root)
        search_frame.pack(fill="x", padx=10)

        ttk.Label(search_frame, text="Search").pack(side="left")

        search_entry = ttk.Entry(search_frame, textvariable=self.search_var)
        search_entry.pack(side="left", fill="x", expand=True, padx=5)
        search_entry.bind("<KeyRelease>", self.filter_list)

        self.add_context_menu(search_entry)

        columns = ("AppID", "Game Name", "Proton", "Prefix Size")

        self.tree = ttk.Treeview(self.root, columns=columns, show="headings")

        for col in columns:
            self.tree.heading(col, text=col)
            self.tree.column(col, anchor="w")

        self.tree.pack(fill="both", expand=True, padx=10, pady=5)

        buttons = ttk.Frame(self.root)
        buttons.pack(pady=5)

        # Added Run EXE Button
        ttk.Button(buttons, text="Run EXE", command=self.run_exe).pack(side="left", padx=6)
        ttk.Button(buttons, text="Browse Prefix Dir", command=self.open_prefix).pack(side="left", padx=6)
        ttk.Button(buttons, text="Browse Game Dir", command=self.open_game_dir).pack(side="left", padx=6)
        ttk.Button(buttons, text="Convert WMV", command=self.convert_wmv).pack(side="left", padx=6)
        ttk.Button(buttons, text="Convert WMV Audio", command=self.convert_wmv_audio).pack(side="left", padx=6)
        ttk.Button(buttons, text="Delete Prefix", command=self.delete_prefix).pack(side="left", padx=6)

    # ---------------- Progress Window ----------------

    def show_progress_window(self, total):

        self.progress_win = tk.Toplevel(self.root)
        self.progress_win.title("Conversion Progress")
        self.progress_win.geometry("700x400")

        self.progress_total = total
        self.progress_count = 0

        self.progress_var = tk.DoubleVar()

        self.progress_bar = ttk.Progressbar(
            self.progress_win,
            maximum=total,
            variable=self.progress_var
        )

        self.progress_bar.pack(fill="x", padx=10, pady=10)

        frame = ttk.Frame(self.progress_win)
        frame.pack(fill="both", expand=True, padx=10, pady=5)

        scrollbar = ttk.Scrollbar(frame)
        scrollbar.pack(side="right", fill="y")

        self.log = tk.Text(frame, yscrollcommand=scrollbar.set)
        self.log.pack(fill="both", expand=True)

        scrollbar.config(command=self.log.yview)

    def log_message(self, msg):

        self.log.insert("end", msg + "\n")
        self.log.see("end")
        self.log.update_idletasks()

    def increment_progress(self):

        self.progress_count += 1
        self.progress_var.set(self.progress_count)

    # ---------------- EXE Runner ----------------

    def run_exe(self):
        item = self.get_selected()
        if not item:
            messagebox.showwarning("No Selection", "Select a game first.")
            return

        appid = item[0]
        prefix_dir = os.path.join(self.compatdata_path.get(), str(appid), "pfx")

        exe_path = filedialog.askopenfilename(
            title="Select EXE to run",
            filetypes=[("Executables", "*.exe"), ("All Files", "*.*")]
        )
        if not exe_path:
            return

        # Look for a Proton installation to find 'wine'
        proton_dirs = glob.glob(os.path.join(DEFAULT_STEAMAPPS, "common", "Proton*"))
        proton_dirs.sort(reverse=True)

        wine_path = None
        for p_dir in proton_dirs:
            # Typical path for wine in Proton
            target = os.path.join(p_dir, "files", "bin", "wine")
            if os.path.exists(target):
                wine_path = target
                break

        if not wine_path:
            messagebox.showerror("Error", "Could not find a Proton 'wine' binary in SteamApps/common.")
            return

        # Setup environment
        env = os.environ.copy()
        env["WINEPREFIX"] = prefix_dir

        try:
            subprocess.Popen([wine_path, exe_path], env=env, cwd=os.path.dirname(exe_path))
        except Exception as e:
            messagebox.showerror("Error", f"Failed to launch: {e}")

    # ---------------- WMV Converter ----------------

    def convert_wmv(self):

        item = self.get_selected()

        if not item:
            messagebox.showwarning("No Selection", "Select a game first.")
            return

        appid = item[0]

        manifest = os.path.join(
            os.path.dirname(self.compatdata_path.get()),
            f"appmanifest_{appid}.acf"
        )

        if not os.path.exists(manifest):
            messagebox.showerror("Error", "App manifest not found.")
            return

        installdir = None

        try:
            with open(manifest) as f:
                for line in f:
                    if '"installdir"' in line:
                        installdir = line.split('"')[3]
                        break
        except:
            pass

        if not installdir:
            messagebox.showerror("Error", "Game directory not found.")
            return

        game_dir = os.path.join(DEFAULT_STEAMAPPS, "common", installdir)

        if not os.path.isdir(game_dir):
            messagebox.showerror("Error", "Game directory does not exist.")
            return

        wmv_files = []

        for root_dir, dirs, files in os.walk(game_dir):
            for f in files:
                if f.lower().endswith(".wmv"):
                    wmv_files.append(os.path.join(root_dir, f))

        if not wmv_files:
            messagebox.showinfo("Convert WMV", "No WMV files found.")
            return

        confirm = messagebox.askyesno(
            "Convert WMV",
            f"Found {len(wmv_files)} WMV files.\nConvert them to H264 + AAC?"
        )

        if not confirm:
            return

        self.show_progress_window(len(wmv_files))

        thread = threading.Thread(
            target=self.run_conversion,
            args=(wmv_files,),
            daemon=True
        )

        thread.start()

    def run_conversion(self, files):

        for input_file in files:

            base = os.path.splitext(input_file)[0]
            temp_mkv = base + ".mkv"
            final_wmv = base + ".wmv"

            try:

                probe = subprocess.run(
                    [
                        "ffprobe",
                        "-v", "error",
                        "-select_streams", "v:0",
                        "-show_entries", "stream=codec_name",
                        "-of", "default=noprint_wrappers=1:nokey=1",
                        input_file
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )

                codec = probe.stdout.strip()

                if codec == "h264":

                    self.log_message(f"SKIP (already H264): {input_file}")
                    self.increment_progress()
                    continue

            except:
                pass

            self.log_message(f"Converting: {input_file}")

            try:

                process = subprocess.Popen(
                    [
                        "ffmpeg", "-y",
                        "-i", input_file,
                        "-map", "0",
                        "-c:v", "libx264",
                        "-preset", "veryfast",
                        "-crf", "23",
                        "-pix_fmt", "yuv420p",
                        "-c:a", "aac",
                        "-b:a", "128k",
                        temp_mkv
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True
                )

                for line in process.stdout:
                    self.log_message(line.strip())

                process.wait()

                os.remove(input_file)
                os.rename(temp_mkv, final_wmv)

                self.log_message("Finished\n")

            except Exception as e:

                self.log_message(f"ERROR: {e}")

            self.increment_progress()

        self.log_message("All conversions finished.")

    # ---------------- WMV AUDIO Converter ----------------

    def convert_wmv_audio(self):

        item = self.get_selected()

        if not item:
            messagebox.showwarning("No Selection", "Select a game first.")
            return

        appid = item[0]

        manifest = os.path.join(
            os.path.dirname(self.compatdata_path.get()),
            f"appmanifest_{appid}.acf"
        )

        if not os.path.exists(manifest):
            messagebox.showerror("Error", "App manifest not found.")
            return

        installdir = None

        try:
            with open(manifest) as f:
                for line in f:
                    if '"installdir"' in line:
                        installdir = line.split('"')[3]
                        break
        except:
            pass

        if not installdir:
            messagebox.showerror("Error", "Game directory not found.")
            return

        game_dir = os.path.join(DEFAULT_STEAMAPPS, "common", installdir)

        if not os.path.isdir(game_dir):
            messagebox.showerror("Error", "Game directory does not exist.")
            return

        wmv_files = []

        for root_dir, dirs, files in os.walk(game_dir):
            for f in files:
                if f.lower().endswith(".wmv"):
                    wmv_files.append(os.path.join(root_dir, f))

        if not wmv_files:
            messagebox.showinfo("Convert WMV Audio", "No WMV files found.")
            return

        confirm = messagebox.askyesno(
            "Convert WMV Audio",
            f"Found {len(wmv_files)} WMV files.\nConvert audio to AAC?"
        )

        if not confirm:
            return

        self.show_progress_window(len(wmv_files))

        thread = threading.Thread(
            target=self.run_audio_conversion,
            args=(wmv_files,),
            daemon=True
        )

        thread.start()

    def run_audio_conversion(self, files):

        for input_file in files:

            base = os.path.splitext(input_file)[0]
            temp_mkv = base + ".mkv"
            final_wmv = base + ".wmv"

            try:

                probe = subprocess.run(
                    [
                        "ffprobe",
                        "-v", "error",
                        "-select_streams", "a:0",
                        "-show_entries", "stream=codec_name",
                        "-of", "default=noprint_wrappers=1:nokey=1",
                        input_file
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True
                )

                codec = probe.stdout.strip()

                if codec == "aac":

                    self.log_message(f"SKIP (already AAC): {input_file}")
                    self.increment_progress()
                    continue

            except:
                pass

            self.log_message(f"Converting audio: {input_file}")

            try:

                process = subprocess.Popen(
                    [
                        "ffmpeg", "-y",
                        "-i", input_file,
                        "-map", "0",
                        "-c:v", "copy",
                        "-c:a", "aac",
                        "-b:a", "128k",
                        temp_mkv
                    ],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True
                )

                for line in process.stdout:
                    self.log_message(line.strip())

                process.wait()

                os.remove(input_file)
                os.rename(temp_mkv, final_wmv)

                self.log_message("Finished\n")

            except Exception as e:

                self.log_message(f"ERROR: {e}")

            self.increment_progress()

        self.log_message("All audio conversions finished.")

    # ---------------- Prefix Tools ----------------

    def delete_prefix(self):

        item = self.get_selected()

        if not item:
            return

        appid = item[0]
        prefix = os.path.join(self.compatdata_path.get(), str(appid))

        confirm = messagebox.askyesno(
            "Confirm Deletion",
            f"Delete prefix for {item[1]} (AppID {appid})?\nThis cannot be undone!"
        )

        if confirm:

            try:
                shutil.rmtree(prefix)
                messagebox.showinfo("Deleted", f"Prefix for {item[1]} deleted.")
                self.scan_prefixes()

            except Exception as e:

                messagebox.showerror("Error", f"Failed to delete prefix:\n{e}")

    # ---------------- Prefix Scanner ----------------

    def browse(self):

        path = filedialog.askdirectory()

        if path:
            self.compatdata_path.set(path)
            self.scan_prefixes()

    def scan_prefixes(self):

        self.prefix_cache.clear()

        base = self.compatdata_path.get()

        if not os.path.isdir(base):
            return

        for appid in os.listdir(base):

            prefix = os.path.join(base, appid, "pfx")

            if not os.path.isdir(prefix):
                continue

            name = self.get_game_name(appid)
            proton = self.get_proton_version(appid)
            size = self.get_prefix_size(prefix)

            entry = (str(appid), name, proton, size)

            self.prefix_cache.append(entry)

        self.refresh_tree()

    def refresh_tree(self):

        self.tree.delete(*self.tree.get_children())

        for entry in self.prefix_cache:
            self.tree.insert("", "end", values=entry)

    def filter_list(self, event=None):

        search = self.search_var.get().lower()

        self.tree.delete(*self.tree.get_children())

        for entry in self.prefix_cache:

            if search in entry[1].lower() or search in entry[0]:

                self.tree.insert("", "end", values=entry)

    # ---------------- Helpers ----------------

    def get_game_name(self, appid):

        manifest = os.path.join(
            os.path.dirname(self.compatdata_path.get()),
            f"appmanifest_{appid}.acf"
        )

        if not os.path.exists(manifest):
            return "Unknown"

        try:

            with open(manifest) as f:
                for line in f:
                    if '"name"' in line:
                        return line.split('"')[3]

        except:
            pass

        return "Unknown"

    def get_proton_version(self, appid):

        config = os.path.join(self.compatdata_path.get(), appid, "config_info")

        if not os.path.exists(config):
            return "Unknown"

        try:
            with open(config) as f:
                version = f.readline().strip()
            return version
        except:
            return "Unknown"

    def get_prefix_size(self, path):

        total = 0

        for root_dir, dirs, files in os.walk(path):

            for f in files:

                try:
                    total += os.path.getsize(os.path.join(root_dir, f))
                except:
                    pass

        return self.human_size(total)

    def human_size(self, size):

        for unit in ["B", "KB", "MB", "GB", "TB"]:

            if size < 1024:
                return f"{size:.1f} {unit}"

            size /= 1024

        return f"{size:.1f} TB"

    def get_selected(self):

        sel = self.tree.selection()

        if not sel:
            return None

        return list(self.tree.item(sel[0])["values"])

    def open_prefix(self):

        item = self.get_selected()

        if not item:
            return

        appid = item[0]

        prefix = os.path.join(self.compatdata_path.get(), str(appid), "pfx")

        subprocess.Popen(["xdg-open", prefix])

    def open_game_dir(self):

        item = self.get_selected()

        if not item:
            return

        appid = item[0]

        manifest = os.path.join(
            os.path.dirname(self.compatdata_path.get()),
            f"appmanifest_{appid}.acf"
        )

        if not os.path.exists(manifest):
            return

        installdir = None

        try:

            with open(manifest) as f:
                for line in f:
                    if '"installdir"' in line:
                        installdir = line.split('"')[3]
                        break

        except:
            return

        if installdir:

            game_dir = os.path.join(DEFAULT_STEAMAPPS, "common", installdir)

            subprocess.Popen(["xdg-open", game_dir])


if __name__ == "__main__":

    root = tk.Tk()
    app = ProtonManager(root)
    root.mainloop()

END_PYTHON
