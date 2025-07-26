# 基于HTTPCLient实现的版本
extends Node
 
const HOST = "localhost"
const PORT = 11434
const API_PATH = "/api/generate"
const MODELS_PATH = "/api/tags"
 
# 信号定义
signal response_received(message: String)
signal error_occurred(message: String)
signal models_loaded(models: Array)
 
var http_client: HTTPClient
var is_connected: bool = false
var current_request: Dictionary = {}
var pending_requests: Array = []
var response_buffer: PackedByteArray = PackedByteArray()
var current_cache_key: String = ""
var response_cache: Dictionary = {}  # 缓存字典
 
# 当前选择的模型
var current_model: String = ""
# 可用的模型列表
var available_models: Array = []
var connection_attempts: int = 0
 
func _ready():
	http_client = HTTPClient.new()
	http_client.set_blocking_mode(false)  # 非阻塞模式
	_connect_to_host()
 
func _connect_to_host():
	print("尝试连接到Ollama...")
	var err = http_client.connect_to_host(HOST, PORT)
	if err == OK:
		print("连接初始化成功")
		connection_attempts = 0
	else:
		push_error("连接错误: " + str(err))
		connection_attempts += 1
		
		# 指数退避重试
		var wait_time = min(5.0 * pow(2, connection_attempts - 1), 30.0)
		get_tree().create_timer(wait_time).timeout.connect(_connect_to_host)
		print("将在", wait_time, "秒后重试连接...")
 
func _process(delta):
	http_client.poll()
 
	# 处理连接状态
	var status = http_client.get_status()
	# print("HTTPClient 状态: ", _get_status_name(status))
 
	match status:
		HTTPClient.STATUS_DISCONNECTED:
			if is_connected:
				is_connected = false
				print("连接断开，尝试重新连接...")
				_connect_to_host()
			elif !is_connected:
				# 初始连接
				_connect_to_host()
		
		HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING:
			pass  # 等待连接
		
		HTTPClient.STATUS_CONNECTED:
			if !is_connected:
				is_connected = true
				print("成功连接到Ollama")
				# 加载模型列表
				_enqueue_request({"type": "models"})
		
		HTTPClient.STATUS_REQUESTING:
			pass  # 请求进行中
		
		HTTPClient.STATUS_BODY:
			_read_response_body()
		
		HTTPClient.STATUS_CONNECTION_ERROR:
			print("连接错误，尝试重新连接...")
			is_connected = false
			_connect_to_host()
 
	# 处理新请求
	if is_connected && pending_requests.size() > 0 && current_request.is_empty():
		current_request = pending_requests.pop_front()
		_send_request(current_request)
 
# 获取状态名称（用于调试）
func _get_status_name(status: int) -> String:
	match status:
		HTTPClient.STATUS_DISCONNECTED: return "DISCONNECTED"
		HTTPClient.STATUS_RESOLVING: return "RESOLVING"
		HTTPClient.STATUS_CONNECTING: return "CONNECTING"
		HTTPClient.STATUS_CONNECTED: return "CONNECTED"
		HTTPClient.STATUS_REQUESTING: return "REQUESTING"
		HTTPClient.STATUS_BODY: return "BODY"
		HTTPClient.STATUS_CONNECTION_ERROR: return "CONNECTION_ERROR"
		_: return "UNKNOWN (" + str(status) + ")"
 
# 加载可用的模型列表
func load_available_models():
	_enqueue_request({"type": "models"})
 
# 发送提示
func send_prompt(prompt: String):
	if current_model.is_empty():
		if available_models.size() > 0:
			current_model = available_models[0]
		else:
			error_occurred.emit("没有可用的模型")
			return
 
	_enqueue_request({"type": "generate", "prompt": prompt})
 
# 将请求加入队列
func _enqueue_request(request: Dictionary):
	# 如果是生成请求，检查缓存
	if request["type"] == "generate":
		var cache_key = request["prompt"].sha256_text() + current_model
		if cache_key in response_cache:
			# 延迟发出信号，避免在_process中处理UI
			call_deferred("emit_signal", "response_received", response_cache[cache_key])
			return
		current_cache_key = cache_key
 
	pending_requests.append(request)
	print("请求已加入队列: ", request["type"])
 
# 发送请求
func _send_request(request: Dictionary):
	print("发送请求: ", request["type"])
 
	var path = MODELS_PATH if request["type"] == "models" else API_PATH
	var method = HTTPClient.METHOD_GET if request["type"] == "models" else HTTPClient.METHOD_POST
	var headers = [
		"Content-Type: application/json",
		"Connection: keep-alive",
		"Accept-Encoding: gzip"
	]
 
	var body = ""
	if request["type"] == "generate":
		body = JSON.stringify({
			"model": current_model,
			"prompt": request["prompt"],
			"stream": false
		})
 
	var err = http_client.request(method, path, headers, body)
	if err != OK:
		error_occurred.emit("请求失败: " + str(err))
		current_request = {}
		print("请求错误: ", err)
	else:
		print("请求已发送: ", path)
 
# 读取响应体
func _read_response_body():
	# 检查是否有数据可读
	#var bytes_available = http_client.get_available_bytes()
	#if bytes_available > 0:
	var chunk = http_client.read_response_body_chunk()
	if chunk.size() > 0:
		response_buffer.append_array(chunk)
		print("收到数据块: ", chunk.size(), "字节")
 
	# 检查是否完成
	if http_client.get_status() != HTTPClient.STATUS_BODY:
		if response_buffer.size() > 0:
			_process_full_response()
		else:
			print("响应完成，但无数据")
		response_buffer = PackedByteArray()
		current_request = {}
		print("请求完成")
 
# 处理完整的响应
func _process_full_response():
	print("处理完整响应，大小: ", response_buffer.size(), "字节")
 
	var response_str = response_buffer.get_string_from_utf8()
	if !response_str:
		error_occurred.emit("空响应")
		print("空响应")
		return
 
	print("原始响应: ", response_str)
 
	var json = JSON.new()
	var parse_error = json.parse(response_str)
	if parse_error != OK:
		var error_msg = "JSON解析错误: " + json.get_error_message() + "\nResponse: " + response_str
		error_occurred.emit(error_msg)
		print(error_msg)
		return
 
	var data = json.get_data()
 
	if current_request["type"] == "models":
		_handle_models_response(data)
	else:
		_handle_generate_response(data)
 
# 处理模型列表响应
func _handle_models_response(data):
	print("处理模型列表响应")
 
	if data and data.has("models"):
		available_models = []
		for model_data in data["models"]:
			if model_data.has("name"):
				available_models.append(model_data["name"])
				print("发现模型: ", model_data["name"])
		
		print("加载的模型列表: ", available_models)
		
		# 如果没有当前模型，选择第一个
		if current_model.is_empty() and available_models.size() > 0:
			current_model = available_models[0]
			print("设置默认模型: ", current_model)
		
		# 发出信号通知模型已加载
		models_loaded.emit(available_models)
		print("模型列表已发送")
	else:
		var error_msg = "无法解析模型列表: " + JSON.stringify(data)
		error_occurred.emit(error_msg)
		print(error_msg)
 
# 处理生成响应
func _handle_generate_response(data):
	print("处理生成响应")
 
	if data and data.has("response"):
		var full_response = data["response"]
		print("原始AI响应: ", full_response)
		
		# 提取<think>标签之后的内容
		var cleaned_response = extract_response_content(full_response)
		response_received.emit(cleaned_response)
		print("清理后响应: ", cleaned_response)
		
		# 缓存响应
		if !current_cache_key.is_empty():
			response_cache[current_cache_key] = cleaned_response
			current_cache_key = ""
	else:
		var error_msg = "无法解析API响应: " + JSON.stringify(data)
		error_occurred.emit(error_msg)
		print(error_msg)
 
# 提取<think>标签之后的内容
func extract_response_content(full_response: String) -> String:
	# 查找<think>标签的位置
	var think_start = full_response.find("<think>")
	var think_end = full_response.find("</think>")
 
	# 如果找到两个标签
	if think_start != -1 && think_end != -1:
		# 获取</think>之后的内容
		return full_response.substr(think_end + 8).strip_edges()
 
	# 如果只找到结束标签
	if think_end != -1:
		return full_response.substr(think_end + 8).strip_edges()
 
	# 如果只找到开始标签
	if think_start != -1:
		return full_response.substr(think_start + 7).strip_edges()
 
	# 没有标签，返回完整响应
	return full_response.strip_edges()
 
# 获取当前模型
func get_current_model() -> String:
	return current_model
 
# 设置当前模型
func set_current_model(model: String):
	if model in available_models:
		current_model = model
		print("模型已设置为: ", model)
	else:
		var error_msg = "尝试设置无效模型: " + model
		push_error(error_msg)
		print(error_msg)
 
# 获取可用模型列表
func get_available_models() -> Array:
	return available_models
 
# 手动测试模型列表请求
func test_models_request():
	print("手动测试模型列表请求...")
	_enqueue_request({"type": "models"})
