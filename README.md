# 小柯機器人3D真實飛行

小柯機器人系列的 3D 客機模擬飛行（Godot 4.7.2，線上版優先）。

- 臺灣全島程序地形與七座機場（桃園、松山、臺中、高雄、花蓮、臺東、澎湖），跑道燈、PAPI、盲降指示
- 手動起飛與降落、基本飛行儀表（姿態、空速、高度、升降率、航向）、操縱桿與油門
- AI 自動駕駛：自動起飛、爬升、巡航、進場、自動落地煞停
- AI 機器人小柯：語音對話、聯絡塔台、最近機場、地圖導航（可選用自己的 OpenAI 金鑰）
- 天氣：下雨、雷雨、颱風、下雪結冰；白天、黃昏、夜晚
- 機上突發狀況：孕婦臨盆、高血壓、心臟病發、劫機；客艙即時小畫面
- 機長廣播（起訖機場、預計抵達時間）、空服員安全示範；當地日期時間
- 全繁體中文、臺灣華語語音、遊戲說明（語音＋文字＋動畫）、版本更新、建立捷徑

## 開發

- 檢查腳本：`godot --headless --path . res://tools/check.tscn`
- 無頭飛行測試：`godot --headless --fixed-fps 60 --path . res://tools/flighttest.tscn -- --from=TPE --to=KHH --ts=4`
- 遊戲測試旗標：`-- --test --level=N --ap --ts=4 --evnow=cardiac --cabin --xk --map --cam=cockpit --shots=5,20 --out=DIR --quit=21 --dbg --autoact=20`
- 語音：`python -I tools/gen_voice.py`（edge-tts，讀 scripts/texts.gd）；音樂音效：`python -I tools/gen_audio.py`
- 線上版：`bash tools/build_web.sh` → `../build/flight-web/`、`../build/xiaoke-flight-web.zip`

開發者：吳玉柱 先生與 Claude AI Opus 5.5
