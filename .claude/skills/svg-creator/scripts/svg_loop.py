#!/usr/bin/env python3
"""SVG Feedback Loop — Mandatory render-view-fix cycle.

Commands:
  python3 svg_loop.py render <svg_file>
      Renders SVG to PNG preview. Claude MUST view the PNG after this.
      Prints the PNG path for the view tool.

  python3 svg_loop.py finish <svg_file> [output_name.svg]
      Finalizes the SVG. Copies to /mnt/user-data/outputs/.
      REFUSES if render was never called (Claude never looked at it).

  python3 svg_loop.py status
      Shows current iteration count and history.

  python3 svg_loop.py reset
      Clears iteration history for a fresh start.
"""

import sys
import os
import json
import shutil
from pathlib import Path

import re
import subprocess
import tempfile

# Portable paths (patched for Windows/macOS/Linux). Override with env vars.
WORK_DIR = os.environ.get("SVG_LOOP_DIR", os.path.join(tempfile.gettempdir(), "svg_loop"))
os.makedirs(WORK_DIR, exist_ok=True)
STATE_FILE = os.path.join(WORK_DIR, ".svg_loop_state.json")
PREVIEW_PNG = os.environ.get("SVG_LOOP_PREVIEW", os.path.join(WORK_DIR, "svg_preview.png"))
OUTPUT_DIR = os.environ.get("SVG_LOOP_OUTPUT", os.path.join(WORK_DIR, "outputs"))

BROWSER_CANDIDATES = [
    r"C:\Program Files\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe",
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
    "/usr/bin/google-chrome", "/usr/bin/chromium", "/usr/bin/chromium-browser",
]

def find_browser():
    custom = os.environ.get("SVG_LOOP_BROWSER")
    if custom and os.path.exists(custom):
        return custom
    for path in BROWSER_CANDIDATES:
        if os.path.exists(path):
            return path
    return None

def render_with_browser(browser, svg_file, out_png, width=800):
    """Render via headless Chrome/Edge so output matches what browsers show."""
    with open(svg_file, encoding="utf-8") as f:
        content = f.read()
    m = re.search(r'viewBox\s*=\s*"([\d.\-\s,]+)"', content)
    height = width
    if m:
        parts = [float(p) for p in re.split(r"[\s,]+", m.group(1).strip())]
        if len(parts) == 4 and parts[2] > 0:
            height = int(round(width * parts[3] / parts[2]))
    html = os.path.join(WORK_DIR, "_render.html")
    svg_uri = Path(os.path.abspath(svg_file)).as_uri()
    with open(html, "w", encoding="utf-8") as f:
        f.write(f'<!doctype html><html><body style="margin:0;background:#fff">'
                f'<img src="{svg_uri}" style="display:block;width:{width}px;height:{height}px"></body></html>')
    subprocess.run([browser, "--headless=new", "--disable-gpu", "--hide-scrollbars",
                    "--allow-file-access-from-files", f"--window-size={width},{height}",
                    "--virtual-time-budget=2000", f"--screenshot={out_png}",
                    Path(html).as_uri()],
                   check=True, capture_output=True, timeout=60)

def ensure_cairosvg():
    try:
        import cairosvg
        return cairosvg
    except ImportError:
        os.system(f"{sys.executable} -m pip install cairosvg --break-system-packages -q")
        import cairosvg
        return cairosvg

def load_state():
    if os.path.exists(STATE_FILE):
        with open(STATE_FILE) as f:
            return json.load(f)
    return {"iterations": 0, "history": [], "svg_file": None}

def save_state(state):
    with open(STATE_FILE, 'w') as f:
        json.dump(state, f, indent=2)

def cmd_render(svg_file, width=800):
    if not os.path.exists(svg_file):
        print(f"ERROR: File not found: {svg_file}")
        sys.exit(1)

    # Read and validate SVG
    with open(svg_file, encoding="utf-8") as f:
        svg_content = f.read()

    if '<svg' not in svg_content:
        print("ERROR: File does not contain valid SVG.")
        sys.exit(1)

    # Render to PNG (headless browser first, cairosvg fallback)
    try:
        browser = find_browser()
        if browser:
            render_with_browser(browser, svg_file, PREVIEW_PNG, width)
        else:
            cairosvg = ensure_cairosvg()
            cairosvg.svg2png(
                bytestring=svg_content.encode('utf-8'),
                write_to=PREVIEW_PNG,
                output_width=width
            )
    except Exception as e:
        print(f"RENDER ERROR: {e}")
        print("Fix the SVG syntax and try again.")
        sys.exit(1)

    # Update state
    state = load_state()
    state["iterations"] += 1
    state["svg_file"] = os.path.abspath(svg_file)
    state["history"].append({
        "iteration": state["iterations"],
        "file": os.path.abspath(svg_file),
        "size": len(svg_content)
    })
    save_state(state)

    n = state["iterations"]
    print(f"{'='*50}")
    print(f"  RENDERED — Iteration #{n}")
    print(f"{'='*50}")
    print(f"  Preview: {PREVIEW_PNG}")
    print(f"")
    print(f"  >>> NOW USE THE VIEW TOOL ON: {PREVIEW_PNG}")
    print(f"  >>> LOOK at the image. Assess what needs fixing.")
    print(f"  >>> Then edit the SVG and run 'render' again.")
    print(f"{'='*50}")

def cmd_finish(svg_file, output_name=None):
    state = load_state()

    if state["iterations"] == 0:
        print("="*50)
        print("  BLOCKED — You never rendered and viewed this SVG!")
        print("  ")
        print("  Run this first:")
        print(f"    python3 svg_loop.py render {svg_file}")
        print("  Then view the PNG, fix issues, and try finish again.")
        print("="*50)
        sys.exit(1)

    if state["iterations"] < 2:
        print("="*50)
        print(f"  WARNING — Only {state['iterations']} render(s) done.")
        print("  Best results need 2+ render-view-fix cycles.")
        print("  Proceeding anyway, but quality may suffer.")
        print("="*50)

    # Determine output path
    if output_name is None:
        output_name = os.path.basename(svg_file)
    if not output_name.endswith('.svg'):
        output_name += '.svg'

    output_path = os.path.join(OUTPUT_DIR, output_name)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    shutil.copy2(svg_file, output_path)

    # Also copy the final preview PNG
    preview_name = output_name.replace('.svg', '_preview.png')
    preview_output = os.path.join(OUTPUT_DIR, preview_name)
    if os.path.exists(PREVIEW_PNG):
        shutil.copy2(PREVIEW_PNG, preview_output)

    print(f"{'='*50}")
    print(f"  DELIVERED after {state['iterations']} iteration(s)")
    print(f"  SVG: {output_path}")
    print(f"  Preview: {preview_output}")
    print(f"{'='*50}")

    # Reset state for next SVG
    save_state({"iterations": 0, "history": [], "svg_file": None})

def cmd_status():
    state = load_state()
    print(f"Iterations: {state['iterations']}")
    print(f"Current file: {state.get('svg_file', 'None')}")
    if state["history"]:
        print("History:")
        for h in state["history"]:
            print(f"  #{h['iteration']}: {h['file']} ({h['size']} bytes)")

def cmd_reset():
    save_state({"iterations": 0, "history": [], "svg_file": None})
    if os.path.exists(PREVIEW_PNG):
        os.remove(PREVIEW_PNG)
    print("State reset. Ready for new SVG.")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "render":
        if len(sys.argv) < 3:
            print("Usage: python3 svg_loop.py render <svg_file> [width]")
            sys.exit(1)
        cmd_render(sys.argv[2], int(sys.argv[3]) if len(sys.argv) > 3 else 800)

    elif cmd == "finish":
        if len(sys.argv) < 3:
            print("Usage: python3 svg_loop.py finish <svg_file> [output_name.svg]")
            sys.exit(1)
        output_name = sys.argv[3] if len(sys.argv) > 3 else None
        cmd_finish(sys.argv[2], output_name)

    elif cmd == "status":
        cmd_status()

    elif cmd == "reset":
        cmd_reset()

    else:
        print(f"Unknown command: {cmd}")
        print("Commands: render, finish, status, reset")
        sys.exit(1)
