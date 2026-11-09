# Build the VistaRevive ISO on GitHub (no Debian PC needed)

GitHub runs the build on its own servers for free and gives you the ISO as a
download. Takes about 1–2 hours of waiting, no work on your side.

## One-time setup
1. Create a free account at github.com (if you don't have one).
2. Create a new repository: **New** → name it `vistarevive` → choose **Public**
   (public repos get free unlimited build minutes and download storage; the
   project is all original work, so nothing in it needs hiding) → **Create**.
3. Upload the project: on the empty repo page click **uploading an existing
   file**, then drag in everything from your `vistarevive` folder, keeping the
   folders: `art/`, `welcome/`, `.github/workflows/build-iso.yml`, all `0*.sh`,
   `0*.md`, `README.md`, `.gitignore`, `vistarevive-art.tar.gz`.
   (The `.github` folder is hidden on some systems; show hidden files, or create
   the file on GitHub via **Add file → Create new file** and type the path
   `.github/workflows/build-iso.yml`, then paste its contents.)
4. **Commit changes**.

## Build
1. Repository → **Actions** tab → **Build VistaRevive ISO** → **Run workflow**.
2. Pick the office suite (LibreOffice / lite / both). Tick *Release* if you want
   a permanent download page. → **Run workflow**.
3. Wait for the green tick (1–2 hours).
4. Click the finished run → **Artifacts** → **vistarevive-iso** (a .zip holding
   the ISO and its checksum). With *Release* ticked, it's also under **Releases**.

## If the run fails (red cross)
Download the **build-log** artifact from that run and send me the last ~50 lines.

## Write the ISO to a USB stick
- Windows: Rufus (choose "DD image mode" if asked) or balenaEtcher
- Linux:   `sudo dd if=vistarevive-*.iso of=/dev/sdX bs=4M status=progress oflag=sync`
  (check the stick's name with `lsblk` first; dd overwrites it)

Then on the 6710b: **F9** at power-on → USB → **Live** to try it, **Install** to install.
