extends Node
class_name LlmClient
##
## MiniMax OpenAI 兼容 API 客户端 — 异步队列 + 重试
##

signal completed(request_id: int, body: Dictionary, meta: Dictionary)
signal failed(request_id: int, error: String, meta: Dictionary)

const DecisionPrompt = preload("res://scripts/llm/prompts/decision.gd")

var _http: HTTPRequest
var _queue: Array = []
var _current: Dictionary = {}
var _busy: bool = false
var _retry_max: int = 2
var _timeout_s: float = 20.0
var _next_id: int = 1


func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)
	_reload_config()


func _reload_config() -> void:
	_retry_max = int(Config.llm.get("retry", 2))
	_timeout_s = float(Config.llm.get("timeout_s", 20.0))
	_http.timeout = _timeout_s


func is_configured() -> bool:
	return not Config.llm_api_key().is_empty()


func request_decision(messages: Array, meta: Dictionary = {}) -> int:
	meta["request_type"] = "decision"
	return _enqueue(messages, meta, true)


func request_chat(messages: Array, meta: Dictionary = {}) -> int:
	if not meta.has("request_type"):
		meta["request_type"] = "chat"
	return _enqueue(messages, meta, false)


func _enqueue(messages: Array, meta: Dictionary, use_tools: bool) -> int:
	var id := _next_id
	_next_id += 1
	_queue.append({
		"id": id,
		"messages": messages,
		"meta": meta,
		"attempt": 0,
		"use_tools": use_tools,
	})
	_pump_queue()
	return id


func _pump_queue() -> void:
	if _busy or _queue.is_empty():
		return
	var item: Dictionary = _queue.pop_front()
	_send(item)


func _send(item: Dictionary) -> void:
	if not is_configured():
		failed.emit(int(item["id"]), "LLM API key not configured (set MINIMAX_API_KEY in .env)", item.get("meta", {}))
		_pump_queue()
		return
	var api_key := Config.llm_api_key()
	var base_url := str(Config.llm.get("base_url", "https://api.minimaxi.com/v1")).trim_suffix("/")
	var url := "%s/chat/completions" % base_url
	var body := {
		"model": str(Config.llm.get("model", "MiniMax-M3")),
		"messages": item["messages"],
		"temperature": float(Config.llm.get("temperature", 0.7)),
		"max_completion_tokens": int(Config.llm.get("max_tokens", 400)),
		"thinking": {"type": "disabled"},
	}
	if bool(item.get("use_tools", false)):
		body["tools"] = DecisionPrompt.tool_definitions()
		body["tool_choice"] = "required"
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	_busy = true
	_current = item
	var err := _http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_busy = false
		_current = {}
		failed.emit(int(item["id"]), "HTTPRequest.request failed: %s" % err, item.get("meta", {}))
		_pump_queue()


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var item: Dictionary = _current
	var req_id := int(item.get("id", -1))
	_busy = false
	_current = {}

	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	var body_dict: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var err_msg := "HTTP %d result=%d body=%s" % [response_code, result, body_text.substr(0, 200)]
		if int(item.get("attempt", 0)) < _retry_max:
			item["attempt"] = int(item["attempt"]) + 1
			_queue.push_front(item)
		else:
			failed.emit(req_id, err_msg, item.get("meta", {}))
		_pump_queue()
		return

	completed.emit(req_id, body_dict, item.get("meta", {}))
	_pump_queue()
