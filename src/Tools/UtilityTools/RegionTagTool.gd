# 커스텀 추가. by kojiomstudio
# 좌측 도구 패널의 영역 태그 도구. 캔버스에 드래그해 사각 영역을 지정하면 놓는 순간
# 현재 레이어에 귀속된 영역 태그가 생성된다(undo 가능). 이름·색상·프레임 범위는 도구
# 옵션에서 지정하며, 생성된 태그는 캔버스 오버레이에 표시되고 .pxo 메타데이터에 저장된다.
# 도구 옵션의 태그 목록은 레이어별로 그룹화되어 표시되며 우클릭(다중) 삭제를 지원한다.
extends BaseTool
## Region Tag tool, creates region tags interactively.
##
## Drag on the canvas to define a rectangular region; releasing the mouse
## commits a RegionTag bound to the current layer with the name/color/scope
## configured in the tool options. Shift constrains the region to a square,
## Ctrl expands it from the center.

var _start_pos := Vector2i.ZERO
var _rect := Rect2i()
var _square := false  ## Mouse Click + Shift
var _expand_from_center := false  ## Mouse Click + Ctrl
# 커스텀 추가. by kojiomstudio — 태그 목록 우클릭 삭제 메뉴.
var _context_menu: PopupMenu
# 커스텀 추가. by kojeomstudio — Delete 키 삭제 확인용 다이얼로그.
var _confirm_dialog: ConfirmationDialog
# 커스텀 추가. by kojeomstudio — 목록 행 → 태그 인덱스 매핑(그룹 헤더 때문에 필요).
var _tag_rows: Array[int] = []

var _connected_project: Project


func _ready() -> void:
	super._ready()
	$"%Color".color = Color.from_string(RegionTag.DEFAULT_COLORS[0], Color.WHITE)
	# 커스텀 추가. by kojiomstudio — 도구 옵션의 태그 목록을 프로젝트/셀/레이어 변경 시 갱신한다.
	Global.project_switched.connect(_on_project_switched)
	Global.cel_switched.connect(_refresh_tag_list)
	var tag_list := $"TagList" as ItemList
	tag_list.select_mode = ItemList.SELECT_MULTI
	tag_list.item_selected.connect(_on_tag_list_selected)
	# 커스텀 추가. by kojeomstudio — 태그 목록 우클릭 메뉴로 (다중) 삭제를 제공한다.
	tag_list.item_clicked.connect(_on_tag_list_item_clicked)
	# 커스텀 추가. by kojeomstudio — Delete 키로도 선택 태그를 삭제할 수 있게 한다.
	tag_list.gui_input.connect(_on_tag_list_gui_input)
	# 커스텀 추가. by kojeomstudio — Delete 키 삭제 시 확인 팝업을 한 번 띄운다.
	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.dialog_text = tr("Delete the selected region tags?")
	_confirm_dialog.ok_button_text = tr("Delete")
	_confirm_dialog.add_cancel_button(tr("Cancel"))
	_confirm_dialog.confirmed.connect(_on_context_menu_id_pressed.bind(0))
	add_child(_confirm_dialog)
	_context_menu = PopupMenu.new()
	_context_menu.add_item(tr("Delete selected tags"), 0)
	_context_menu.id_pressed.connect(_on_context_menu_id_pressed)
	add_child(_context_menu)
	_on_project_switched()


## 목록 항목 우클릭 시 삭제 메뉴를 띄운다. Shift/Ctrl 클릭으로 여러 항목 선택 가능.
## 목록에 포커스된 상태에서 Delete 키를 누르면 확인 팝업 후 선택 태그들을 삭제한다.
func _on_tag_list_gui_input(event: InputEvent) -> void:
	if (
		event is InputEventKey
		and event.pressed
		and not event.echo
		and event.keycode == KEY_DELETE
	):
		var tag_list := $"TagList" as ItemList
		if not tag_list.get_selected_items().is_empty():
			_confirm_dialog.popup_centered()
			tag_list.accept_event()


func _on_tag_list_item_clicked(index: int, _position: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	var tag_list := $"TagList" as ItemList
	if _row_to_tag_index(index) == -1:
		return
	tag_list.select(index)
	_on_tag_list_selected(index)
	_context_menu.reset_size()
	_context_menu.position = _context_menu.get_viewport().get_mouse_position()
	_context_menu.popup()


## 컨텍스트 메뉴의 삭제 처리: 선택된 모든 태그를 단일 undo 액션으로 커밋한다.
func _on_context_menu_id_pressed(_id: int) -> void:
	var tag_list := $"TagList" as ItemList
	var tag_indices := []
	for row in tag_list.get_selected_items():
		var tag_index := _row_to_tag_index(row)
		if tag_index != -1:
			tag_indices.append(tag_index)
	if tag_indices.is_empty():
		return
	_delete_tags(tag_indices)


## 커스텀 추가. by kojeomstudio — 목록에서 태그들을 삭제하고 undo 로 복구 가능하게 한다.
func _delete_tags(indices: Array) -> void:
	var project := Global.current_project
	var undo_tags := _duplicate_tags(project.region_tags)
	var redo_tags := _duplicate_tags(project.region_tags)
	indices.sort()
	indices.reverse()  # 뒤에서부터 제거해 인덱스가 밀리지 않게 한다.
	for index in indices:
		if index >= 0 and index < redo_tags.size():
			redo_tags.remove_at(index)
	project.undo_redo.create_action("Delete Region Tags")
	project.undo_redo.add_do_property(project, "region_tags", redo_tags)
	project.undo_redo.add_undo_property(project, "region_tags", undo_tags)
	project.undo_redo.commit_action()


func _duplicate_tags(tags: Array[RegionTag]) -> Array[RegionTag]:
	var result: Array[RegionTag] = []
	for tag in tags:
		result.append(tag.duplicate())
	return result


func _on_project_switched() -> void:
	if is_instance_valid(_connected_project):
		if _connected_project.region_tags_changed.is_connected(_refresh_tag_list):
			_connected_project.region_tags_changed.disconnect(_refresh_tag_list)
		if _connected_project.layers_updated.is_connected(_on_layers_updated):
			_connected_project.layers_updated.disconnect(_on_layers_updated)
		for layer in _connected_project.layers:
			if layer.visibility_changed.is_connected(_refresh_tag_list):
				layer.visibility_changed.disconnect(_refresh_tag_list)
	_connected_project = Global.current_project
	if is_instance_valid(_connected_project):
		_connected_project.region_tags_changed.connect(_refresh_tag_list)
		# 커스텀 추가. by kojeomstudio — 레이어 추가/제거/표시 토글 시 목록을 갱신한다.
		_connected_project.layers_updated.connect(_on_layers_updated)
		for layer in _connected_project.layers:
			layer.visibility_changed.connect(_refresh_tag_list)
	_refresh_tag_list()


func _on_layers_updated() -> void:
	if not is_instance_valid(_connected_project):
		return
	for layer in _connected_project.layers:
		if not layer.visibility_changed.is_connected(_refresh_tag_list):
			layer.visibility_changed.connect(_refresh_tag_list)
	_refresh_tag_list()


## 커스텀 변경. by kojeomstudio — 태그 목록을 레이어별 그룹으로 채운다.
## 헤더 행(비활성) + 태그 행으로 구성하고 _tag_rows 로 행→태그 인덱스를 매핑한다.
func _refresh_tag_list() -> void:
	var tag_list := $"TagList" as ItemList
	var selected_tag_indices := []
	for row in tag_list.get_selected_items():
		var tag_index := _row_to_tag_index(row)
		if tag_index != -1:
			selected_tag_indices.append(tag_index)
	tag_list.clear()
	_tag_rows = []
	var project := Global.current_project
	if not is_instance_valid(project):
		return
	var last_layer := -99999
	for tag_index in project.region_tags.size():
		var tag := project.region_tags[tag_index]
		if tag.layer != last_layer:
			last_layer = tag.layer
			tag_list.add_item(_get_layer_header(project, tag.layer))
			tag_list.set_item_disabled(tag_list.item_count - 1, true)
		var icon := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		var icon_color := tag.color
		icon_color.a = 1.0
		icon.fill(icon_color)
		tag_list.add_item(_get_tag_label(tag), ImageTexture.create_from_image(icon))
		_tag_rows.append(tag_list.item_count - 1)
	for tag_index in selected_tag_indices:
		if tag_index < _tag_rows.size():
			tag_list.select(_tag_rows[tag_index])


## 표시 행 인덱스를 태그 인덱스로 변환한다. 헤더 행은 -1.
func _row_to_tag_index(row: int) -> int:
	return _tag_rows.find(row)


## 커스텀 추가. by kojiomstudio — 레이어 그룹 헤더 라벨(숨김 레이어 표시 포함).
func _get_layer_header(project: Project, layer_index: int) -> String:
	if layer_index < 0 or layer_index >= project.layers.size():
		return "All layers"
	var layer := project.layers[layer_index]
	var header := "Layer %d: %s" % [layer_index, layer.name]
	if not layer.visible:
		header += "  (" + tr("hidden") + ")"
	return header


func _get_tag_label(tag: RegionTag) -> String:
	var frame_range := (
		str(tag.from_frame)
		if tag.from_frame == tag.to_frame
		else "%d-%d" % [tag.from_frame, tag.to_frame]
	)
	return "%s (F%s)" % [tag.name, frame_range]


## 목록에서 선택한 태그를 오버레이에서 흰색 테두리로 강조한다.
func _on_tag_list_selected(row: int) -> void:
	var tag_index := _row_to_tag_index(row)
	if tag_index == -1:
		return
	var overlay := Global.canvas.region_tags_overlay
	if not is_instance_valid(overlay):
		return
	overlay.selected_tag = Global.current_project.region_tags[tag_index]


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
	# 커스텀 변경. by kojeomstudio — 명시적으로 드래그한 경우에만 태그를 만든다.
	# 클릭만으로 1x1 태그가 생기면 메타데이터가 노이즈로 오염된다.
	if pos == _start_pos:
		_reset_tool()
		Global.canvas.previews.queue_redraw()
		return
	_rect = _get_result_rect(_start_pos, pos)
	if _rect.size.x > 1 or _rect.size.y > 1:
		_commit_tag(_rect)
	_reset_tool()
	Global.canvas.previews.queue_redraw()


func cancel_tool() -> void:
	super()
	_reset_tool()
	Global.canvas.previews.queue_redraw()


## 커스텀 변경. by kojiomstudio — 미리보기는 기존 사각 선택 도구(RectSelect)와 완전히
## 동일하게: 반투명 채움 없이 검은 1px 테두리만 그린다. 완성 태그의 색상 표시는
## 오버레이가 담당한다.
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
	canvas.draw_rect(_rect, Color.BLACK, false)
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


## 드래그로 만든 사각형을 태그로 커밋한다. 태그는 항상 현재 레이어에 귀속된다.
func _commit_tag(rect: Rect2i) -> void:
	var project := Global.current_project
	var tag_base: String = $"%Name".text.strip_edges()
	var frame_scope: int = $"%FrameScope".selected
	var from_frame := project.current_frame + 1
	var to_frame := from_frame
	# 커스텀 변경. by kojeomstudio — 부위_레이어_프레임 자동 네이밍(예: head_layer0_frame0).
	# "All frames" 스코프는 프레임 무관 태그이므로 base 그대로 둔다.
	var tag_name := tag_base
	if frame_scope != 1:
		tag_name = RegionTag.compose_name(tag_base, project.current_layer, project.current_frame)
	elif tag_name.is_empty():
		tag_name = "region"
	if frame_scope == 1:  # All frames
		from_frame = 1
		to_frame = maxi(project.frames.size(), 1)
	# 커스텀 변경. by kojiomstudio — 태그는 항상 현재 레이어에 귀속시킨다(레이어 visible 연동).
	var layer := project.current_layer
	# 커스텀 변경. by kojeomstudio — 자동 색상: 같은 부위 이름의 기존 색을 재사용(1:1 매핑)하고
	# 새로운 부위면 아직 안 쓰인 고시인성 색을 고른다. 체크 해제 시 색 선택기를 따른다.
	var color: Color = $"%Color".color
	if $"%AutoColor".button_pressed:
		color = RegionTag.pick_color(tag_base, project.region_tags)
	var new_tags: Array[RegionTag] = []
	for tag in project.region_tags:
		new_tags.append(tag.duplicate())
	new_tags.append(RegionTag.new(tag_name, color, rect, layer, from_frame, to_frame))
	new_tags.sort_custom(  # 커스텀 변경. by kojiomstudio — 계층 순 유지
		func(a: RegionTag, b: RegionTag) -> bool:
			if a.layer != b.layer:
				return a.layer < b.layer
			if a.from_frame != b.from_frame:
				return a.from_frame < b.from_frame
			return a.name < b.name
	)
	var undo_tags := _duplicate_tags(project.region_tags)
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
