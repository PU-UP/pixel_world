extends Node
class_name LlmClient
##
## MiniMax OpenAI 兼容 API 客户端 — 异步队列 + 并发池 + 重试
##

signal completed(request_id: int, body: Dictionary, meta: Dictionary)
signal failed(request_id: int, error: String, meta: Dictionary)

const DecisionPrompt = preload("res://scripts/llm/prompts/decision.gd")

var _queue: Array = []
var _http_pool: Array = []
var _http_item: Dictionary = {}  # HTTPRequest -> queue item
var _retry_max: int = 2
var _timeout_s: float = 20.0
var _max_concurrent: int = 4
var _next_id: int = 1
var _obs_logger = null


func set_logger(logger) -> void:
	_obs_logger = logger


func _ready() -> void:
	_reload_config()


func _reload_config() -> void:
	_retry_max = int(Config.llm.get("retry", 2))
	_timeout_s = float(Config.llm.get("timeout_s", 20.0))
	_max_concurrent = max(1, Config.llm_concurrency())
	_ensure_http_pool(_max_concurrent)


func is_configured() -> bool:
	return not Config.llm_api_key().is_empty()


func inflight_count() -> int:
	return _http_item.size()


func queue_length() -> int:
	return _queue.size()


func cancel_pending() -> void:
	_queue.clear()


func request_decision(messages: Array, meta: Dictionary = {}, tools: Array = []) -> int:
	meta["request_type"] = "decision"
	if tools.size() > 0:
		meta["tools"] = tools
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
		"tools": meta.get("tools", []),
	})
	_pump_queue()
	return id


func _ensure_http_pool(count: int) -> void:
	while _http_pool.size() < count:
		var http := HTTPRequest.new()
		add_child(http)
		http.request_completed.connect(_on_request_completed.bind(http))
		_http_pool.append(http)


func _pump_queue() -> void:
	if _queue.is_empty():
		return
	for http in _http_pool:
		if _http_item.has(http):
			continue
		if _queue.is_empty():
			break
		_send(http, _queue.pop_front())


func _send(http: HTTPRequest, item: Dictionary) -> void:
	if not is_configured():
		_log_llm(item.get("meta", {}), {}, false, "LLM API key not configured")
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
		var tools: Array = item.get("tools", [])
		if tools.is_empty():
			tools = DecisionPrompt.tool_definitions()
		body["tools"] = tools
		body["tool_choice"] = "required"
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])
	http.timeout = _timeout_s
	_http_item[http] = item
	var err := http.request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		_http_item.erase(http)
		_log_llm(item.get("meta", {}), {}, false, "HTTPRequest.request failed: %s" % err)
		failed.emit(int(item["id"]), "HTTPRequest.request failed: %s" % err, item.get("meta", {}))
		_pump_queue()


func _on_request_completed(
	result: int,
	response_code: int,
	_headers: PackedStringArray,
	body: PackedByteArray,
	http: HTTPRequest,
) -> void:
	var item: Dictionary = _http_item.get(http, {})
	_http_item.erase(http)
	var req_id := int(item.get("id", -1))

	var body_text := body.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(body_text)
	var body_dict: Dictionary = parsed if typeof(parsed) == TYPE_DICTIONARY else {}

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		var err_msg := "HTTP %d result=%d body=%s" % [response_code, result, body_text.substr(0, 200)]
		var is_rate_limit := response_code == 429 or body_text.find("rate_limit") >= 0
		if int(item.get("attempt", 0)) < _retry_max:
			item["attempt"] = int(item["attempt"]) + 1
			if is_rate_limit:
				_queue.push_back(item)
			else:
				_queue.push_front(item)
		else:
			_log_llm(item.get("meta", {}), body_dict, false, err_msg)
			failed.emit(req_id, err_msg, item.get("meta", {}))
		_pump_queue()
		return

	_log_llm(item.get("meta", {}), body_dict, true, "")
	completed.emit(req_id, body_dict, item.get("meta", {}))
	_pump_queue()


func _log_llm(meta: Dictionary, body: Dictionary, ok: bool, error: String) -> void:
	if _obs_logger == null:
		return
	_obs_logger.log_llm_response(meta, body, ok, error)
