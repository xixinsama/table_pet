extends Node2D

@onready var pet: Pet = $Pet
@onready var menu: Control = $menu
@onready var quit_button: Button = $menu/Panel/VBoxContainer/QuitButton
@onready var model_loading: Label = $menu/Panel/VBoxContainer/ModelLoading
@onready var model_button: Button = $menu/Panel/VBoxContainer/ModelButton
@onready var model_popup: PopupMenu = $menu/Panel/VBoxContainer/ModelPopup
@onready var text_edit: TextEdit = $menu/Panel/VBoxContainer/TextEdit
@onready var send_button: Button = $menu/Panel/VBoxContainer/SendButton

# 拖拽状态变量
var is_dragging: bool = false
var drag_offset: Vector2 = Vector2.ZERO
var local_mouse_pos: Vector2 = Vector2.ZERO 

# 随机游走变量
var is_moving: bool = false:
	set(value):
		var direct: Vector2 = target_position - Vector2(get_window().position)
		if value == true:
			if randi_range(0, 1) == 1:
				pet.anime_play("walk", direct)
			else:
				pet.anime_play("crouch", direct)
		else:
			pet.anime_play("idle", direct)
		is_moving = value
var target_position: Vector2 = Vector2.ZERO
var move_speed: float = 360.0  # 像素/秒
var wander_timer: float = 0.0
var wander_interval: float = 15.0

func _ready():
	# 初始隐藏菜单
	menu.visible = false
	
	# 连接输入事件信号
	pet.input_event.connect(_on_drag_area_input)
	model_popup.id_pressed.connect(_on_model_selected)
	# 初始化随机位置
	target_position = get_random_screen_position()
	
	# 连接模型加载信号
	OllamaClient.models_loaded.connect(_on_models_loaded)
	
	# 如果OllamaClient尚未加载模型，尝试加载，再次请求
	if OllamaClient.available_models.size() == 0:
		OllamaClient.load_available_models()
	else:
		_on_models_loaded(OllamaClient.available_models)

# 当模型加载完成时调用
func _on_models_loaded(models: Array):
	# 更新UI
	model_popup.position = get_window().position 
	model_loading.visible = false
	model_button.visible = true
	model_popup.visible = true
	text_edit.visible = true
	send_button.visible = true
	
	# 初始化模型选择菜单
	init_model_menu(models)
	
	# 设置初始模型
	if OllamaClient.current_model.is_empty() and models.size() > 0:
		OllamaClient.current_model = models[0]
	
	if models.size() > 0:
		model_button.text = "模型: " + get_model_display_name(OllamaClient.current_model)
	else:
		model_button.text = "没有可用模型"

# 初始化模型选择菜单
func init_model_menu(models: Array):
	model_popup.clear()
	for model in models:
		model_popup.add_item(get_model_display_name(model))

# 获取模型显示名称（简化）
func get_model_display_name(full_name: String) -> String:
	var parts = full_name.split(":")
	if parts.size() > 0:
		return parts[0].capitalize()
	return full_name

func _process(delta):
	if is_dragging:
		# 获取鼠标在屏幕上的绝对位置
		var mouse_pos = DisplayServer.mouse_get_position()
		# 更新窗口位置（考虑拖拽偏移量）
		get_window().position = Vector2(mouse_pos) - drag_offset
	else:
		# 处理随机游走
		handle_random_wander(delta)

# 处理随机游走
func handle_random_wander(delta):
	# 只有不移动时，计时增加
	if not is_moving: wander_timer += delta
	
	# 检查是否到达目标位置
	if get_window().position.distance_to(target_position) < 10:
		is_moving = false
	
	# 时间到或到达目标位置后，设置新的目标位置
	if wander_timer >= wander_interval:
		wander_timer = 0.0
		target_position = get_random_screen_position()
		is_moving = true
	
	# 向目标位置移动
	if is_moving:
		var direction = (target_position - Vector2(get_window().position)).normalized()
		var movement = direction * move_speed * delta
		get_window().position += Vector2i(movement)

# 获取屏幕内的随机位置
func get_random_screen_position() -> Vector2:
	var screen_size = DisplayServer.screen_get_size()
	var window_size = get_window().size
	
	# 确保窗口不会移出屏幕
	var max_x = screen_size.x - window_size.x
	var max_y = screen_size.y - window_size.y
	
	return Vector2(
		randi_range(0, max_x),
		randi_range(0, max_y)
	)

# 处理输入事件
func _on_drag_area_input(_viewport, event, _shape_idx):
	if event is InputEventMouseButton:
		# 左键拖拽
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 开始拖拽
				is_dragging = true
				is_moving = false  # 停止随机移动
				# 计算鼠标相对于宠物区域的偏移量
				local_mouse_pos = pet.get_local_mouse_position()
				# 转换为窗口位置偏移
				drag_offset = pet.global_position + local_mouse_pos
			else:
				# 结束拖拽
				is_dragging = false
				wander_timer = randf_range(0, wander_interval)
		# 右键菜单
		elif event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			toggle_menu()

# 切换菜单显示状态
func toggle_menu():
	menu.visible = !menu.visible
		
	# 确保菜单不会超出屏幕
	var screen_size = get_viewport_rect().size
	if menu.position.x + menu.size.x > screen_size.x:
		menu.position.x = screen_size.x - menu.size.x
	if menu.position.y + menu.size.y > screen_size.y:
		menu.position.y = screen_size.y - menu.size.y

func _on_text_edit_text_changed() -> void:
	# 获取文本内容
	var text_content = text_edit.text
	
	# 检查是否有文本
	if text_content.strip_edges().is_empty():
		printerr("没有文本可保存", false)
		return
	
	# 获取下载目录路径
	var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	
	# 生成文件名（带时间戳）
	var datetime = Time.get_datetime_dict_from_system()
	var filename = "DINO.txt"
	
	# 创建完整文件路径
	var file_path = downloads_path.path_join(filename)
	
	# 保存文件
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	
	if file != null:
		file.store_string(text_content)
		file.close()
		print("文件已保存到: " + file_path)
	else:
		var error = FileAccess.get_open_error()
		print("保存失败: 错误代码 " + str(error))

# 模型选择按钮按下
func _on_model_button_pressed() -> void:
	# 确保有模型可用
	if OllamaClient.available_models.size() > 0:
		# 显示模型选择菜单
		model_popup.position = Vector2(get_window().position) + model_button.global_position + Vector2(0, model_button.size.y)
		model_popup.size.x = model_button.size.x
		model_popup.popup()

# 模型选择菜单项被选中
func _on_model_selected(id: int) -> void:
	if id < OllamaClient.available_models.size():
		var selected_model = OllamaClient.available_models[id]
		OllamaClient.current_model = selected_model
		model_button.text = "模型: " + get_model_display_name(selected_model)
		print("已选择模型: ", selected_model)

# 发送信息按钮被按下
func _on_send_button_pressed() -> void:
	pet.load_and_send_file()
	menu.hide()

func _on_quit_button_pressed() -> void:
	get_tree().quit()
