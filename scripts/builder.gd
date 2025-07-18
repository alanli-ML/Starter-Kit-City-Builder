extends Node3D

@export var structures: Array[Structure] = []

var map:DataMap

var index:int = 0 # Index of structure being built

@export var selector:Node3D # The 'cursor'
@export var selector_container:Node3D # Node that holds a preview of the structure
@export var view_camera:Camera3D # Used for raycasting mouse
@export var gridmap:GridMap
@export var cash_display:Label
@export var structure_list_container:VBoxContainer # Container for structure selection buttons
@export var structure_panel:Panel # The structure selection panel
@export var notification_label:Label # Notification display label

var plane:Plane # Used for raycasting mouse

func _ready():
	
	map = DataMap.new()
	plane = Plane(Vector3.UP, Vector3.ZERO)
	
	# Create new MeshLibrary dynamically, can also be done in the editor
	# See: https://docs.godotengine.org/en/stable/tutorials/3d/using_gridmaps.html
	
	var mesh_library = MeshLibrary.new()
	
	for structure in structures:
		
		var id = mesh_library.get_last_unused_item_id()
		
		mesh_library.create_item(id)
		mesh_library.set_item_mesh(id, get_mesh(structure.model))
		mesh_library.set_item_mesh_transform(id, Transform3D())
		
	gridmap.mesh_library = mesh_library
	
	populate_structure_list()
	update_structure()
	update_cash()

func _process(delta):
	
	# Controls
	
	action_rotate() # Rotates selection 90 degrees
	action_structure_toggle() # Toggles between structures
	
	action_save() # Saving
	action_load() # Loading
	action_load_sample() # Load sample map
	
	# Map position based on mouse
	
	var world_position = plane.intersects_ray(
		view_camera.project_ray_origin(get_viewport().get_mouse_position()),
		view_camera.project_ray_normal(get_viewport().get_mouse_position()))

	var gridmap_position = Vector3(round(world_position.x), 0, round(world_position.z))
	selector.position = lerp(selector.position, gridmap_position, delta * 40)
	
	action_build(gridmap_position)
	action_demolish(gridmap_position)

# Retrieve the mesh from a PackedScene, used for dynamically creating a MeshLibrary

func get_mesh(packed_scene):
	var scene_state:SceneState = packed_scene.get_state()
	for i in range(scene_state.get_node_count()):
		if(scene_state.get_node_type(i) == "MeshInstance3D"):
			for j in scene_state.get_node_property_count(i):
				var prop_name = scene_state.get_node_property_name(i, j)
				if prop_name == "mesh":
					var prop_value = scene_state.get_node_property_value(i, j)
					
					return prop_value.duplicate()

# Build (place) a structure

func action_build(gridmap_position):
	if Input.is_action_just_pressed("build") and not is_mouse_over_ui():
		
		var previous_tile = gridmap.get_cell_item(gridmap_position)
		gridmap.set_cell_item(gridmap_position, index, gridmap.get_orthogonal_index_from_basis(selector.basis))
		
		if previous_tile != index:
			map.cash -= structures[index].price
			update_cash()

# Check if mouse is over UI elements
func is_mouse_over_ui() -> bool:
	if not structure_panel:
		return false
	
	var mouse_pos = get_viewport().get_mouse_position()
	var panel_rect = structure_panel.get_global_rect()
	return panel_rect.has_point(mouse_pos)

func action_load_sample():
	if Input.is_action_just_pressed("load_sample"):
		print("Loading sample map...")
		
		gridmap.clear()
		
		var loaded_map = ResourceLoader.load("res://sample map/map.res")
		if not loaded_map:
			print("Sample map not found!")
			map = DataMap.new()
			show_notification("Sample Map Not Found!")
		else:
			print("Sample map loaded successfully!")
			map = loaded_map
			show_notification("Sample Map Loaded Successfully!")
		
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()

# Demolish (remove) a structure

func action_demolish(gridmap_position):
	if Input.is_action_just_pressed("demolish") and not is_mouse_over_ui():
		gridmap.set_cell_item(gridmap_position, -1)

# Rotates the 'cursor' 90 degrees

func action_rotate():
	if Input.is_action_just_pressed("rotate"):
		selector.rotate_y(deg_to_rad(90))

# Toggle between structures to build

func action_structure_toggle():
	if Input.is_action_just_pressed("structure_next"):
		index = wrap(index + 1, 0, structures.size())
	
	if Input.is_action_just_pressed("structure_previous"):
		index = wrap(index - 1, 0, structures.size())

	update_structure()
	update_structure_list_selection()

# Update the structure visual in the 'cursor'

func update_structure():
	# Clear previous structure preview in selector
	for n in selector_container.get_children():
		selector_container.remove_child(n)
		
	# Create new structure preview in selector
	var _model = structures[index].model.instantiate()
	selector_container.add_child(_model)
	_model.position.y += 0.25
	
	# Update UI selection
	update_structure_list_selection()
	
func update_cash():
	cash_display.text = "$" + str(map.cash)

# Show notification message with auto-hide timer
func show_notification(message: String, duration: float = 3.0):
	if notification_label:
		notification_label.text = message
		notification_label.visible = true
		
		# Create a timer to hide the notification
		var timer = Timer.new()
		add_child(timer)
		timer.wait_time = duration
		timer.one_shot = true
		timer.timeout.connect(_hide_notification.bind(timer))
		timer.start()

# Hide notification and cleanup timer
func _hide_notification(timer: Timer):
	if notification_label:
		notification_label.visible = false
	timer.queue_free()

# Populate the structure selection list UI
func populate_structure_list():
	if not structure_list_container:
		return
		
	# Clear existing buttons
	for child in structure_list_container.get_children():
		child.queue_free()
	
	# Create previews asynchronously
	_create_structure_items()

# Create structure items with async preview generation
func _create_structure_items():
	for i in range(structures.size()):
		var structure = structures[i]
		
		# Create container for each structure item
		var item_container = HBoxContainer.new()
		item_container.custom_minimum_size.y = 80
		
		# Create placeholder for preview initially
		var preview_rect = TextureRect.new()
		preview_rect.custom_minimum_size = Vector2(70, 70)
		preview_rect.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		preview_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		# Create button for selection
		var button = Button.new()
		button.custom_minimum_size.y = 70
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		# Extract structure name from model path
		var model_path = structure.model.resource_path
		var structure_name = model_path.get_file().get_basename().replace("-", " ").capitalize()
		
		button.text = structure_name + "\n$" + str(structure.price)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		
		# Connect button to selection function
		button.pressed.connect(_on_structure_selected.bind(i))
		
		# Add preview and button to container
		item_container.add_child(preview_rect)
		item_container.add_child(button)
		
		structure_list_container.add_child(item_container)
		
		# Generate preview texture asynchronously
		_generate_preview_async(preview_rect, structure)

# Generate preview texture asynchronously
func _generate_preview_async(preview_rect: TextureRect, structure: Structure):
	var preview_texture = await create_structure_preview(structure)
	if is_instance_valid(preview_rect):
		preview_rect.texture = preview_texture

# Create a 3D preview texture for a structure
func create_structure_preview(structure: Structure) -> ImageTexture:
	print("Generating preview for: ", structure.model.resource_path)
	
	# Create a SubViewport for rendering
	var viewport = SubViewport.new()
	viewport.size = Vector2i(128, 128)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	
	# Add viewport to scene first
	get_tree().root.call_deferred("add_child", viewport)
	
	# Wait for viewport to be added
	await get_tree().process_frame
	
	# Create a 3D scene for the preview
	var scene_3d = Node3D.new()
	viewport.add_child(scene_3d)
	
	# Add the structure model
	var model_instance = structure.model.instantiate()
	scene_3d.add_child(model_instance)
	
	# Get the model's AABB to position camera properly
	var aabb = get_model_aabb(model_instance)
	var center = aabb.get_center()
	var size = aabb.size.length()
	
	# Position camera to frame the model nicely based on its size
	var camera_distance = max(size * 1.5, 2.0)
	var camera = Camera3D.new()
	camera.position = Vector3(camera_distance * 0.7, camera_distance * 0.7, camera_distance * 0.7)
	camera.fov = 45
	scene_3d.add_child(camera)
	
	# Look at the center of the model
	camera.look_at_from_position(camera.position, center, Vector3.UP)
	
	# Add lighting
	var light = DirectionalLight3D.new()
	light.position = Vector3(camera_distance, camera_distance, camera_distance)
	light.light_energy = 1.5
	scene_3d.add_child(light)
	
	# Look at the model center
	light.look_at_from_position(light.position, center, Vector3.UP)
	
	# Add ambient light
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.15, 0.15, 0.2, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.ambient_light_energy = 0.4
	camera.environment = env
	
	# Force multiple render frames to ensure everything is loaded
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	
	# Get the texture
	var texture = viewport.get_texture()
	var image = texture.get_image()
	
	# Clean up
	viewport.queue_free()
	
	# Create ImageTexture from the captured image
	var image_texture = ImageTexture.new()
	image_texture.set_image(image)
	
	print("Preview generated for: ", structure.model.resource_path)
	return image_texture

# Get the AABB of a model instance (recursive for complex models)
func get_model_aabb(node: Node3D) -> AABB:
	var aabb = AABB()
	var first = true
	
	if node is MeshInstance3D:
		var mesh_instance = node as MeshInstance3D
		if mesh_instance.mesh:
			var mesh_aabb = mesh_instance.mesh.get_aabb()
			mesh_aabb = mesh_instance.transform * mesh_aabb
			aabb = mesh_aabb
			first = false
	
	for child in node.get_children():
		if child is Node3D:
			var child_aabb = get_model_aabb(child)
			if not child_aabb.has_area():
				continue
			child_aabb = node.transform * child_aabb
			if first:
				aabb = child_aabb
				first = false
			else:
				aabb = aabb.merge(child_aabb)
	
	# Default fallback if no mesh found
	if first:
		aabb = AABB(Vector3(-0.5, -0.5, -0.5), Vector3(1, 1, 1))
	
	return aabb

# Handle structure selection from UI
func _on_structure_selected(structure_index: int):
	index = structure_index
	update_structure()
	update_structure_list_selection()

# Update visual selection in structure list
func update_structure_list_selection():
	if not structure_list_container:
		return
		
	for i in range(structure_list_container.get_child_count()):
		var item_container = structure_list_container.get_child(i) as HBoxContainer
		if item_container:
			if i == index:
				item_container.modulate = Color.YELLOW
			else:
				item_container.modulate = Color.WHITE

# Saving/load

func action_save():
	if Input.is_action_just_pressed("save"):
		print("Saving map...")
		
		map.structures.clear()
		for cell in gridmap.get_used_cells():
			
			var data_structure:DataStructure = DataStructure.new()
			
			data_structure.position = Vector2i(cell.x, cell.z)
			data_structure.orientation = gridmap.get_cell_item_orientation(cell)
			data_structure.structure = gridmap.get_cell_item(cell)
			
			map.structures.append(data_structure)
			
		var result = ResourceSaver.save(map, "user://map.res")
		if result == OK:
			show_notification("Map Saved Successfully!")
		else:
			show_notification("Failed to Save Map!")
	
func action_load():
	if Input.is_action_just_pressed("load"):
		print("Loading map...")
		
		gridmap.clear()
		
		# Try to load user map first, then fall back to sample map
		var loaded_map = ResourceLoader.load("user://map.res")
		var map_source = ""
		
		if loaded_map:
			map = loaded_map
			map_source = "User Map"
		else:
			loaded_map = ResourceLoader.load("res://sample map/map.res")
			if loaded_map:
				map = loaded_map
				map_source = "Sample Map"
			else:
				map = DataMap.new()
				map_source = "New Map"
		
		for cell in map.structures:
			gridmap.set_cell_item(Vector3i(cell.position.x, 0, cell.position.y), cell.structure, cell.orientation)
			
		update_cash()
		show_notification(map_source + " Loaded Successfully!")
