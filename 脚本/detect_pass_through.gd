extends Node
var _api

func _ready() -> void:
	_api = get_node("/root/ClickThrough")
	_api.SetClickThrough(true)

func _process(_delta: float) -> void:
	DetectPassthrough()

func DetectPassthrough():
	var viewport = get_viewport()
	var img =viewport.get_texture().get_image()
	var rect=viewport.get_visible_rect()
	
	var mouse_position = viewport.get_mouse_position()
	var viewX=int((int(mouse_position.x)+ rect.position.x))
	var viewY=int((int(mouse_position.y)+ rect.position.y))
	
	var x = (int)(img.get_size().x * viewX / rect.size.x)
	var y = (int)(img.get_size().y * viewY / rect.size.y)
	
	if x < img.get_size().x && x>=0 && y< img.get_size().y && y>=0:
		var pixel = img.get_pixel(x, y)
		if pixel.a > 0.5:
			set_click_ability(true)
		else:
			set_click_ability(false)

var click_through = true
func set_click_ability(clickable:bool):
	if clickable != click_through:
		click_through = clickable
		_api.SetClickThrough(!clickable)
