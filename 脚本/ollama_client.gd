extends Node

const API_URL = "http://localhost:11434/api/generate"
var http_request = HTTPRequest.new()
signal response_received(message: String)
signal error_occurred(message: String)

func _ready():
	add_child(http_request)
	http_request.request_completed.connect(_on_response_received)

func send_prompt(prompt: String, model: String = "deepseek-r1:7b-qwen-distill-q4_K_M"):
	var headers = ["Content-Type: application/json"]
	var body = JSON.stringify({
		"model": model,
		"prompt": prompt,
		"stream": false  # 非流式响应
	})
	http_request.request(API_URL, headers, HTTPClient.METHOD_POST, body)

func _on_response_received(result, response_code, headers, body):
	if response_code == 200:
		var json = JSON.parse_string(body.get_string_from_utf8())
		if json.has("response"):
			var full_response = json["response"]
			# 提取<think>标签之后的内容
			var cleaned_response = extract_response_content(full_response)
			response_received.emit(cleaned_response)
	else:
		error_occurred.emit("API错误: " + str(response_code))

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
