# 커스텀 추가. by kojeomstudio
# 좌측 도구 패널의 영역 태그 도구. 캔버스에 드래그해 사각 영역을 지정하면 놓는 순간
# 영역 태그가 생성된다(undo 가능). 이름·색상·프레임 범위·레이어 스코프는 도구 옵션에서
# 지정하며, 생성된 태그는 기존처럼 캔버스 오버레이에 표시되고 .pxo 메타데이터에 저장된다.
# 세부 편집(프레임 범위 조정, 삭제 등)은 Image > Region Tags... 다이얼로그에서 담당한다.
extends BaseTool
## Region Tag tool, creates region tags interactively.
##
## Drag on the canvas to define a rectangular region; releasing the mouse
## commits a RegionTag with the name/color/scope configured in the tool
## options. Shift constrains the region to a square, Ctrl expands it from
## the center.

var _start_pos := Vector2i.ZERO
var _rect := Rect2i()
var _square := false  ## Mouse Click + Shift
var _expand_from_center := false  ## Mouse Click + Ctrl


func _ready() -> void:
	super._ready()
	$"%Color".color = Color.from_string(RegionTag.DEFAULT_COLORS[0], Color.WHITE)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("shape_perfect"):
		_square = true
	elif event.is_action_released("shape_perfect"):
		_square = false
	if event.is_action_pressed("shape_center"):
		_expand_from_center = true
	elif event.is_action_released("shape_center"):
		_expand_from_center = false


func draw_start(pos: Vector2i) -> void:
	super.draw_start(pos)
	_start_pos = pos
	_rect = Rect2i(pos, Vector2i.ZERO)


func draw_move(pos: Vector2i) -> void:
	super.draw_move(pos)
	_rect = _get_result_rect(_start_pos, pos)
	_set_cursor_text(_rect)
	Global.canvas.previews.queue_redraw()


func draw_end(pos: Vector2i) -> void:
	super.draw_end(pos)
	_rect = _get_result_rect(_start_pos, pos)
	if _rect.has_area():
		_commit_tag(_rect)
	_reset_tool()
	Global.canvas.previews.queue_redraw()


func cancel_tool() -> void:
	super()
	_reset_tool()
	Global.canvas.previews.queue_redraw()


## 드래그 중 미리보기: 옵션에서 고른 색상으로 실제 태그와 동일하게 표시한다.
func draw_preview() -> void:
	if not _rect.has_area():
		return
	var project := Global.current_project
	var canvas: Node2D = Global.canvas.previews
	var pos := canvas.position
	var canvas_scale := canvas.scale
	if Global.mirror_view:
		pos.x = pos.x + project.size.x
		canvas_scale.x = -1
	canvas.draw_set_transform(pos, canvas.rotation, canvas_scale)
	var color: Color = $"%Color".color
	var fill_color := color
	fill_color.a = RegionTagsOverlay.FILL_ALPHA
	canvas.draw_rect(_rect, fill_color, true)
	var border_color := color
	border_color.a = RegionTagsOverlay.BORDER_ALPHA
	canvas.draw_rect(_rect, border_color, false)
	canvas.draw_set_transform(canvas.position, canvas.rotation, canvas.scale)


func _reset_tool() -> void:
	_rect = Rect2i()
	_square = false
	_expand_from_center = false
	cursor_text = ""


## BaseSelectionTool 의 헬퍼를 가져온다(BaseTool 에는 없음).
func _set_cursor_text(rect: Rect2i) -> void:
	cursor_text = "%s, %s" % [rect.position.x, rect.position.y]
	cursor_text += " -> %s, %s" % [rect.end.x - 1, rect.end.y - 1]
	cursor_text += " (%s, %s)" % [rect.size.x, rect.size.y]


## 드래그로 만든 사각형을 태그로 커밋한다. 다이얼로그와 동일하게 하나의 undo 액션으로.
func _commit_tag(rect: Rect2i) -> void:
	var project := Global.current_project
	var tag_base: String = $"%Name".text.strip_edges()
	var frame_scope: int = $"%FrameScope".selected
	var from_frame := project.current_frame + 1
	var to_frame := from_frame
	# 커스텀 변경. by kojiomstudio — 부위_레이어_프레임 자동 네이밍(예: head_0_0).
	# "All frames" 스코프는 프레임 무관 태그이므로 base 그대로 둔다.
	var tag_name := tag_base
	if frame_scope != 1:
		tag_name = RegionTag.compose_name(tag_base, project.current_layer, project.current_frame)
	elif tag_name.is_empty():
		tag_name = "region"
	if frame_scope == 1:  # All frames
		from_frame = 1
		to_frame = maxi(project.frames.size(), 1)
	var layer := -1
	if $"%LayerOnly".button_pressed:
		layer = project.current_layer
	var color: Color = $"%Color".color
	var new_tags: Array[RegionTag] = []
	for tag in project.region_tags:
		new_tags.append(tag.duplicate())
	new_tags.append(RegionTag.new(tag_name, color, rect, layer, from_frame, to_frame))
	new_tags.sort_custom(  # 커스텀 변경. by kojeomstudio — 계층 순 유지
		func(a: RegionTag, b: RegionTag) -> bool:
			if a.layer != b.layer:
				return a.layer < b.layer
			if a.from_frame != b.from_frame:
				return a.from_frame < b.from_frame
			return a.name < b.name
	)
	var undo_tags: Array[RegionTag] = []
	for tag in project.region_tags:
		undo_tags.append(tag.duplicate())
	project.undo_redo.create_action("Add Region Tag")
	project.undo_redo.add_do_property(project, "region_tags", new_tags)
	project.undo_redo.add_undo_property(project, "region_tags", undo_tags)
	project.undo_redo.commit_action()


## RectSelect 와 동일한 규칙(Shift 정사각형, Ctrl 중심 확장)으로 결과 사각형을 계산한다.
func _get_result_rect(origin: Vector2i, dest: Vector2i) -> Rect2i:
	var rect := Rect2i()
	if _expand_from_center:
		var new_size := dest - origin
		if _square:
			var square_size := maxi(absi(new_size.x), absi(new_size.y))
			new_size = Vector2i(square_size, square_size)
		origin -= new_size
		dest = origin + 2 * new_size
	if _square:
		var square_size := mini(absi(origin.x - dest.x), absi(origin.y - dest.y))
		rect.position.x = origin.x if origin.x < dest.x else origin.x - square_size
		rect.position.y = origin.y if origin.y < dest.y else origin.y - square_size
		rect.size = Vector2i(square_size, square_size)
	else:
		rect.position = Vector2i(mini(origin.x, dest.x), mini(origin.y, dest.y))
		rect.size = (origin - dest).abs()
	rect.size += Vector2i.ONE
	return rect
