# CS2 NetCafe Optimizer

Author: **[@yusifcatharsis](https://github.com/yusifcatharsis)** · Telegram: **[@jeisterx](https://t.me/jeisterx)**

A single-file, silent Counter-Strike 2 optimizer for internet cafes, built and tested on a **diskless** club (Cloud Update) with 83 PCs.

**[Azərbaycanca aşağıdadır ↓](#azərbaycanca)**

## What it does

Runs hidden in the background when the PC boots (nothing is shown on screen) and:

- Detects the GPU, screen resolution and CPU type
- Writes an optimized `cs2_video.txt` (read-only) for **every** Steam account on the PC, including accounts that log in later
- Writes `autoexec.cfg`, applies Windows game settings (Game DVR off, Game Mode on, high-performance GPU, fullscreen optimizations off) and the right power plan for the CPU (dual-CCD X3D CPUs keep *Balanced*)
- Applies NVIDIA driver settings silently if `nvidiaProfileInspector.exe` sits next to the script
- **Shader cache sharing:** restores the NVIDIA shader cache from a server share before CS2 starts, and collects it back after CS2 closes (archived by GPU model + driver version)
- **Pre-warm:** reads the exact parts of the CS2 files the game needs to reach the main menu into RAM, so the first launch is fast

Players launch CS2 from Steam as usual. No menu entry is needed.

## Measured results (diskless client, 1 Gbps, RTX 4060 Ti / RTX 5070)

| First launch after boot | cs2.exe start → main menu | Data read over network during launch |
|---|---|---|
| Without pre-warm | ~61–70 s | ~5.0–5.7 GB |
| **With pre-warm** | **~29 s** | **~1.9 GB** |

The pre-warm itself takes ~50–60 s at boot, running in the background before the player gets to the game.

## Requirements

- Windows 10/11, PowerShell 5.1 (built in)
- Steam + CS2
- For shader sharing / custom list / logs: a shared folder on your server that the client PCs can write to
- Optional: [NVIDIA Profile Inspector](https://github.com/Orbmu2k/nvidiaProfileInspector/releases) 2.4.x (`nvidiaProfileInspector.exe`) placed next to the script. It is not included in this repo.

## Setup

1. Open `CS2_Optimizer.bat` in a text editor and set your share path:
   ```powershell
   $ShareDir = '\\SERVER\share\cs2_shader'
   ```
   Other settings (MSAA, Reflex, FPS limits, pre-warm delay, and so on) are in the same block.
2. Put the script where the clients can reach it.
3. Run it at boot, for example:
   - **Cloud Update:** Workstations → More → Set boot task → Add Task → *Run only*, Executable = path to `CS2_Optimizer.bat`, Delay = 30
   - Other diskless systems or a normal PC: a startup task that runs the `.bat` with admin rights
4. Check the logs: `C:\ProgramData\cs2opt\log.txt` on the client and `<ShareDir>\jurnal\<PC>.txt` on the server.

## Extra modes (run from an admin command prompt)

| Command | What it does |
|---|---|
| `CS2_Optimizer.bat iz` | Re-measures which file parts CS2 reads up to the main menu (ETW trace) and saves a new pre-warm list to the share. **Run this after big CS2 updates.** Reboot first, log in to Steam, then run it and press Enter when the main menu appears. |
| `CS2_Optimizer.bat play` | Starts the background service if it is not running, then launches CS2 (optional, for club menus). |
| `CS2_Optimizer.bat image` | **Super mode / image editing only.** Turns off VBS / Memory Integrity. This gives more FPS but **weakens Windows security**, so use it at your own risk. |

## Notes

- The built-in pre-warm list was measured on 19.11.2026. After CS2 updates it still works but helps less, until you run `iz` again.
- Built for diskless clubs. It also works on a normal PC, but the shader-sharing and pre-warm parts help most on diskless systems.
- MIT licensed. No warranty: test on one PC before rolling out.
- Questions or feedback: open an issue or write on Telegram [@jeisterx](https://t.me/jeisterx).

---

## Azərbaycanca

Internet klublar üçün tək fayldan ibarət, səssiz işləyən CS2 optimizatoru. Disksiz (Cloud Update) 83 PC-lik klubda hazırlanıb və sınanıb.

### Nə edir

PC açılanda arxa planda gizli işə düşür (ekranda heç nə görünmür) və bunları edir:
- Video kartı, ekranı və prosessoru tanıyır
- PC-dəki **hər** Steam hesabına `cs2_video.txt` yazır, sonradan girən hesablar da daxil
- `autoexec.cfg` yazır, Windows oyun ayarlarını və prosessora uyğun enerji planını tətbiq edir
- `nvidiaProfileInspector.exe` yanında olsa, NVIDIA ayarlarını səssiz tətbiq edir
- Shader cache-i serverdən geri yükləyir, CS2 bağlananda serverə yığır
- CS2-nin menyuya qədər oxuduğu hissələri RAM-a əvvəlcədən oxuyur: ilk açılış ~65 san → **~29 san**

Müştəri CS2-ni Steam-dən adi qaydada açır.

### Quraşdırma

1. `CS2_Optimizer.bat`-da `$ShareDir` sətrini öz server qovluğunuza dəyişin.
2. Cloud Update → Workstations → More → Set boot task → Add Task:
   - Task Type: *Run only*
   - Executable: faylın yolu
   - Delay: 30
3. Jurnal: client-də `C:\ProgramData\cs2opt\log.txt`, serverdə `<ShareDir>\jurnal\<PC>.txt`.

### Əlavə rejimlər

- **`iz`**: CS2 böyük yeniləmədən sonra öncədən oxuma siyahısını yeniləyir.
- **`play`**: CS2-ni açır.
- **`image`**: yalnız super rejimdə işlədin. VBS-i söndürür və təhlükəsizliyi zəiflədir.

---

## Contact / Əlaqə

- GitHub: [@yusifcatharsis](https://github.com/yusifcatharsis)
- Telegram: [@jeisterx](https://t.me/jeisterx)

Suggestions, bug reports and pull requests are welcome. / Təklif və xəta bildirişləri üçün Issues bölməsindən və ya Telegram-dan yazın.
