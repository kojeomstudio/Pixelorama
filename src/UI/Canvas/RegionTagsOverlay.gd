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
const LABEL_OFFSET := Vector2(0, -2)

var font: Font
## 커스텀 추가. by kojeomstudio — 도구의 태그 목록에서 선택된 태그(테두리 강조용).
var selected_tag: RegionTag

var _connected_project: Project


func _ready() -> void:
	font = Themes.get_font()
	Global.project_switched.connect(_on_project_switched)
	Global.cel_switched.connect(queue_redraw)
	# 줌/회전 시 테두리 두께와 라벨 크기를 화면 기준으로 일정하게 유지하기 위해 재그리기.
	Global.camera.zoom_changed.connect(queue_redraw)
	_on_project_switched()


func _on_project_switched() -> void:
	_disconnect_project()
	_connected_project = Global.current_project
	if is_instance_valid(_connected_project):
		_connected_project.region_tags_changed.connect(queue_redraw)
		# 커스텀 추가. by kojeomstudio — 레이어 표시 토글/목록 변경 시 재그리기.
		_connected_project.layers_updated.connect(_on_layers_updated)
		for layer in _connected_project.layers:
			layer.visibility_changed.connect(queue_redraw)
	queue_redraw()


func _disconnect_project() -> void:
	if not is_instance_valid(_connected_project):
		return
	if _connected_project.region_tags_changed.is_connected(queue_redraw):
		_connected_project.region_tags_changed.disconnect(queue_redraw)
	if _connected_project.layers_updated.is_connected(_on_layers_updated):
		_connected_project.layers_updated.disconnect(_on_layers_updated)
	for layer in _connected_project.layers:
		if layer.visibility_changed.is_connected(queue_redraw):
			layer.visibility_changed.disconnect(queue_redraw)


func _on_layers_updated() -> void:
	if not is_instance_valid(_connected_project):
		return
	for layer in _connected_project.layers:
		if not layer.visibility_changed.is_connected(queue_redraw):
			layer.visibility_changed.connect(queue_redraw)
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
		# 커스텀 변경. by kojeomstudio — 태그가 귀속된 레이어를 끄면 태그도 함께 숨긴다.
		var tag_layer := tag.layer if tag.layer >= 0 else project.current_layer
		if tag_layer >= project.layers.size() or not project.layers[tag_layer].visible:
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
		if tag == selected_tag:  # 커스텀 변경. by kojiomstudio — 목록 선택 태그는 흰색 강조
			border_color = Color.WHITE
		draw_rect(rect, border_color, false, border_width)
		_draw_label(rect, tag.name, tag.color, canvas_zoom, canvas_rotation)


## 커스텀 변경. by kojiomstudio — 네임플레이트: 검은 배경 없이 영역 좌측 최상단 코너
## 바로 위에 bold 로 표시한다. 가독성을 위해 얇은 어두운 윤곽만 깔고, 본문을 살짝
## 겹쳐 그려 굵은 글씨 효과를 낸다.
func _draw_label(
	rect: Rect2, text: String, color: Color, canvas_zoom: Vector2, canvas_rotation: float
) -> void:
	var label_pos := rect.position + LABEL_OFFSET
	var string_pos := (label_pos * canvas_zoom).rotated(-canvas_rotation)
	draw_set_transform(Vector2.ZERO, canvas_rotation, Vector2.ONE / canvas_zoom)
	for offset in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
		draw_string(
			font,
			string_pos + offset,
			text,
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			LABEL_FONT_SIZE,
			Color(0, 0, 0, 0.8)
		)
	# 본문을 0.5px 오프셋으로 두 번 그려 bold 효과를 낸다.
	draw_string(font, string_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_FONT_SIZE, color)
	draw_string(
		font,
		string_pos + Vector2(0.5, 0),
		text,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		LABEL_FONT_SIZE,
		color
	)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
