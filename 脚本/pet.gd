extends Area2D
class_name Pet

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var name_label: Label = $CanvasLayer/NameLabel
@onready var dialogue: RichTextLabel = $CanvasLayer/Dialogue


func _ready():
	OllamaClient.response_received.connect(_on_ai_response)
	
func load_and_send_file():
	var downloads_path = OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS).path_join("/DINO.txt")
	#print(downloads_path)
	#print(FileAccess.file_exists(downloads_path))
	var file = FileAccess.open(downloads_path, FileAccess.READ)
	if file:
		var content = file.get_as_text()
		print(content)
	#input_box.text = content  # 显示在输入框
		OllamaClient.send_prompt(content)
	
func _on_ai_response(response: String):
	print(response)
	dialogue.text = response
	# 可选：添加打字机效果
	animate_text(response)  

func animate_text(text: String):
	dialogue.visible_characters = 0
	dialogue.text = text
	for i in len(text):
		dialogue.visible_characters += 1
		await get_tree().create_timer(0.02).timeout

func _on_mouse_entered() -> void:
	name_label.visible = true

func _on_mouse_exited() -> void:
	name_label.visible = false
