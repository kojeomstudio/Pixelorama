# 커스텀 추가. by kojeomstudio
# 영역 태그 관리 다이얼로그. 머리/몸통/팔/다리 등 캔버스 영역에 이름·색상·프레임 범위를
# 지정하고, 현재 선택 영역으로부터 태그를 바로 만들 수 있다. 모션 작업을 고려해 태그는
# 프레임 범위(1-based)로 적용 구간을 지정하며, 확인 시 변경 전체가 하나의 undo 액션으로
# 커밋되고 취소 시 다이얼로그를 열 당시 상태로 되돌아간다.
class_name RegionTagsDialog
extends AcceptDialog
## Dialog for managing the region tags of the current project.
##
## Region tags label rectangular canvas areas (eg. body parts) with a name, a
## color and an optional frame/layer scope, and are stored in the project's
## metadata when saving a .pxo file. The UI is built from code to keep scene
## file churn to a minimum.

var tag_list: ItemList
var add_button: Button
var add_from_selection_button: Button
var delete_button: Button
var name_line_edit: LineEdit
var color_picker_button: ColorPickerButton
var layer_option_button: OptionButton
var from_frame_spin_box: SpinBox
var to_frame_spin_box: SpinBox
var x_spin_box: SpinBox
var y_spin_box: SpinBox
var width_spin_box: SpinBox
var height_spin_box: SpinBox
var user_data_text_edit: TextEdit
var visible_check_box: CheckBox

var _snapshot: Array[RegionTag] = []
var _syncing := false  ## UI를 채우는 동안 편집 시그널 루프를 막는다.


func _ready() -> void:
	title = tr("Region Tags")
	size = Vector2i(760, 440)
	min_size = Vector2i(640, 380)
	ok_button_text = tr("OK")
	_build_ui()
	about_to_popup.connect(_on_about_to_popup)
	confirmed.connect(_on_confirmed)
	canceled.connect(_on_canceled)
	visibility_changed.connect(_on_visibility_changed)


func _on_visibility_changed() -> void:
	Global.dialog_open(visible)


## UI를 코드로 구성한다. 레이아웃: (태그 목록 + 버튼) | (속성 편집기).
func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(split)

	var left_box := VBoxContainer.new()
	left_box.custom_minimum_size = Vector2(240, 0)
	split.add_child(left_box)

	tag_list = ItemList.new()
	tag_list.custom_minimum_size = Vector2(240, 0)
	tag_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tag_list.item_selected.connect(_on_tag_selected)
	left_box.add_child(tag_list)

	var button_row := HBoxContainer.new()
	left_box.add_child(button_row)

	add_button = Button.new()
	add_button.text = tr("Add")
	add_button.pressed.connect(_on_add_pressed)
	button_row.add_child(add_button)

	add_from_selection_button = Button.new()
	add_from_selection_button.text = tr("Add From Selection")
	add_from_selection_button.tooltip_text = tr(
		"Creates a region tag from the current selection, scoped to the current frame."
	)
	add_from_selection_button.pressed.connect(_on_add_from_selection_pressed)
	button_row.add_child(add_from_selection_button)

	delete_button = Button.new()
	delete_button.text = tr("Delete")
	delete_button.pressed.connect(_on_delete_pressed)
	button_row.add_child(delete_button)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(grid)

	name_line_edit = _add_grid_row(grid, tr("Name:"), "LineEdit") as LineEdit
	name_line_edit.text_changed.connect(_on_name_changed)

	color_picker_button = (
		_add_grid_row(grid, tr("Color:"), "ColorPickerButton") as ColorPickerButton
	)
	color_picker_button.custom_minimum_size = Vector2(48, 28)
	color_picker_button.color_changed.connect(_on_color_changed)

	layer_option_button = _add_grid_row(grid, tr("Layer:"), "OptionButton") as OptionButton
	layer_option_button.item_selected.connect(_on_layer_selected)

	from_frame_spin_box = _add_grid_row(grid, tr("From Frame:"), "SpinBox") as SpinBox
	from_frame_spin_box.value_changed.connect(_on_from_frame_changed)

	to_frame_spin_box = _add_grid_row(grid, tr("To Frame:"), "SpinBox") as SpinBox
	to_frame_spin_box.value_changed.connect(_on_to_frame_changed)

	x_spin_box = _add_grid_row(grid, tr("X:"), "SpinBox") as SpinBox
	x_spin_box.value_changed.connect(_on_x_changed)

	y_spin_box = _add_grid_row(grid, tr("Y:"), "SpinBox") as SpinBox
	y_spin_box.value_changed.connect(_on_y_changed)

	width_spin_box = _add_grid_row(grid, tr("Width:"), "SpinBox") as SpinBox
	width_spin_box.value_changed.connect(_on_width_changed)

	height_spin_box = _add_grid_row(grid, tr("Height:"), "SpinBox") as SpinBox
	height_spin_box.value_changed.connect(_on_height_changed)

	user_data_text_edit = _add_grid_row(grid, tr("User Data:"), "TextEdit") as TextEdit
	user_data_text_edit.custom_minimum_size = Vector2(0, 64)
	user_data_text_edit.text_changed.connect(_on_user_data_changed)

	visible_check_box = _add_grid_row(grid, tr("Visible:"), "CheckBox") as CheckBox
	visible_check_box.toggled.connect(_on_visible_toggled)


func _add_grid_row(grid: GridContainer, label_text: String, control_type: String) -> Control:
	var label := Label.new()
	label.text = label_text
	grid.add_child(label)
	var control: Control = ClassDB.instantiate(control_type)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)
	return control


func _on_about_to_popup() -> void:
	_snapshot = _duplicate_tags(Global.current_project.region_tags)
	_refresh_editor_bounds()
	_refresh_list()
	_select_tag(0 if tag_list.item_count > 0 else -1)


## 확인 시: 다이얼로그에서 편집한 내용을 단일 undo 액션으로 커밋한다.
func _on_confirmed() -> void:
	var project := Global.current_project
	if _tags_equal(_snapshot, project.region_tags):
		return
	var undo_tags := _duplicate_tags(_snapshot)
	var redo_tags := _duplicate_tags(project.region_tags)
	project.undo_redo.create_action("Edit Region Tags")
	project.undo_redo.add_do_property(project, "region_tags", redo_tags)
	project.undo_redo.add_undo_property(project, "region_tags", undo_tags)
	project.undo_redo.commit_action()
	project.has_changed = true


## 취소 시: 열 당시 스냅샷으로 되돌린다(undo 히스토리 오염 방지).
func _on_canceled() -> void:
	var project := Global.current_project
	if not _tags_equal(_snapshot, project.region_tags):
		project.region_tags = _duplicate_tags(_snapshot)


func _duplicate_tags(tags: Array[RegionTag]) -> Array[RegionTag]:
	var result: Array[RegionTag] = []
	for tag in tags:
		result.append(tag.duplicate())
	return result


func _tags_equal(a: Array[RegionTag], b: Array[RegionTag]) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if a[i].serialize() != b[i].serialize():
			return false
	return true


## 스핀박스 범위를 현재 프로젝트 크기/프레임 수에 맞춘다.
func _refresh_editor_bounds() -> void:
	var project := Global.current_project
	var frame_count := maxi(project.frames.size(), 1)
	from_frame_spin_box.min_value = 1
	from_frame_spin_box.max_value = frame_count
	to_frame_spin_box.min_value = 1
	to_frame_spin_box.max_value = frame_count
	for spin_box: SpinBox in [x_spin_box, width_spin_box]:
		spin_box.min_value = 0
		spin_box.max_value = maxi(project.size.x, 1)
	for spin_box: SpinBox in [y_spin_box, height_spin_box]:
		spin_box.min_value = 0
		spin_box.max_value = maxi(project.size.y, 1)
	_syncing = true
	layer_option_button.clear()
	layer_option_button.add_item(tr("All Layers"))
	for layer in project.layers:
		layer_option_button.add_item(layer.name)
	_syncing = false


func _refresh_list(select_index := -1) -> void:
	_syncing = true
	tag_list.clear()
	var project := Global.current_project
	for tag in project.region_tags:
		tag_list.add_item(_get_tag_label(tag), _get_tag_icon(tag))
	if select_index >= 0 and select_index < tag_list.item_count:
		tag_list.select(select_index)
	_syncing = false
	_populate_editors(_selected_tag())


# 커스텀 변경. by kojeomstudio — 목록 항목 라벨/아이콘 조합을 헬퍼로 분리(부분 갱신 재사용).
func _get_tag_label(tag: RegionTag) -> String:
	var frame_range := (
		str(tag.from_frame)
		if tag.from_frame == tag.to_frame
		else "%d-%d" % [tag.from_frame, tag.to_frame]
	)
	var tag_name := tag.name if not tag.name.is_empty() else "-"
	var label := "%s  (F%s)" % [tag_name, frame_range]
	if not tag.visible:
		label += "  (" + tr("hidden") + ")"
	return label


func _get_tag_icon(tag: RegionTag) -> ImageTexture:
	var icon := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var icon_color := tag.color
	icon_color.a = 1.0
	icon.fill(icon_color)
	return ImageTexture.create_from_image(icon)


# 커스텀 변경. by kojiomstudio — 편집마다 전체 목록을 재구성하면 텍스트 입력 중 커서가
# 끝으로 튀고 스크롤이 리셋되므로, 선택 항목의 라벨/아이콘만 갱신한다.
func _update_selected_item_label() -> void:
	var selected := tag_list.get_selected_items()
	if selected.is_empty() or selected[0] >= Global.current_project.region_tags.size():
		return
	var tag := Global.current_project.region_tags[selected[0]]
	tag_list.set_item_text(selected[0], _get_tag_label(tag))
	tag_list.set_item_icon(selected[0], _get_tag_icon(tag))


func _selected_tag() -> RegionTag:
	var selected := tag_list.get_selected_items()
	if selected.is_empty():
		return null
	var tags := Global.current_project.region_tags
	if selected[0] >= tags.size():
		return null
	return tags[selected[0]]


func _select_tag(index: int) -> void:
	if index >= 0 and index < tag_list.item_count:
		tag_list.select(index)
	_populate_editors(_selected_tag())


func _on_tag_selected(_index: int) -> void:
	if _syncing:
		return
	_populate_editors(_selected_tag())


## 선택한 태그의 값을 편집기에 채운다.
func _populate_editors(tag: RegionTag) -> void:
	_syncing = true
	var has_tag := tag != null
	for control: Control in [
		name_line_edit,
		color_picker_button,
		layer_option_button,
		from_frame_spin_box,
		to_frame_spin_box,
		x_spin_box,
		y_spin_box,
		width_spin_box,
		height_spin_box,
		user_data_text_edit,
		visible_check_box
	]:
		# 커스텀 변경. by kojeomstudio — 버튼 계열은 disabled, 입력 계열(LineEdit/TextEdit/SpinBox)은
		# editable 프로퍼티를 쓴다. 잘못된 대입은 함수 중단(_syncing 갇힘)을 유발하므로 타입별 분기.
		if control is BaseButton:
			(control as BaseButton).disabled = not has_tag
		else:
			control.set("editable", has_tag)
	if not has_tag:
		_syncing = false
		return
	name_line_edit.text = tag.name
	color_picker_button.color = tag.color
	layer_option_button.selected = clampi(tag.layer + 1, 0, layer_option_button.item_count - 1)
	from_frame_spin_box.value = tag.from_frame
	to_frame_spin_box.value = tag.to_frame
	x_spin_box.value = tag.rect.position.x
	y_spin_box.value = tag.rect.position.y
	width_spin_box.value = tag.rect.size.x
	height_spin_box.value = tag.rect.size.y
	user_data_text_edit.text = tag.user_data
	visible_check_box.button_pressed = tag.visible
	_syncing = false


## 편집 내용을 태그에 반영하고 오버레이/목록을 갱신한다.
func _apply_edit(property: Callable, value: Variant) -> void:
	if _syncing:
		return
	var tag := _selected_tag()
	if tag == null:
		return
	property.call(tag, value)
	# setter를 다시 통과시켜 region_tags_changed 신호 → 캔버스 오버레이 갱신.
	Global.current_project.region_tags = Global.current_project.region_tags
	_update_selected_item_label()


func _on_name_changed(text: String) -> void:
	_apply_edit(func(tag: RegionTag, v: String) -> void: tag.name = v, text)


func _on_color_changed(color: Color) -> void:
	_apply_edit(func(tag: RegionTag, v: Color) -> void: tag.color = v, color)


func _on_layer_selected(index: int) -> void:
	_apply_edit(func(tag: RegionTag, v: int) -> void: tag.layer = v - 1, index)


func _on_from_frame_changed(value: float) -> void:
	var frame := clampi(int(value), 1, maxi(Global.current_project.frames.size(), 1))
	_apply_edit(func(tag: RegionTag, v: int) -> void: tag.from_frame = v, frame)
	if _selected_tag() != null and _selected_tag().to_frame < frame:
		to_frame_spin_box.value = frame


func _on_to_frame_changed(value: float) -> void:
	var frame := clampi(int(value), 1, maxi(Global.current_project.frames.size(), 1))
	_apply_edit(func(tag: RegionTag, v: int) -> void: tag.to_frame = maxi(v, 1), frame)
	if _selected_tag() != null and _selected_tag().from_frame > frame:
		from_frame_spin_box.value = frame


func _on_x_changed(value: float) -> void:
	_apply_edit(_set_rect_part.bind("position:x"), int(value))


func _on_y_changed(value: float) -> void:
	_apply_edit(_set_rect_part.bind("position:y"), int(value))


func _on_width_changed(value: float) -> void:
	_apply_edit(_set_rect_part.bind("size:x"), int(value))


func _on_height_changed(value: float) -> void:
	_apply_edit(_set_rect_part.bind("size:y"), int(value))


## Rect2i는 값 타입이라 부분 수정을 헬퍼로 처리한다.
## 커스텀 변경. by kojiomstudio — Callable.bind 는 인자 뒤에 붙으므로 part 를 마지막으로.
func _set_rect_part(tag: RegionTag, value: int, part: String) -> void:
	var rect := tag.rect
	match part:
		"position:x":
			rect.position.x = value
		"position:y":
			rect.position.y = value
		"size:x":
			rect.size.x = maxi(value, 0)
		"size:y":
			rect.size.y = maxi(value, 0)
	tag.rect = rect


func _on_user_data_changed() -> void:
	_apply_edit(
		func(tag: RegionTag, v: String) -> void: tag.user_data = v, user_data_text_edit.text
	)


func _on_visible_toggled(button_pressed: bool) -> void:
	_apply_edit(func(tag: RegionTag, v: bool) -> void: tag.visible = v, button_pressed)


func _on_add_pressed() -> void:
	_add_tag(Rect2i(Vector2i.ZERO, Vector2i.ONE), false)


## 현재 선택 영역을 태그로 만든다. 선택이 없으면 알림만 표시한다.
func _on_add_from_selection_pressed() -> void:
	var project := Global.current_project
	if not project.has_selection:
		Global.notification_label(tr("There is no selection to create a region tag from."))
		return
	var rect := project.selection_map.get_selection_rect(project)
	rect = rect.intersection(Rect2i(Vector2i.ZERO, project.size))
	if not rect.has_area():
		Global.notification_label(tr("The selection is outside of the canvas boundaries."))
		return
	_add_tag(rect, true)


func _add_tag(rect: Rect2i, from_selection: bool) -> void:
	var project := Global.current_project
	var color := Color.from_string(
		RegionTag.DEFAULT_COLORS[project.region_tags.size() % RegionTag.DEFAULT_COLORS.size()],
		Color.WHITE
	)
	# 새 태그는 기본적으로 현재 프레임에만 적용된다(모션별 태깅). 다이얼로그에서 범위 조정.
	var current_frame := project.current_frame + 1
	var new_tag := RegionTag.new(
		"region_%d" % (project.region_tags.size() + 1),
		color,
		rect,
		-1,
		current_frame,
		current_frame
	)
	project.region_tags.append(new_tag)
	project.region_tags = project.region_tags
	_refresh_list(project.region_tags.size() - 1)
	if not from_selection:
		name_line_edit.grab_focus()
		name_line_edit.select_all()


func _on_delete_pressed() -> void:
	var selected := tag_list.get_selected_items()
	if selected.is_empty():
		return
	var project := Global.current_project
	project.region_tags.remove_at(selected[0])
	project.region_tags = project.region_tags
	_refresh_list()
	_select_tag(selected[0])
