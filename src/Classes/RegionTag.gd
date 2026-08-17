# 커스텀 추가. by kojeomstudio
# 픽셀 아트의 신체 부위(머리, 몸통, 팔, 다리 등)처럼 사용자가 지정한 캔버스 영역에
# 이름과 색상을 태깅하는 클래스. 모션/스프라이트 시트 작업을 고려해 프레임 범위와
# 레이어 범위를 지정할 수 있으며, .pxo 저장 시 data.json의 "region_tags"에 직렬화되어
# 외부 도구/AI 에이전트가 영역 정보를 쉽게 파악할 수 있도록 한다.
class_name RegionTag
extends RefCounted
## A class for canvas region tag properties.
##
## A region tag marks a rectangular area of the canvas with a name and a color,
## optionally scoped to a frame range and/or a specific layer. This is useful for
## labeling body parts (head, torso, arms, legs) of a sprite, so that external
## tools and AI agents can understand the structure of the artwork from the
## saved metadata.

const DEFAULT_COLORS: PackedStringArray = [
	"ff4d4d", "4dc3ff", "66e07a", "ffd24d", "c58cff", "ff9e4d", "4dffc3", "ff6ee0"
]

var name: String  ## Name of the region (eg. "head", "left_arm").
var color: Color  ## Display color of the region on the canvas overlay.
var rect: Rect2i  ## Region in canvas coordinates.
## Layer index the tag belongs to, or -1 if it applies to all layers.
var layer := -1
## First frame of the tag (first frame in timeline is numbered 1, like AnimationTag).
var from_frame := 1
## Last frame of the tag (inclusive, 1-based like AnimationTag).
var to_frame := 1
var user_data := ""  ## User defined data, set in the region tag properties.
var visible := true  ## If false, the tag is kept in the metadata but not drawn.


## Class Constructor (used as [code]RegionTag.new(name, color, rect)[/code])
func _init(
	_name: String = "",
	_color: Color = Color.WHITE,
	_rect: Rect2i = Rect2i(),
	_layer: int = -1,
	_from_frame: int = 1,
	_to_frame: int = 1
) -> void:
	name = _name
	color = _color
	rect = _rect
	layer = _layer
	from_frame = _from_frame
	to_frame = _to_frame


func serialize() -> Dictionary:
	var dict := {
		"name": name,
		"color": color.to_html(true),
		"rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y],
		"layer": layer,
		"from_frame": from_frame,
		"to_frame": to_frame,
	}
	if not user_data.is_empty():
		dict["user_data"] = user_data
	if not visible:
		dict["visible"] = visible
	return dict


func deserialize(dict: Dictionary) -> void:
	name = str(dict.get("name", ""))
	color = Color.from_string(str(dict.get("color", "ffffffff")), Color.WHITE)
	var rect_values: Array = dict.get("rect", [0, 0, 0, 0])
	rect = Rect2i(
		Vector2i(int(rect_values[0]), int(rect_values[1])),
		Vector2i(int(rect_values[2]), int(rect_values[3]))
	)
	layer = int(dict.get("layer", -1))
	from_frame = maxi(1, int(dict.get("from_frame", 1)))
	to_frame = maxi(from_frame, int(dict.get("to_frame", from_frame)))
	user_data = str(dict.get("user_data", ""))
	visible = bool(dict.get("visible", true))


func duplicate() -> RegionTag:
	var new_tag := RegionTag.new(name, color, rect, layer, from_frame, to_frame)
	new_tag.user_data = user_data
	new_tag.visible = visible
	return new_tag


## Returns true if the tag is active on the given 0-based frame index.
func has_frame(index: int) -> bool:
	return from_frame <= (index + 1) and (index + 1) <= to_frame


## Returns true if the tag should be drawn for the given 0-based frame/layer indices.
func applies_to(frame_index: int, layer_index: int) -> bool:
	return has_frame(frame_index) and (layer == -1 or layer == layer_index)
