#!/bin/bash
# Bash wrapper that runs the embedded Python Tkinter app
exec python3 - <<'END_PYTHON'
import os
import subprocess
import tkinter as tk
from tkinter import simpledialog, messagebox

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_PROTON = os.path.join(SCRIPT_DIR, "run-proton.sh")
APPDIR = os.path.expanduser("~/.local/share/applications")
PREFIX = "generated-launcher"

os.makedirs(APPDIR, exist_ok=True)

def list_games():
    return [f[len(PREFIX)+1:-8] for f in os.listdir(APPDIR)
            if f.startswith(f"{PREFIX}-") and f.endswith(".desktop")]

def add_game():
    script = simpledialog.askstring("Desktop Launcher Generator", "Proton Script / Wine Binary:", initialvalue=DEFAULT_PROTON)
    if script is None: return
    name = simpledialog.askstring("Desktop Launcher Generator", "Game Name:")
    if name is None: return
    exe = simpledialog.askstring("Desktop Launcher Generator", "Game EXE:")
    if exe is None: return

    if not script or not name or not exe:
        messagebox.showerror("Error", "All fields must be filled")
        return

    safe_name = ''.join(c if c.isalnum() or c=='-' else '-' for c in name.replace(' ', '-'))
    file_path = os.path.join(APPDIR, f"{PREFIX}-{safe_name}.desktop")

    with open(file_path, "w") as f:
        f.write(f"""[Desktop Entry]
Type=Application
Name={name}
Exec="{script}" "{exe}"
Icon=steam
Terminal=false
Categories=Game;
""")
    os.chmod(file_path, 0o755)
    messagebox.showinfo("Success", f"Launcher created:\n\n{file_path}\n\nNow open Steam → Add Non-Steam Game")

def select_game_window(title, multiple=False):
    games = list_games()
    if not games:
        messagebox.showinfo("Info", "No launchers found")
        return None

    window = tk.Toplevel()
    window.title(title)
    window.geometry("300x400")

    frame = tk.Frame(window)
    frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

    scrollbar = tk.Scrollbar(frame)
    scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    lb = tk.Listbox(frame, selectmode=tk.MULTIPLE if multiple else tk.SINGLE, yscrollcommand=scrollbar.set)
    for game in games:
        lb.insert(tk.END, game)
    lb.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    scrollbar.config(command=lb.yview)

    result = []

    def confirm():
        selected_indices = lb.curselection()
        for i in selected_indices:
            result.append(lb.get(i))
        window.destroy()

    button_frame = tk.Frame(window)
    button_frame.pack(pady=5)
    tk.Button(button_frame, text="Confirm", command=confirm, width=12).pack(side=tk.LEFT, padx=5)
    tk.Button(button_frame, text="Close", command=window.destroy, width=12).pack(side=tk.LEFT, padx=5)

    window.grab_set()
    window.wait_window()

    return result if multiple else (result[0] if result else None)

def remove_game():
    selected = select_game_window("Remove Launcher", multiple=True)
    if not selected:
        return
    for game in selected:
        file_path = os.path.join(APPDIR, f"{PREFIX}-{game}.desktop")
        os.remove(file_path)
    messagebox.showinfo("Success", f"Launcher(s) removed: {', '.join(selected)}")

def edit_game():
    selected = select_game_window("Edit Launcher", multiple=False)
    if not selected:
        return
    file_path = os.path.join(APPDIR, f"{PREFIX}-{selected}.desktop")

    # Read existing values
    with open(file_path, "r") as f:
        lines = f.readlines()
    values = {}
    for line in lines:
        if "=" in line:
            k, v = line.strip().split("=", 1)
            values[k] = v

    new_name = simpledialog.askstring("Edit Launcher", "Game Name:", initialvalue=values.get("Name"))
    new_exec = simpledialog.askstring("Edit Launcher", "Exec Command:", initialvalue=values.get("Exec"))
    new_icon = simpledialog.askstring("Edit Launcher", "Icon:", initialvalue=values.get("Icon", "steam"))
    new_term = simpledialog.askstring("Edit Launcher", "Terminal (true/false):", initialvalue=values.get("Terminal", "false"))

    with open(file_path, "w") as f:
        f.write(f"""[Desktop Entry]
Type=Application
Name={new_name}
Exec={new_exec}
Icon={new_icon}
Terminal={new_term}
Categories=Game;
""")
    messagebox.showinfo("Success", "Launcher updated")

def show_list():
    games = list_games()
    if not games:
        messagebox.showinfo("Created Launchers", "No launchers found")
        return

    window = tk.Toplevel()
    window.title("Created Launchers")
    window.geometry("300x400")

    frame = tk.Frame(window)
    frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

    scrollbar = tk.Scrollbar(frame)
    scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    lb = tk.Listbox(frame, yscrollcommand=scrollbar.set)
    for game in games:
        lb.insert(tk.END, game)
    lb.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)

    scrollbar.config(command=lb.yview)
    tk.Button(window, text="Close", command=window.destroy).pack(pady=5)

    window.grab_set()
    window.wait_window()

def open_steam_add_game():
    subprocess.run(["steam", "steam://open/addnonsteamgame"])

def main_menu():
    root = tk.Tk()
    root.title("Desktop Launcher Generator")
    root.geometry("400x350")

    tk.Button(root, text="Add Game Launcher", command=add_game, width=30).pack(pady=5)
    tk.Button(root, text="Edit Launcher", command=edit_game, width=30).pack(pady=5)
    tk.Button(root, text="Remove Launcher", command=remove_game, width=30).pack(pady=5)
    tk.Button(root, text="List Launchers", command=show_list, width=30).pack(pady=5)
    tk.Button(root, text="Open Steam Add Game Window", command=open_steam_add_game, width=30).pack(pady=5)
    tk.Button(root, text="Exit", command=root.destroy, width=30).pack(pady=5)

    root.mainloop()

if __name__ == "__main__":
    main_menu()
END_PYTHON
