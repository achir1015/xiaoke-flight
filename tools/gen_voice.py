"""產生全部角色台詞與遊戲說明的臺灣華語語音（edge-tts 神經語音）。

用法：python -I tools/gen_voice.py [--force]
讀 scripts/texts.gd 的 SPEAKERS、LINES、HELP，輸出 assets/voice/<id>.ogg 與 help_NN.ogg。
已經存在且文字沒變的檔案會略過（assets/voice/.hash.json 記錄文字雜湊）。
需要 edge-tts（pip install edge-tts）與 ffmpeg。
"""
import asyncio
import hashlib
import json
import os
import re
import subprocess
import sys
import edge_tts

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "voice")
HELP_VOICE = ("zh-TW-HsiaoChenNeural", "+0Hz", "+0%")

FX = {
    "none": None,
    "radio": "highpass=f=320,lowpass=f=3200,acompressor=threshold=-18dB:ratio=4,volume=1.6",
    "pa": "highpass=f=180,lowpass=f=5200,aecho=0.8:0.5:40:0.18,volume=1.3",
}

REPL = [
    ("Shift 或 PageUp", "Shift 鍵或 PageUp 鍵"), ("（[ 鍵）", "（左中括號鍵）"), ("G 鍵", "G 鍵"),
    ("W／S", "W 和 S"), ("A／D", "A 和 D"), ("Q／E", "Q 和 E"), ("Shift／Ctrl", "Shift 和 Ctrl"),
    ("PageUp／PageDown", "PageUp 和 PageDown"), ("[ ／ ]", "左右中括號"), ("P 或 Esc", "P 鍵或 Esc 鍵"),
    ("Chrome／Edge", "Chrome 或 Edge"), ("N1", "N 一"), ("PAPI", "怕批"), ("AED", "A E D"), ("CPR", "C P R"),
    ("OpenAI", "Open A I"), ("ChatGPT", "Chat G P T"), ("AI", "A I"),
    ("1,000", "一千"), ("2,000", "兩千"), ("144", "一百四十四"), ("180", "一百八十"), ("140", "一百四十"), ("700", "七百"), ("900", "九百"),
    ("／", "、"), ("～", "到"), ("→", "，再點"), ("•", ""), ("①", ""), ("②", ""), ("③", ""), ("④", ""), ("⑤", ""), ("⑥", ""), ("　", "，"),
]


def clean(t: str) -> str:
    t = t.replace("\\n", "\n")
    for a, b in REPL:
        t = t.replace(a, b)
    out = []
    for ln in t.split("\n"):
        ln = ln.strip()
        if not ln:
            continue
        if not re.search(r"[。！？：；，、]$", ln):
            ln += "。"
        out.append(ln)
    return "".join(out)


def parse():
    src = open(os.path.join(ROOT, "scripts", "texts.gd"), encoding="utf8").read()
    sp_block = src[src.index("const SPEAKERS"):src.index("const LINES")]
    speakers = {}
    for m in re.finditer(r'"(\w+)": \["([^"]*)", "([^"]+)", "([^"]+)", "([^"]+)", "(\w+)"\]', sp_block):
        speakers[m.group(1)] = (m.group(3), m.group(4), m.group(5), m.group(6))
    ln_block = src[src.index("const LINES"):src.index("const HELP")]
    lines = re.findall(r'"(\w+)": \["(\w+)", "((?:[^"\\]|\\.)*)"\]', ln_block)
    help_block = src[src.index("const HELP"):src.index("const CHANGELOG")]
    pages = re.findall(r'\["([^"]+)", "(\w+)", "((?:[^"\\]|\\.)*)"\]', help_block)
    return speakers, lines, pages


async def speak(text, name, voice, pitch, rate, fx, hashes, force):
    h = hashlib.md5((text + voice + pitch + rate + str(fx)).encode("utf8")).hexdigest()
    ogg = os.path.join(OUT, name + ".ogg")
    if not force and os.path.exists(ogg) and hashes.get(name) == h:
        return
    mp3 = os.path.join(OUT, name + ".mp3")
    for attempt in range(4):
        try:
            await edge_tts.Communicate(text, voice, rate=rate, pitch=pitch).save(mp3)
            break
        except Exception as e:  # 網路偶爾失敗就重試
            print("retry", name, e)
            await asyncio.sleep(2 + attempt * 2)
    cmd = ["ffmpeg", "-v", "error", "-y", "-i", mp3]
    if FX.get(fx):
        cmd += ["-af", FX[fx]]
    cmd += ["-ac", "1", "-ar", "24000", "-c:a", "libvorbis", "-q:a", "2", ogg]
    subprocess.run(cmd, check=True)
    os.remove(mp3)
    hashes[name] = h
    print(name, len(text), "字")


async def main():
    force = "--force" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    hp = os.path.join(OUT, ".hash.json")
    hashes = json.load(open(hp, encoding="utf8")) if os.path.exists(hp) else {}
    speakers, lines, pages = parse()
    try:
        for lid, spk, text in lines:
            voice, pitch, rate, fx = speakers[spk]
            await speak(clean(text), lid, voice, pitch, rate, fx, hashes, force)
        for i, (title, _anim, body) in enumerate(pages):
            await speak(title + "。" + clean(body), "help_%02d" % i, *HELP_VOICE, "none", hashes, force)
    finally:
        json.dump(hashes, open(hp, "w", encoding="utf8"), ensure_ascii=False, indent=0)
    print("done", len(lines), "lines", len(pages), "help")


if __name__ == "__main__":
    asyncio.run(main())
