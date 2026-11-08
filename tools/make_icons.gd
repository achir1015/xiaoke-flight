extends SceneTree

# 由 icon.svg 產生各尺寸 PNG 圖示：godot --headless --path . -s res://tools/make_icons.gd

func _init() -> void:
	var svg := FileAccess.get_file_as_string("res://icon.svg")
	for s in [16, 32, 48, 144, 180, 192, 256, 512]:
		var img := Image.new()
		img.load_svg_from_string(svg, s / 512.0)
		img.save_png("res://platform/icon_%d.png" % s)
	# App Store 圖示：1024×1024、不能有透明（圓角留給系統裁切）
	var big := Image.new()
	big.load_svg_from_string(svg.replace('rx="112"', 'rx="0"'), 1024 / 512.0)  # 滿版，圓角交給 iOS
	var flat := Image.create(1024, 1024, false, Image.FORMAT_RGBA8)
	flat.fill(Color(0.06, 0.1, 0.18))
	big.convert(Image.FORMAT_RGBA8)
	flat.blend_rect(big, Rect2i(0, 0, 1024, 1024), Vector2i.ZERO)
	flat.convert(Image.FORMAT_RGB8)
	flat.save_png("res://assets/icon_1024.png")
	print("icons ok")
	quit()
