extends Node
## Server autoload. Keep it clean and minimal.
## Should only care about connection and authentication stuff.

const GatewayConnector = preload("res://source/game_server/gateway_connector.gd")

# Default port
var port: int = 8087
var game_server: WebSocketMultiplayerPeer

var gateway: GatewayConnector
# {token: {"username": "salade", "class": "knight"}}
var token_list: Dictionary

var player_list: Dictionary

## For autocomplention
@onready var scene_multiplayer := multiplayer as SceneMultiplayer


func _ready() -> void:
	add_gateway_connector.call_deferred()
	var parsed_arguments := CmdlineUtils.get_parsed_args()
	print("Game Server parsed arguments = ", parsed_arguments)
	if parsed_arguments.has("port"):
		port = parsed_arguments[port]


func start_server() -> void:
	print("Starting server.")
	game_server = WebSocketMultiplayerPeer.new()
	
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	
	scene_multiplayer.peer_authenticating.connect(_on_peer_authenticating)
	scene_multiplayer.peer_authentication_failed.connect(_on_peer_authentication_failed)
	scene_multiplayer.set_auth_callback(_authentication_callback)
	
	var server_certificate = load("res://source/common/server_certificate.crt")
	var server_key = load("res://source/game_server/server_key.key")
	if server_certificate == null or server_key == null:
		print("Failed to load certificate or key.")
		return
	
	var error := game_server.create_server(port, "*", TLSOptions.server(server_key, server_certificate))
	if error:
		print(error_string(error))
		return
	multiplayer.set_multiplayer_peer(game_server)
	gateway.connect_to_gateway()


func _on_peer_connected(peer_id: int) -> void:
	print("Peer: %d is connected." % peer_id)


func _on_peer_disconnected(peer_id: int) -> void:
	print("Peer: %d is disconnected." % peer_id)
	player_list.erase(peer_id)


func _on_peer_authenticating(peer_id: int) -> void:
	print("Peer: %d is trying to authenticate." % peer_id)
	scene_multiplayer.send_auth(peer_id, "data_from_server".to_ascii_buffer())


func _on_peer_authentication_failed(peer_id: int) -> void:
	print("Peer: %d failed to authenticate." % peer_id)


# Quick and dirty, needs rework.
func _authentication_callback(peer_id: int, data: PackedByteArray) -> void:
	#var dict := bytes_to_var(data) as Dictionary
	var token := bytes_to_var(data) as String
	print("Peer: %d is trying to connect with data: \"%s\"." % [peer_id, token])
	if is_valid_authentication_token(token):
		scene_multiplayer.complete_auth(peer_id)
		#player_list[peer_id] = dict
		player_list[peer_id] = token_list[token]
		token_list.erase(token)
	else:
		game_server.disconnect_peer(peer_id)


func is_valid_authentication_token(token: String) -> bool:
	if token_list.has(token):
		return true
	return false


func add_gateway_connector() -> void:
	gateway = GatewayConnector.new()
	gateway.name = "GatewayBridge"
	gateway.token_received.connect(
		func(token: String, player_data: Dictionary):
			token_list[token] = player_data
	)
	add_sibling(gateway)
