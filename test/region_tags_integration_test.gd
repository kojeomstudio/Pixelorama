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
	# 기본 옵션: 이름 자동(region_1), 현재 프레임(1), 전체 레이어(-1)
	var expected := Rect2i(3, 4, 8, 11)
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
