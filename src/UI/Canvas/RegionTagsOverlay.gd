# 커스텀 추가. by kojeomstudio
# 캔버스 위에 영역 태그(머리/몸통/팔/다리 등)를 색상 반투명 사각형 + 테두리 + 라벨로
# 표시하는 오버레이. 그리기 작업 방해를 최소화하기 위해 낮은 알파의 채움과 얇은 테두리를
# 사용하며, 입력 이벤트를 전혀 처리하지 않아 마우스 조작이 도구에 그대로 전달된다.
class_name RegionTagsOverlay
extends Node2D
## Draws the region tags of the current project on top of the canvas.
##
## The overlay is purely visual: it does not handle any input, so it never
## interferes with drawing. Tags are only shown when they belong to the current
## frame (and, if scoped, the current layer), so per-frame motion tagging works
## naturally while playing through a sprite sheet.

const FILL_ALPHA := 0.15
const BORDER_ALPHA := 0.9
const LABEL_FONT_SIZE := 14
const LABEL_OFFSET := Vector2(2, -4)

var font: Font

var _connected_project: Project


func _ready() -> void:
	font = Themes.get_font()
	Global.project_switched.connect(_on_project_switched)
	Global.cel_switched.connect(queue_redraw)
	# 줌/회전 시 테두리 두께와 라벨 크기를 화면 기준으로 일정하게 유지하기 위해 재그리기.
	Global.camera.zoom_changed.connect(queue_redraw)
	_on_project_switched()


func _on_project_switched() -> void:
	if is_instance_valid(_connected_project):
		_connected_project.region_tags_changed.disconnect(queue_redraw)
	_connected_project = Global.current_project
	if is_instance_valid(_connected_project):
		_connected_project.region_tags_changed.connect(queue_redraw)
	queue_redraw()


func _draw() -> void:
	if not Global.show_region_tags:
		return
	var project := Global.current_project
	if not is_instance_valid(project):
		return
	var canvas_zoom := get_viewport().canvas_transform.get_scale()
	var canvas_rotation := -get_viewport().canvas_transform.get_rotation()
	# 화면 픽셀 기준 1px 두께의 테두리를 그리기 위한 보정값.
	var border_width := 1.0 / maxf(canvas_zoom.x, 0.001)
	for tag in project.region_tags:
		if not tag.visible or not tag.applies_to(project.current_frame, project.current_layer):
			continue
		var rect := Rect2(tag.rect)
		if Global.mirror_view:  # 미러 뷰에서도 태그가 실제 픽셀 위에 놓이도록 보정.
			rect.position.x = project.size.x - rect.size.x - rect.position.x
		if not rect.has_area():
			continue
		var fill_color := tag.color
		fill_color.a = FILL_ALPHA
		draw_rect(rect, fill_color, true)
		var border_color := tag.color
		border_color.a = BORDER_ALPHA
		draw_rect(rect, border_color, false, border_width)
		_draw_label(rect.position + LABEL_OFFSET, tag.name, tag.color, canvas_zoom, canvas_rotation)


## 라벨 텍스트는 화면 기준 크기로 고정하여 줌 레벨과 무관하게 읽을 수 있게 한다.
func _draw_label(
	position: Vector2, text: String, color: Color, canvas_zoom: Vector2, canvas_rotation: float
) -> void:
	var string_pos := (position * canvas_zoom).rotated(-canvas_rotation)
	draw_set_transform(Vector2.ZERO, canvas_rotation, Vector2.ONE / canvas_zoom)
	# 가독성을 위해 어두운 오프셋 사본을 먼저 그린다.
	draw_string(
		font,
		string_pos + Vector2.ONE,
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE,
		Color(0, 0, 0, 0.6)
	)
	draw_string(font, string_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
