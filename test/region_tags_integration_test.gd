# 커스텀 추가. by kojeomstudio
# 영역 태그 기능의 헤드리스 통합 테스트. 메인 씬이 완전히 기동된 실제 환경(autoload 포함)에서
# 오버레이 생성, 다이얼로그 UI 구성/편집 흐름, 직렬화/역직렬화, .pxo 저장/로드 라운드트립을 검증한다.
#
# 실행 방법:
# 1) project.godot의 [autoload] 섹션 마지막에 임시로 한 줄 추가:
#    RegionTagsTest="*res://test/region_tags_integration_test.gd"
# 2) godot --headless --path . 실행 (스크립트가 스스로 종료하며 종료 코드로 성패 판단)
# 3) 테스트 후 project.godot의 해당 줄 제거(원복)
#
# 결과는 "REGION_TAGS_INTEGRATION: PASS/FAIL" 로 출력된다.
extends Node

var _failures: Array[String] = []


func _ready() -> void:
	# 메인 씬(UI/캔버스/오버레이) 구성이 끝나기를 기다린다.
	for i in 15:
		await get_tree().process_frame
	await _test_overlay()
	await _test_tool()
	await _test_tool_click_only_blocked()
	await _test_eraser()
	await _test_naming_and_sorting()
	await _test_dialog_flow()
	await _test_serialization()
	await _test_pxo_roundtrip()
	var result := "PASS" if _failures.is_empty() else "FAIL"
	print("REGION_TAGS_INTEGRATION: ", result)
	for failure in _failures:
		print("  - ", failure)
	get_tree().quit(0 if _failures.is_empty() else 1)


## Region Tag 도구: 등록/할당 + 드래그 시뮬레이션으로 태그 생성과 undo 를 검증한다.
func _test_tool() -> void:
	if not Tools.tools.has("RegionTag"):
		_fail("tool: Tools.tools 에 RegionTag 미등록")
		return
	Tools.assign_tool("RegionTag", MOUSE_BUTTON_LEFT)
	var tool := Tools.get_tool(MOUSE_BUTTON_LEFT).tool_node
	if tool == null:
		_fail("tool: tool_node 미할당")
		return
	var project := Global.current_project
	project.region_tags = []
	tool.draw_start(Vector2i(3, 4))
	tool.draw_move(Vector2i(10, 14))
	tool.draw_end(Vector2i(10, 14))
	if project.region_tags.size() != 1:
		_fail("tool: 드래그 후 태그 미생성 (size=%d)" % project.region_tags.size())
		return
	var tag := project.region_tags[0]
	# 기본 옵션: 이름 자동(region_0_0), 현재 프레임(1), 전체 레이어(-1)
	var expected := Rect2i(3, 4, 8, 11)
	if tag.name != "region_0_0":
		_fail("tool: 자동 네이밍 오류 (name=%s)" % tag.name)
	if tag.rect != expected or tag.layer != -1 or tag.from_frame != 1:
		_fail(
			"tool: 태그 필드 오류 (rect=%s layer=%d from=%d)" % [str(tag.rect), tag.layer, tag.from_frame]
		)
	if not project.undo_redo.has_undo():
		_fail("tool: 태그 생성이 undo 액션으로 커밋되지 않음")
	else:
		project.undo_redo.undo()
		if project.region_tags.size() != 0:
			_fail("tool: undo 후 태그 잔존 (size=%d)" % project.region_tags.size())


## 네이밍 컨벤션(부위_레이어_프레임) + 계층 정렬(레이어→프레임→이름) + 다중 부위 컬렉션 검증.
func _test_naming_and_sorting() -> void:
	if RegionTag.compose_name("head", 0, 0) != "head_0_0":
		_fail("naming: head_0_0 컨벤션 오류 (%s)" % RegionTag.compose_name("head", 0, 0))
	if RegionTag.compose_name("head", 0, 1) != "head_0_1":
		_fail("naming: head_0_1 컨벤션 오류")
	if RegionTag.compose_name("", 2, 3) != "region_2_3":
		_fail("naming: 빈 base 기본값 오류")
	var project := Global.current_project
	# 같은 레이어의 프레임별 태그(head_0_0/head_0_1) + 같은 프레임 다중 부위(body/ear) + 레이어 스코프(arm)
	project.region_tags = [
		RegionTag.new("head_0_1", Color.RED, Rect2i(1, 1, 4, 4), -1, 2, 2),
		RegionTag.new("head_0_0", Color.RED, Rect2i(1, 2, 4, 4), -1, 1, 1),
		RegionTag.new("ear_0_0", Color.GREEN, Rect2i(3, 3, 2, 2), -1, 1, 1),
		RegionTag.new("body_0_0", Color.BLUE, Rect2i(2, 2, 4, 4), -1, 1, 1),
		RegionTag.new("arm_0_0", Color.CYAN, Rect2i(4, 4, 2, 2), 1, 1, 1),
	]
	project.sort_region_tags()
	var names := []
	for tag in project.region_tags:
		names.append(tag.name)
	var expected_order := ["body_0_0", "ear_0_0", "head_0_0", "head_0_1", "arm_0_0"]
	if names != expected_order:
		_fail("sorting: 계층 정렬 오류 (%s)" % str(names))
	# 직렬화 결과도 정렬 순서 유지 확인
	var region_data: Array = project.serialize()["region_tags"]
	var serialized_names := []
	for entry in region_data:
		serialized_names.append(entry["name"])
	if serialized_names != expected_order:
		_fail("sorting: 직렬화 정렬 오류 (%s)" % str(serialized_names))
	project.region_tags = []


## 클릭만으로는 1x1 태그가 만들어지지 않는지 검증한다.
func _test_tool_click_only_blocked() -> void:
	Tools.assign_tool("RegionTag", MOUSE_BUTTON_LEFT)
	var tool := Tools.get_tool(MOUSE_BUTTON_LEFT).tool_node
	var project := Global.current_project
	project.region_tags = []
	tool.draw_start(Vector2i(5, 5))
	tool.draw_end(Vector2i(5, 5))
	if project.region_tags.size() != 0:
		_fail("click_only: 클릭만으로 태그가 생성됨 (size=%d)" % project.region_tags.size())


## 태그 지우개: 클릭 지점 태그 삭제와 undo 복구를 검증한다.
func _test_eraser() -> void:
	if not Tools.tools.has("RegionTagEraser"):
		_fail("eraser: Tools.tools 에 RegionTagEraser 미등록")
		return
	Tools.assign_tool("RegionTagEraser", MOUSE_BUTTON_LEFT)
	var eraser := Tools.get_tool(MOUSE_BUTTON_LEFT).tool_node
	var project := Global.current_project
	project.region_tags = [
		RegionTag.new("head_0_0", Color.RED, Rect2i(2, 2, 6, 6), -1, 1, 1),
		RegionTag.new("body_0_0", Color.BLUE, Rect2i(10, 10, 6, 6), -1, 1, 1),
	]
	project.region_tags = project.region_tags
	eraser.draw_start(Vector2i(3, 3))  # head 태그 내부 클릭
	if project.region_tags.size() != 1 or project.region_tags[0].name != "body_0_0":
		_fail(
			(
				"eraser: 클릭 태그 미삭제 (size=%d first=%s)"
				% [
					project.region_tags.size(),
					project.region_tags[0].name if project.region_tags.size() > 0 else "-"
				]
			)
		)
	eraser.draw_end(Vector2i(3, 3))
	if not project.undo_redo.has_undo():
		_fail("eraser: 삭제가 undo 액션으로 커밋되지 않음")
	else:
		project.undo_redo.undo()
		if project.region_tags.size() != 2:
			_fail("eraser: undo 후 복원 실패 (size=%d)" % project.region_tags.size())
	project.region_tags = []


func _fail(message: String) -> void:
	_failures.append(message)


## 캔버스 오버레이 노드 생성 및 표시 토글 동작 확인.
func _test_overlay() -> void:
	if not is_instance_valid(Global.canvas.region_tags_overlay):
		_fail("overlay: canvas.region_tags_overlay 가 유효하지 않음")
		return
	Global.show_region_tags = false
	Global.show_region_tags = true


## 다이얼로그 UI 구성 + 추가/편집/undo 커밋 흐름 확인.
func _test_dialog_flow() -> void:
	var dialog: RegionTagsDialog = load("res://src/UI/Dialogs/RegionTagsDialog.tscn").instantiate()
	Global.control.add_child(dialog)
	await get_tree().process_frame  # _ready(_build_ui) 실행 대기
	if dialog.tag_list == null or dialog.name_line_edit == null or dialog.x_spin_box == null:
		_fail("dialog_flow: UI 가 구성되지 않음")
		dialog.queue_free()
		return
	var project := Global.current_project
	project.region_tags = []
	dialog._on_about_to_popup()  # 스냅샷 촬영
	dialog._on_add_pressed()
	if project.region_tags.size() != 1:
		_fail("dialog_flow: 태그 추가 실패 (size=%d)" % project.region_tags.size())
		dialog.queue_free()
		return
	var tag := project.region_tags[0]
	dialog._on_name_changed("head")
	dialog._on_x_changed(5.0)
	dialog._on_y_changed(6.0)
	dialog._on_width_changed(10.0)
	dialog._on_height_changed(12.0)
	dialog._on_visible_toggled(false)
	var expected_rect := Rect2i(5, 6, 10, 12)
	if tag.name != "head" or tag.rect != expected_rect or tag.visible:
		_fail(
			(
				"dialog_flow: 편집 반영 오류 (name=%s rect=%s visible=%s)"
				% [tag.name, str(tag.rect), str(tag.visible)]
			)
		)
	var list_text: String = dialog.tag_list.get_item_text(0)
	if not list_text.contains("head") or not list_text.contains(tr("hidden")):
		_fail("dialog_flow: 목록 라벨 갱신 오류 (%s)" % list_text)
	dialog._on_confirmed()  # 단일 undo 액션으로 커밋
	if not project.undo_redo.has_undo():
		_fail("dialog_flow: 확인 시 undo 액션이 커밋되지 않음")
	else:
		project.undo_redo.undo()
		if project.region_tags.size() != 0:
			_fail("dialog_flow: undo 가 스냅샷을 복원하지 못함 (size=%d)" % project.region_tags.size())
	dialog.queue_free()


## Project 직렬화에 region_tags 포함 + 탭 인덴트 확인.
func _test_serialization() -> void:
	var project := Global.current_project
	var tag := RegionTag.new("head", Color(1, 0, 0), Rect2i(2, 3, 8, 8), -1, 1, 2)
	project.region_tags = [tag]
	var dict := project.serialize()
	if not dict.has("region_tags") or dict.region_tags.is_empty():
		_fail("serialize: 직렬화 결과에 region_tags 없음")
		return
	var tag_dict: Dictionary = dict.region_tags[0]
	if tag_dict.get("name") != "head" or tag_dict.get("from_frame") != 1:
		_fail("serialize: 태그 필드 직렬화 오류 (%s)" % str(tag_dict))
	elif tag_dict.get("to_frame") != 2:
		_fail("serialize: to_frame 직렬화 오류 (%s)" % str(tag_dict))
	var json := JSON.stringify(dict, "\t")
	if not json.contains('\n\t"region_tags"'):
		_fail("serialize: 탭 인덴트가 적용되지 않음")


## 실제 .pxo 저장/로드 라운드트립 + data.json 인덴트/내용 확인.
func _test_pxo_roundtrip() -> void:
	var project := Global.current_project
	var tag := RegionTag.new("body", Color(0, 1, 0), Rect2i(10, 11, 20, 21), -1, 1, 1)
	project.region_tags = [tag]
	var path := OS.get_user_data_dir().path_join("region_tags_integration_test.pxo")
	if not OpenSave.save_pxo_file(path, false, false, project):
		_fail("pxo: save_pxo_file 실패")
		return
	var zip_reader := ZIPReader.new()
	if zip_reader.open(path) != OK:
		_fail("pxo: 저장된 파일 재오픈 실패")
		return
	var data_json := zip_reader.read_file("data.json").get_string_from_utf8()
	zip_reader.close()
	if not data_json.contains('\n\t"region_tags"'):
		_fail("pxo: data.json 에 탭 인덴트/region_tags 없음")
	OpenSave.open_pxo_file(path)
	var loaded := Global.current_project
	if loaded.region_tags.size() != 1:
		_fail("pxo: 로드 후 region_tags 복원 실패 (size=%d)" % loaded.region_tags.size())
		return
	var restored := loaded.region_tags[0]
	if restored.name != "body" or restored.rect != Rect2i(10, 11, 20, 21):
		_fail("pxo: 복원된 태그 필드 불일치 (name=%s rect=%s)" % [restored.name, str(restored.rect)])
	DirAccess.remove_absolute(path)
