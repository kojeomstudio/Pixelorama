# 커스텀 추가. by kojeomstudio
# 태그 지우개 도구. 지우개처럼 클릭 또는 드래그로 지나가는 지점이 속한 영역 태그를
# 즉시 삭제한다. 삭제는 하나의 undo 액션("Erase Region Tags")으로 커밋되어 Ctrl+Z 로
# 전체 복구할 수 있다. 현재 프레임/레이어에 적용되는 태그만 대상으로 한다.
extends BaseTool
## Region Tag Eraser tool, erases region tags like an eraser.
##
## Click or drag over tagged regions to remove them. Erased tags are committed
## as a single undoable action when the stroke ends.

var _stroke_backup: Array[RegionTag] = []  ## 스트로크 시작 시 전체 태그 스냅샷
var _stroke_erased := false


func draw_start(pos: Vector2i) -> void:
	super.draw_start(pos)
	_stroke_backup = _duplicate_tags(Global.current_project.region_tags)
	_stroke_erased = false
	_erase_at(pos)


func draw_move(pos: Vector2i) -> void:
	super.draw_move(pos)
	_erase_at(pos)


func draw_end(_pos: Vector2i) -> void:
	super.draw_end(_pos)
	if _stroke_erased:
		_commit_stroke()
	_reset_stroke()


func cancel_tool() -> void:
	super()
	if _stroke_erased:
		# 취소 시 스트로크 시작 상태로 되돌린다(undo 히스토리 오염 방지).
		Global.current_project.region_tags = _duplicate_tags(_stroke_backup)
	_reset_stroke()


## 지점이 속한 태그(현재 프레임/레이어 매칭, 표시 중)를 즉시 지운다.
func _erase_at(pos: Vector2i) -> void:
	var project := Global.current_project
	if Global.mirror_view:  # 미러 뷰에서도 실제 태그 좌표에 맞춘다.
		pos.x = project.size.x - pos.x - 1
	var remaining: Array[RegionTag] = []
	for tag in project.region_tags:
		if (
			tag.visible
			and tag.applies_to(project.current_frame, project.current_layer)
			and tag.rect.has_point(pos)
		):
			_stroke_erased = true
		else:
			remaining.append(tag)
	if remaining.size() != project.region_tags.size():
		project.region_tags = remaining


## 스트로크 전체를 하나의 undo 액션으로 커밋한다.
func _commit_stroke() -> void:
	var project := Global.current_project
	var undo_tags := _duplicate_tags(_stroke_backup)
	var redo_tags := _duplicate_tags(project.region_tags)
	project.undo_redo.create_action("Erase Region Tags")
	project.undo_redo.add_do_property(project, "region_tags", redo_tags)
	project.undo_redo.add_undo_property(project, "region_tags", undo_tags)
	project.undo_redo.commit_action()


func _reset_stroke() -> void:
	_stroke_backup = []
	_stroke_erased = false


func _duplicate_tags(tags: Array[RegionTag]) -> Array[RegionTag]:
	var result: Array[RegionTag] = []
	for tag in tags:
		result.append(tag.duplicate())
	return result
