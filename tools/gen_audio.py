"""產生小柯機器人3D真實飛行的背景音樂與音效（原創程序合成）。

用法：python -I tools/gen_audio.py
輸出：assets/music/*.ogg、assets/sfx/*.wav（需要 numpy、scipy、ffmpeg）
"""
import os
import subprocess
import numpy as np
from scipy.io import wavfile
from scipy.signal import butter, lfilter

SR = 44100
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
MUSIC = os.path.join(ROOT, "assets", "music")
SFX = os.path.join(ROOT, "assets", "sfx")
rng = np.random.default_rng(20261107)


def midi(n):
    return 440.0 * 2 ** ((n - 69) / 12)


def lp(x, fc, order=2):
    b, a = butter(order, min(fc / (SR / 2), 0.99), "low")
    return lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = butter(order, fc / (SR / 2), "high")
    return lfilter(b, a, x)


def epiano(f, dur, vel=0.5):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 2.2) * (1 - np.exp(-t * 400))
    tine = np.sin(2 * np.pi * f * t + 0.6 * np.sin(2 * np.pi * f * 14 * t) * np.exp(-t * 9))
    body = 0.5 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 4)
    trem = 1 + 0.15 * np.sin(2 * np.pi * 4.5 * t)
    return (tine + body) * env * trem * vel


def bass(f, dur, vel=0.6):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 1.5) * (1 - np.exp(-t * 200))
    x = np.sin(2 * np.pi * f * t) + 0.25 * np.sin(2 * np.pi * f * 2 * t)
    return x * env * vel


def pluck(f, dur, vel=0.3):
    n = int(dur * SR)
    t = np.arange(n) / SR
    env = np.exp(-t * 6) * (1 - np.exp(-t * 600))
    x = np.sign(np.sin(2 * np.pi * f * t)) * 0.3 + np.sin(2 * np.pi * f * t)
    return lp(x * env * vel, 2500)


def kick():
    n = int(0.35 * SR)
    t = np.arange(n) / SR
    f = 50 + 70 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 9) * 0.8


def hat(open_=False):
    n = int((0.25 if open_ else 0.06) * SR)
    t = np.arange(n) / SR
    x = hp(rng.standard_normal(n), 7000)
    return x * np.exp(-t * (12 if open_ else 60)) * 0.12


def snare():
    n = int(0.25 * SR)
    t = np.arange(n) / SR
    x = lp(rng.standard_normal(n), 5000) * np.exp(-t * 18) * 0.25
    x += np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25) * 0.2
    return x


def add(buf, x, at):
    i = int(at * SR)
    j = min(len(buf), i + len(x))
    if i < len(buf):
        buf[i:j] += x[: j - i]


def vinyl(n):
    x = lp(rng.standard_normal(n), 1800) * 0.008
    pops = (rng.random(n) > 0.99993) * rng.standard_normal(n) * 0.15
    return x + lp(pops, 3000)


def track(name, key, bpm, prog, bars, swing=0.58, melody_scale=None):
    beat = 60.0 / bpm
    total = bars * 4 * beat + 2.0
    n = int(total * SR)
    L = np.zeros(n)
    R = np.zeros(n)
    scale = melody_scale or [0, 2, 4, 7, 9, 12, 14, 16]
    for bar in range(bars):
        root, quality = prog[bar % len(prog)]
        t0 = bar * 4 * beat
        chord = [0, 4, 7, 11, 14] if quality == "maj" else [0, 3, 7, 10, 14]
        notes = [key + root + c for c in chord]
        # 和弦：前拍與切分
        for hit, vel in ((0.0, 0.42), (2.5, 0.3)):
            for k, nn in enumerate(notes[1:]):
                x = epiano(midi(nn + 12), beat * 3, vel * 0.5)
                pan = 0.35 + 0.3 * (k / 3)
                add(L, x * (1 - pan), t0 + hit * beat + k * 0.012)
                add(R, x * pan, t0 + hit * beat + k * 0.012)
        # 低音
        for b_at, off in ((0, 0), (1.5, 7), (2.5, 0), (3.5, 12 if bar % 2 else 7)):
            x = bass(midi(key + root - 12 + off), beat * 1.2, 0.5)
            add(L, x, t0 + b_at * beat)
            add(R, x, t0 + b_at * beat)
        # 鼓
        if bar >= 2:
            for b in range(4):
                tt = t0 + b * beat
                if b in (0, 2):
                    add(L, kick(), tt); add(R, kick(), tt)
                if b in (1, 3):
                    s = snare(); add(L, s * 0.9, tt); add(R, s, tt)
                for h in range(2):
                    off = h * beat * (swing if h else 0)
                    hh = hat(open_=(b == 3 and h == 1))
                    add(L, hh * 0.8, tt + off); add(R, hh, tt + off)
        # 旋律（溫和、偶爾休息）
        if bar >= 4 and bar % 8 < 6:
            for s in range(8):
                if rng.random() < 0.45:
                    deg = scale[int(rng.integers(0, len(scale)))]
                    x = pluck(midi(key + 24 + root % 12 // 12 + deg), beat * 0.9, 0.18)
                    tt = t0 + s * beat / 2 + (beat / 2 * (swing - 0.5) if s % 2 else 0)
                    add(L, x * 0.6, tt); add(R, x * 0.9, tt)
    st = np.stack([L, R], axis=1)
    st[:, 0] += vinyl(n)
    st[:, 1] += vinyl(n)
    st = lp(st.T, 9000).T
    # 淡入淡出
    fade = int(1.5 * SR)
    st[:fade] *= np.linspace(0, 1, fade)[:, None]
    st[-fade:] *= np.linspace(1, 0, fade)[:, None]
    st /= np.max(np.abs(st)) + 1e-9
    st *= 0.8
    wav = os.path.join(MUSIC, name + ".wav")
    wavfile.write(wav, SR, (st * 32767).astype(np.int16))
    ogg = os.path.join(MUSIC, name + ".ogg")
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "3", ogg], check=True)
    os.remove(wav)
    print("music", name, round(total, 1), "s")


def write_sfx(name, x):
    x = np.asarray(x, dtype=float)
    x /= np.max(np.abs(x)) + 1e-9
    x *= 0.7
    wavfile.write(os.path.join(SFX, name + ".wav"), SR, (x * 32767).astype(np.int16))




def write_sfx(name, x):
    x = np.asarray(x, dtype=float)
    x /= np.max(np.abs(x)) + 1e-9
    x *= 0.7
    wavfile.write(os.path.join(SFX, name + ".wav"), SR, (x * 32767).astype(np.int16))


def tone(f, dur, decay=8.0, wave="sine"):
    n = int(dur * SR)
    t = np.arange(n) / SR
    if wave == "square":
        x = np.sign(np.sin(2 * np.pi * f * t))
    else:
        x = np.sin(2 * np.pi * f * t)
    return x * np.exp(-t * decay) * (1 - np.exp(-t * 800))


def cat(*parts):
    return np.concatenate(parts)


def loopfade(x, sec=0.25):
    f = int(sec * SR)
    x = x.copy()
    # 交叉淡化讓循環無縫
    head = x[:f].copy()
    x = x[f:]
    x[-f:] = x[-f:] * np.linspace(1, 0, f) + head * np.linspace(0, 1, f)
    return x


def sfx():
    write_sfx("click", tone(1400, 0.05, 60))
    # 客艙提示音（叮咚）與安全帶燈
    write_sfx("chime", cat(tone(988, 0.55, 3.5) * 0.8 + tone(1976, 0.55, 6) * 0.15, tone(784, 1.0, 2.5) * 0.8 + tone(1568, 1.0, 5) * 0.15))
    write_sfx("seatbelt", tone(1046, 0.9, 3.0) + 0.3 * tone(2093, 0.9, 5))
    write_sfx("ding", tone(1318, 0.5, 6) + 0.5 * tone(1975, 0.5, 8))
    # 主警告
    seg = []
    for _ in range(3):
        seg.append(tone(1000, 0.18, 1, "square") * 0.3)
        seg.append(np.zeros(int(0.12 * SR)))
    write_sfx("caution", np.concatenate(seg))
    # 失速抖桿
    n = int(1.0 * SR)
    t = np.arange(n) / SR
    shake = lp(np.sign(np.sin(2 * np.pi * 28 * t)) * (0.6 + 0.4 * rng.random(n)), 400)
    write_sfx("stall", loopfade(shake, 0.05))
    # 無線電雜訊（按話）
    n = int(0.18 * SR)
    t = np.arange(n) / SR
    r = hp(rng.standard_normal(n), 1800) * np.exp(-t * 18) * 0.6
    r[:int(0.06 * SR)] += tone(1800, 0.06, 30) * 0.3
    write_sfx("radio", r)
    # 起落架
    n = int(2.6 * SR)
    t = np.arange(n) / SR
    hum = lp(rng.standard_normal(n), 300) * 0.5 * np.minimum(1, t / 0.2) * np.exp(-np.maximum(0, t - 2.0) * 6)
    hum += np.sin(2 * np.pi * 110 * t) * 0.15 * np.minimum(1, t / 0.2) * np.exp(-np.maximum(0, t - 2.0) * 6)
    clunk = np.zeros(n)
    i = int(2.1 * SR)
    m = int(0.3 * SR)
    tt = np.arange(m) / SR
    clunk[i:i + m] = np.sin(2 * np.pi * (70 + 80 * np.exp(-tt * 30)) * tt) * np.exp(-tt * 12) * 1.2
    write_sfx("gear", hum + clunk)
    # 襟翼馬達
    n = int(1.6 * SR)
    t = np.arange(n) / SR
    write_sfx("flaps", (np.sin(2 * np.pi * 180 * t) * 0.3 + lp(rng.standard_normal(n), 600) * 0.4) * np.minimum(1, t / 0.15) * np.minimum(1, (1.6 - t) / 0.2))
    # 著陸輪胎摩擦
    n = int(0.9 * SR)
    t = np.arange(n) / SR
    squeal = (np.sin(2 * np.pi * (1300 - 300 * t) * t) * 0.3 + hp(rng.standard_normal(n), 900) * 0.5) * np.exp(-t * 4)
    thud = np.sin(2 * np.pi * (60 + 50 * np.exp(-t * 20)) * t) * np.exp(-t * 8)
    write_sfx("touchdown", squeal + thud)
    # 墜毀
    n = int(3.0 * SR)
    t = np.arange(n) / SR
    write_sfx("crash", lp(rng.standard_normal(n), 400) * np.exp(-t * 1.2) * 2 + hp(rng.standard_normal(n), 2000) * np.exp(-t * 5))
    # 乘客鼓掌
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    clap = np.zeros(n)
    for _ in range(900):
        i = int(rng.random() * (n - 2000))
        m = 600
        tt = np.arange(m) / SR
        clap[i:i + m] += bp_noise(m) * np.exp(-tt * 400) * (0.5 + rng.random())
    env = np.minimum(1, t / 0.4) * np.minimum(1, (4.0 - t) / 1.2)
    write_sfx("applause", clap * env)
    # 救護車與警車
    n = int(3.0 * SR)
    t = np.arange(n) / SR
    f = np.where((t * 1.4) % 1 < 0.5, 960, 770)
    write_sfx("siren", np.sin(2 * np.pi * np.cumsum(f) / SR) * 0.6)
    write_sfx("fanfare", cat(tone(523, 0.12, 6), tone(659, 0.12, 6), tone(784, 0.12, 6), tone(1046, 0.6, 3)))
    write_sfx("fail", cat(tone(392, 0.25, 4), tone(330, 0.25, 4), tone(262, 0.7, 2.5)))
    # 寶寶誕生的溫柔鈴聲
    write_sfx("baby", cat(tone(1046, 0.25, 5), tone(1318, 0.25, 5), tone(1568, 0.25, 5), tone(2093, 1.0, 2)) * 0.8)
    # 心電圖嗶聲
    write_sfx("beep", tone(1000, 0.12, 10))
    # 拉起警告（地形）
    seg = []
    for _ in range(2):
        seg.append(tone(700, 0.25, 0.5, "square") * 0.25)
        seg.append(np.zeros(int(0.08 * SR)))
    write_sfx("whoop", np.concatenate(seg))
    print("sfx done")


def bp_noise(m):
    return hp(lp(rng.standard_normal(m), 3500), 700)


def loops():
    """可循環：引擎、風切、雨、雷。"""
    n = int(6.0 * SR)
    t = np.arange(n) / SR
    # 渦扇引擎：寬頻隆隆＋風扇嗡聲
    roar = lp(rng.standard_normal(n), 700) * 0.9 + lp(rng.standard_normal(n), 2500) * 0.25
    fan = sum(np.sin(2 * np.pi * f * t + rng.random() * 6) * a for f, a in ((240, 0.06), (480, 0.04), (1830, 0.02), (3660, 0.012)))
    write_sfx("engine", loopfade(roar + fan))
    # 引擎高頻嘯聲（推力大時加大）
    whine = sum(np.sin(2 * np.pi * f * t) * a for f, a in ((2900, 0.4), (4350, 0.2), (5800, 0.1)))
    whine += hp(rng.standard_normal(n), 4000) * 0.15
    write_sfx("whine", loopfade(whine))
    # 風切聲
    w = lp(rng.standard_normal(n), 900)
    gust = 0.7 + 0.3 * np.sin(2 * np.pi * 0.25 * t) * np.sin(2 * np.pi * 0.11 * t + 1.0)
    write_sfx("wind", loopfade(w * gust))
    # 雨打機身
    rain = hp(rng.standard_normal(n), 1500) * 0.25 + lp(rng.standard_normal(n), 900) * 0.15
    drops = (rng.random(n) > 0.997) * rng.standard_normal(n)
    rain += hp(drops, 2500) * 0.8
    write_sfx("rain", loopfade(rain))
    # 地面滾行轟隆
    write_sfx("rumble", loopfade(lp(rng.standard_normal(n), 140) * (1 + 0.3 * (rng.random(n) > 0.995))))
    n = int(4.0 * SR)
    t = np.arange(n) / SR
    crack = hp(rng.standard_normal(n), 1200) * np.exp(-t * 9) * 0.7
    rumble = lp(rng.standard_normal(n), 120) * np.exp(-t * 0.8) * (1 - np.exp(-t * 6)) * 2.5
    write_sfx("thunder", crack + rumble)
    print("loops done")


if __name__ == "__main__":
    os.makedirs(MUSIC, exist_ok=True)
    os.makedirs(SFX, exist_ok=True)
    sfx()
    loops()
    track("sky_theme", 62, 88, [(0, "maj"), (7, "maj"), (9, "min"), (5, "maj")], 40)
    track("cruise", 60, 72, [(5, "maj"), (0, "maj"), (2, "min"), (7, "maj")], 36)
    track("tension", 57, 96, [(0, "min"), (8, "maj"), (3, "maj"), (10, "maj")], 32, melody_scale=[0, 3, 5, 7, 10, 12])
