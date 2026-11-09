-- data/lab_classes.lua: the call classes of spec M1a section 3.4 (A1.10; D17, D30) and of the player beta's
-- dismemberment (docs/research/beta-dismemberment-plan.md BD0, the block at the end). Pure data: no require.
-- Key: a section 3.4 or a BD0 sentinel name, each one a META.lab_risky name. Value: the data/hooks.lua calls ids
-- (each a '/Script/<class>:<function>' UFunction path) the code under that name calls, in no particular order:
-- * D17: LAB.sig(name) (A1.2) runs ue.sig_ok on each id's path against data/sigs.lua at the class's first use in a
--   session; an empty list (reflection, property writes, loader globals such as LoadAsset and UnregisterHook) passes
--   trivially.
-- * D30: a route is ready when every class on it has its ids present (not in env calls_missing), its sig check ok and
--   its ladder proof, so a name missing elsewhere blocks only the classes that list it.
-- What a class lists: the calls of its section 3.4 row, what its ladder step (section 3.5) or frame (section 3.8) runs
-- under that name (a step that shows, hides, attaches or reads back lists those calls too), and the calls the bridge
-- helper it uses makes on the way: ue.add_component -> AddComponentByClass and SetCullDistance (never_cull; Box and
-- Sphere skip it), with no_collision SetCollisionEnabled (review A5.1 F3, F9) and, with trace_neutral, the collision
-- setters; ue.destroy -> GetOwner and K2_DestroyComponent;
-- ue.set_hidden -> SetHiddenInGame; ue.hold -> a hidden keeper or holder component with SetMaterial, or
-- SetCollisionEnabled and SetStaticMesh (ue.destroy when that fails); ue.hide_bone_all, ue.unhide_bone_all and the
-- read-back's walk over every leader with the bone (ue.leaders_with_bone) -> K2_GetComponentsByClass and GetBoneIndex;
-- ue.cap_parent -> GetBoneIndex (the leader walk when its target lacks the bone), K2_AttachToComponent and
-- K2_SetRelativeLocationAndRotation; ue.components -> K2_GetComponentsByClass; ue.listed (a component destroy read back
-- through its owner's list) -> K2_GetComponentsByClass; ue_lab's bone_parent -> GetParentBone.
-- The route names (lab.cut.*) list every call of their frame, failure paths included. tests/test_lab_data.lua pins
-- the keys (pairs) to section 3.4, every id to data/hooks.lua calls, and the helper calls above to the source of
-- adapter/ue.lua and adapter/ue_lab.lua.
-- The beta (BD0): the stage, head and limb rows also list what the beta route calls under them (the subtree scan's
-- GetSocketBoneName and attach reads, the Cap roll's GetActorForwardVector, the hidden extras' world transforms, the
-- textured Cap MID, the scan hits tagged on a limb); the BD0 names (the block at the end, behind __index) list what
-- lab_look, lab_cap's test section, lab_census, lab_fade and lab_gib call under them. A group that needs another id
-- asks for a BD0 follow-up.
local GET_OWNER, DESTROY_COMP = 'actor_comp_get_owner', 'actor_comp_k2_destroy_component'
-- ue.leaders_with_bone: every skinned component of the actor, then GetBoneIndex on each
local LEADERS = { 'actor_k2_get_components_by_class', 'skinned_get_bone_index' }
local ADD, NO_CULL, HIDDEN = 'actor_add_component_by_class', 'prim_set_cull_distance', 'scene_set_hidden_in_game'
local ATTACH, REL = 'scene_k2_attach_to_component', 'scene_k2_set_relative_location_and_rotation'
local SECTION, SECTIONS = 'procmesh_create_mesh_section_linear_color', 'procmesh_get_num_sections'
-- ue_lab.mid: the component's CreateDynamicMaterialInstance, else GetNumMaterials, GetMaterial, the library's
-- CreateDynamicMaterialInstance and SetMaterial (TC-LAB-02 run 1: P5 no_mid)
local MID = { 'prim_create_dynamic_material_instance', 'prim_get_num_materials', 'prim_get_material',
    'kmat_create_dynamic_material_instance', 'prim_set_material' }
local MID_COLOR = 'mid_set_vector_parameter_value'
local BEGIN, FINISH = 'statics_begin_deferred_actor_spawn_from_class', 'statics_finish_spawning_actor'
local ACTOR_HIDDEN, DESTROY_ACTOR = 'actor_set_actor_hidden_in_game', 'actor_k2_destroy_actor'
local HIDE, UNHIDE, IS_HIDDEN = 'skinned_hide_bone_by_name', 'skinned_un_hide_bone_by_name', 'skinned_is_bone_hidden_by_name'
local CVAR = 'ksl_get_console_variable_int_value'
-- the Piece's poseable (piece.mesh), pose (piece.pose), isolation (piece.isolate) and physics (piece.phys)
local P_ASSET, P_MATS, P_GET_MAT, P_SET_MAT = 'skinned_set_skinned_asset_and_update', 'prim_get_num_materials',
    'prim_get_material', 'prim_set_material'
local P_WORLD, P_COPY, P_GET = 'scene_k2_set_world_transform', 'poseable_copy_pose_from_skeletal_component',
    'poseable_get_bone_transform_by_name'
local P_SCALE, P_XFORM, P_ROOT = 'poseable_set_bone_scale_by_name', 'poseable_set_bone_transform_by_name',
    'skinned_get_bone_name'
local PHYS = { 'prim_set_collision_enabled', 'prim_set_collision_object_type', 'prim_set_collision_response_to_all_channels',
    'prim_set_collision_response_to_channel', 'scene_set_mobility', 'prim_set_mass_override_in_kg', 'prim_set_use_ccd',
    'prim_set_simulate_physics', 'prim_add_impulse' }
-- the beta (BD0): the subtree scan (the socket's bone, the attach parent and socket), the roll, a world transform, the
-- textured Cap MID, the material reads of the cap look probe, the static mesh reads
local SCAN = { 'skinned_get_socket_bone_name', 'scene_get_attach_parent', 'scene_get_attach_socket_name' }
local FORWARD, TO_WORLD, MID_TEX = 'actor_get_actor_forward_vector', 'scene_k2_get_component_to_world',
    'mid_set_texture_parameter_value'
local MIC_GET = { 'mic_k2_get_texture_parameter_value', 'mic_k2_get_scalar_parameter_value',
    'mic_k2_get_vector_parameter_value' }
local MID_GET = { 'mid_k2_get_texture_parameter_value', 'mid_k2_get_scalar_parameter_value',
    'mid_k2_get_vector_parameter_value' }
local SM_READ = { 'static_mesh_get_material', 'static_mesh_get_material_index', 'static_mesh_get_num_sections',
    'static_mesh_get_bounds' }
-- -> one list of the given ids and lists, in order, each id once
local function join(...)
    local out, seen = {}, {}
    for _, v in ipairs({ ... }) do
        for _, id in ipairs(type(v) == 'table' and v or { v }) do
            if not seen[id] then seen[id], out[#out + 1] = true, id end
        end
    end
    return out
end

local C = {}
-- the L0i group and the bone resolver (P1; also every new mesh asset at a stage), time (P1b), reflection, the keep
-- levers (property writes with read-back, P2), the mob group read
C['lab.inherit.hide'] = { HIDE, IS_HIDDEN, GET_OWNER, 'actor_comp_component_has_tag', UNHIDE, 'skinned_get_parent_bone',
    'scene_get_socket_transform', 'skinned_get_bone_index' }
C['probe.static.GetTimeSeconds'] = { 'statics_get_time_seconds' }
C['probe.meta'] = {}
C['keep.write'] = {}
C['lab.inherit.group'] = { 'mob_group_has_alive_members' }
-- Caps: ladder P3-P9b
C['cap.pmc'] = { ADD, NO_CULL, HIDDEN }                                      -- added hidden
C['lab.tarray.probe'] = { SECTION, SECTIONS }
C['cap.mid'] = join(MID, MID_COLOR)
C['cap.parent'] = join(ATTACH, REL, LEADERS)                                -- ue.cap_parent
C['cap.mesh'] = { SECTION, SECTIONS, HIDDEN }                                -- shown 5 s
C['cap.meat'] = join(ADD, 'prim_set_collision_enabled', NO_CULL, 'static_mesh_comp_set_static_mesh', MID, MID_COLOR,
    ATTACH, REL, LEADERS, HIDDEN)                                            -- collision off from the add (A5.1 F3)
C['cap.destroy'] = { GET_OWNER, DESTROY_COMP, 'actor_k2_get_components_by_class' }   -- ue.listed reads it back
C['cap.keep'] = { ADD, NO_CULL, HIDDEN, P_SET_MAT, 'prim_set_collision_enabled', 'static_mesh_comp_set_static_mesh',
    GET_OWNER, DESTROY_COMP }
-- Pieces: ladder P10-P16 (the box carrier skips SetCullDistance)
C['hide.optim'] = { 'opt_proxy_disable_all_optimizations', 'opt_proxy_enable_optimizations' }
C['piece.spawn'] = { BEGIN, FINISH, ADD, 'prim_set_collision_enabled', 'box_set_box_extent', ACTOR_HIDDEN }  -- A5.1 F9
C['piece.mesh'] = { ADD, NO_CULL, P_ASSET, P_MATS, P_GET_MAT, P_SET_MAT }
C['piece.pose'] = { P_WORLD, P_COPY, P_GET, 'scene_k2_get_component_to_world', 'scene_get_socket_transform',
    'skinned_get_bone_index' }                                                -- the pose proof reads (M1a 4.2 item 2)
C['piece.isolate'] = { P_SCALE, P_XFORM, P_GET, P_ROOT, 'scene_get_socket_transform', 'skinned_get_bone_index' }
-- (P_ROOT: the root bone name when iso is nil; the socket and index reads: the stump and cut poses from the leader, and
-- P14's pose re-read)
C['piece.phys'] = join(PHYS, ACTOR_HIDDEN)                                   -- shown, then simulated
C['piece.destroy'] = { DESTROY_ACTOR }
-- the head components (P17, P18: the tags go through the ComponentTags TArray userdata, no UFunction)
C['hide.comp'] = { HIDDEN }
C['hide.tag'] = { 'actor_comp_component_has_tag' }
-- the commit (section 3.8): the bone hide, the hidden build, the head, limb and GCAP-a frames, the read-back
C['hide.bone'] = join(HIDE, LEADERS)                                         -- ue.hide_bone_all
-- (the stage's lab_piece build walks the cut subtree through GetParentBone once per mesh asset, and lab_cap's
-- Piece-end seat walks it when the cut has no chain)
-- (the beta, BD0: the scan, the roll, the extras' world transforms and the textured Cap MID run in the stage too)
C['lab.cut.stage'] = join(ADD, 'prim_set_collision_enabled', NO_CULL, HIDDEN, SECTION, SECTIONS, MID, MID_COLOR,
    'static_mesh_comp_set_static_mesh',
    ATTACH, REL, 'skinned_get_bone_index', 'scene_get_socket_transform', BEGIN, FINISH, 'box_set_box_extent',
    ACTOR_HIDDEN, P_ASSET, P_MATS, P_GET_MAT, P_SET_MAT, GET_OWNER, DESTROY_COMP, DESTROY_ACTOR, LEADERS,
    'skinned_get_parent_bone', SCAN, FORWARD, TO_WORLD, MID_TEX)
-- (isolate reads the stump and cut poses from the leader; the beta, BD0: the hidden extras' world transforms read at
-- the commit for lab_gib, and a limb tags its scan hits)
C['lab.cut.head'] = join('opt_proxy_disable_all_optimizations', P_COPY, P_GET, P_ROOT, P_SCALE, P_XFORM, P_WORLD, HIDE,
    HIDDEN, 'actor_comp_component_has_tag', ACTOR_HIDDEN, PHYS, UNHIDE, GET_OWNER, DESTROY_COMP, DESTROY_ACTOR, LEADERS,
    'scene_get_socket_transform', 'skinned_get_bone_index', TO_WORLD)
C['lab.cut.limb'] = join('opt_proxy_disable_all_optimizations', P_COPY, P_GET, P_ROOT, P_SCALE, P_XFORM, P_WORLD, HIDE,
    HIDDEN, ACTOR_HIDDEN, PHYS, UNHIDE, GET_OWNER, DESTROY_COMP, DESTROY_ACTOR, LEADERS,
    'scene_get_socket_transform', 'skinned_get_bone_index', 'actor_comp_component_has_tag', TO_WORLD)
C['lab.cut.gcap'] = join(HIDE, IS_HIDDEN, BEGIN, FINISH, ADD, 'prim_set_collision_enabled', NO_CULL,
    'box_set_box_extent', P_ASSET, P_MATS, P_GET_MAT,
    P_SET_MAT, P_WORLD, P_COPY, P_SCALE, ACTOR_HIDDEN, UNHIDE, DESTROY_ACTOR, LEADERS)
C['lab.read.bonehidden'] = join(IS_HIDDEN, LEADERS)                          -- every leader with the cut bone (A3.8)
-- the spawn press (D12): the class load is a loader lookup (find, else LoadAsset)
C['lab.spawn.load'] = {}
C['lab.spawn.summon'] = { 'cheat_summon' }
C['lab.spawn.deferred'] = { BEGIN, FINISH, DESTROY_ACTOR }       -- an unfinished actor destroyed (A5.1 F6)
C['lab.spawn.respawn'] = { 'npc_spawner_respawn', 'ai_spawner_iface_respawn' }
C['lab.spawn.move'] = { 'actor_k2_teleport_to', 'controller_get_control_rotation' }  -- the placement yaw
C['lab.spawn.ai'] = { 'pawn_spawn_default_controller' }
-- the pawn class held for the session (M1a 4.2 item 4): a ChildActorComponent on the lab pawn (ue.hold kind 'class'),
-- destroyed through its owner on a failed read-back
C['lab.spawn.hold'] = { ADD, GET_OWNER, DESTROY_COMP }
-- S-SKIN (D16): the holder, the copy, the bone list, one chunk of reads
C['lab.skin.holder'] = { ADD, NO_CULL, HIDDEN, 'base_dyn_mesh_comp_get_dynamic_mesh',
    'actor_k2_get_components_by_class' }                                      -- the meshhead looked up by name
C['lab.skin.copy'] = { 'gs_static_mesh_copy_mesh_from_skeletal_mesh', 'gs_bone_weight_mesh_has_bone_weights',
    'gs_query_get_vertex_count' }
C['lab.skin.bones'] = { 'gs_bone_weight_get_all_bones_info' }
C['lab.skin.read'] = { 'gs_query_get_vertex_position', 'gs_bone_weight_get_vertex_bone_weights' }
-- CVar reads, mod-off (the unhook is UE4SS UnregisterHook per hook: no UFunction)
C['probe.cvar.r.FreeSkeletalMeshBuffers'] = { CVAR }
C['probe.cvar.PBZ.Character.EnableHeadBonesToRemove'] = { CVAR }
C['modoff.hide'] = { ACTOR_HIDDEN }
C['modoff.unhook'] = {}
-- ---------- the beta's dismemberment (docs/research/beta-dismemberment-plan.md BD0) ----------
-- Kept in B and reached through C's __index: LAB.sig(name) and every C[name] find these rows as any other, while
-- pairs(C) (lab_plan's sig pass over every class, the M1a data tests) still walks the 43 section 3.4 names only, so
-- the dev and probe profiles check what they checked before. Each beta module asks LAB.sig for its own names at first
-- use; lab_plan's beta sig pass (BD9) names the ones its route needs.
local B = {}
-- lab_look (BD5): the candidate loads (LoadAsset, a loader global), the material, texture and static mesh reads, the
-- transient MID of a plain Material, the slicer CDO and FindAllOf (loader lookups and property reads), the LVF CVar;
-- lab_cap's hidden test section (BD11)
B['cap.look.load'] = {}
B['cap.look.read'] = join('mat_iface_get_base_material', MIC_GET, SM_READ, 'texture2d_blueprint_get_size_x',
    'texture2d_blueprint_get_size_y')
B['cap.look.mid'] = join('kmat_create_dynamic_material_instance', MID_GET, 'mat_iface_get_base_material')
B['cap.look.slicer'] = {}
B['cap.look.section'] = { SECTION, SECTIONS, 'procmesh_set_mesh_section_visible', P_SET_MAT, P_GET_MAT }
B['probe.cvar.r.Material.IgnoreLVFUsageMode'] = { CVAR }
-- lab_fade (BD13): the slot materials and the slot-0 MID's dissolve time stamps (the rest are property reads);
-- lab_census (BD6): the components, bones, attach reads, slot materials and attached actors, the head bounds, the body
-- size
B['lab.read.dissolve'] = { P_MATS, P_GET_MAT, 'mid_k2_get_scalar_parameter_value' }
B['lab.read.census'] = join(LEADERS, 'scene_get_socket_transform', SCAN, P_GET_MAT, 'actor_get_attached_actors')
B['lab.read.bounds'] = { 'ksl_get_component_bounds' }
B['lab.read.bodysize'] = { 'slicer_get_skeletal_mesh_physics_body_size' }
-- lab_gib (the author's answers 6 and 7): its asset loads (LoadAsset), the carriers, the chunk and hat meshes, their
-- physics, the head-break FX, the destroys; the hats and masks that fall (a copy of a static or skinned extra at its
-- world transform, on its own carrier); the cloth hair kept on the flying head (a ChaosClothComponent copy led by the
-- head poseable, the held Piece shown or destroyed)
B['gib.load'] = {}
B['gib.spawn'] = { BEGIN, FINISH, ADD, 'prim_set_collision_enabled', 'box_set_box_extent', ACTOR_HIDDEN, P_WORLD }
B['gib.mesh'] = join(ADD, 'prim_set_collision_enabled', NO_CULL, 'static_mesh_comp_set_static_mesh',
    'static_mesh_get_bounds', P_MATS, P_GET_MAT, P_SET_MAT, MID, MID_COLOR, P_WORLD, HIDDEN)
B['gib.phys'] = join(PHYS, 'prim_add_angular_impulse_in_degrees', ACTOR_HIDDEN)
B['gib.fx'] = { 'niagara_spawn_system_at_location' }
B['gib.destroy'] = { DESTROY_ACTOR, GET_OWNER, DESTROY_COMP }
B['extra.fall'] = join(BEGIN, FINISH, ADD, 'prim_set_collision_enabled', NO_CULL, 'box_set_box_extent', ACTOR_HIDDEN,
    'static_mesh_comp_set_static_mesh', P_ASSET, P_COPY, P_MATS, P_GET_MAT, P_SET_MAT, P_WORLD, TO_WORLD,
    'scene_get_socket_transform', PHYS, 'prim_add_angular_impulse_in_degrees', DESTROY_ACTOR)
B['hair.keep'] = join(ADD, NO_CULL, 'chaos_cloth_get_asset', 'chaos_cloth_set_asset',
    'chaos_cloth_set_enable_simulation', 'skinned_set_leader_pose_component', P_MATS, P_GET_MAT, P_SET_MAT, P_WORLD,
    ATTACH, REL, HIDDEN, ACTOR_HIDDEN, GET_OWNER, DESTROY_COMP, DESTROY_ACTOR)
-- lab_corpse (the beta's corpse keep): the keep levers are property writes with read-back (keep.write's kind); the
-- on-screen read of a due corpse; the vanish (the dissolve lever back, then the Blueprint BP_RenewalNPC_C:Vanish(),
-- no /Script path, so no calls row: lab_corpse checks its arity itself at its first call); the destroy
B['corpse.keep'] = {}
B['corpse.seen'] = { 'actor_was_recently_rendered' }
B['corpse.vanish'] = {}
B['corpse.destroy'] = { DESTROY_ACTOR }
-- lab_slice (docs/research/slicer-stumps.md): the reads (the skinned components, bones, LOD counts, material slots,
-- simulation; the CapMaterial lookups and the streaming flags are loader lookups and property reads), the LODInfo bit
-- (property reads), the crash-flagged CVar, the preflight, M_SKInteriror's LoadAsset and its hold on the player
-- controller's keeper (ue.hold: the keeper component, never culled, hidden, the material slot), the material flags,
-- the cut per body asset (the lab's report form and the production form; the cut frame's Akasha-half check lists the
-- components), the after reads (the halves' bounds too), the re-home, the source fix and its read-back, the head-half
-- impulse; a sliced corpse's going under lab_corpse (its Vanish has no /Script path: lab_corpse checks its arity)
local SLICE = { 'slicer_slice_skeletal_mesh_component_runtime_with_debug_report',
    'slicer_slice_skeletal_mesh_component_runtime', 'actor_k2_get_components_by_class' }
B['slicer.read'] = join(LEADERS, 'scene_get_socket_transform', 'skinned_get_num_lods', P_MATS, P_GET_MAT,
    'scene_is_simulating_physics')
B['slicer.lodinfo'] = { 'skinned_get_num_lods' }
-- the route's LOD experiment (lab_slice_lod): the LOD 0 and LOD 1-3 preflights (the bit itself is a property write;
-- GetNumLODs bounds k), Prepare, Release, the wait for the prepared LOD (ForcedLodModel is a property read), the
-- prepared cut (k bounded again, the forced and predicted LOD read again, the slice, the result's components)
B['slicer.cpuflag'] = { 'slicer_debug_skeletal_mesh_slice_preflight', 'skinned_get_num_lods' }
B['slicer.lodpre'] = B['slicer.cpuflag']
B['slicer.prepare'] = { 'slicer_prepare_skeletal_mesh_slice_runtime' }
B['slicer.release'] = { 'slicer_release_prepared_skeletal_mesh_slice' }
B['slicer.prep.read'] = { 'skinned_get_predicted_lod_level' }
B['slicer.cut.prep'] = { 'slicer_slice_prepared_skeletal_mesh_component_runtime', 'actor_k2_get_components_by_class',
    'skinned_get_num_lods', 'skinned_get_predicted_lod_level' }
B['probe.cvar.z.sliceUseEngineSetAllBodiesSimulatePhysics'] = { CVAR }
B['slicer.preflight'] = { 'slicer_debug_skeletal_mesh_slice_preflight' }
B['slicer.load'] = { ADD, NO_CULL, HIDDEN, P_SET_MAT }
B['slicer.mat'] = { 'mat_iface_get_base_material' }
B['slicer.cut.malethug'] = SLICE
B['slicer.cut.guichai'] = SLICE
-- the production route (lab_slice_route): every other cut class by its row's route, and the re-slice of a half
B['slicer.cut.body'] = SLICE
B['slicer.cut.meshhead'] = SLICE
B['slicer.reslice'] = SLICE
B['slicer.after'] = join(B['slicer.read'], 'ksl_get_component_bounds')
B['slicer.rehome'] = { ATTACH, 'skinned_set_leader_pose_component', 'actor_k2_get_components_by_class' }
B['slicer.fix'] = { 'prim_set_simulate_physics', 'scene_is_simulating_physics' }
B['slicer.push'] = { 'prim_add_impulse' }
B['slicer.gone'] = { DESTROY_ACTOR }
-- a sliced head's hats and masks: lab_slice_route's read of each one's world transform and its hide (the actor's
-- components listed), lab_gib's falling copies (extra.fall's calls under their own name)
B['slicer.drop'] = { 'actor_k2_get_components_by_class', TO_WORLD, HIDDEN }
B['slicer.fall'] = B['extra.fall']
-- the test build's listener of the game's own slice (lab_slice_watch): the source component's owner and LOD count, the
-- owner's skeletal components (its Akasha halves), each half's LOD count and last material slot; the LOD bits and the
-- streaming flags are property reads
B['slicer.watch'] = { GET_OWNER, 'actor_k2_get_components_by_class', 'skinned_get_num_lods', P_MATS, P_GET_MAT }
-- the native Cap look (route B, lab_cap): the vertebra stub on a neck Stump Cap (ue.add_component with no_collision,
-- the hidden add, SetStaticMesh, the attach to the Cap and its pose)
B['cap.stub'] = join(ADD, 'prim_set_collision_enabled', NO_CULL, HIDDEN, 'static_mesh_comp_set_static_mesh', ATTACH,
    REL)
-- and the wound ring on every native Stump Cap: the attached decal, hidden until the Cap shows
B['cap.ring'] = { 'statics_spawn_decal_attached', HIDDEN }
-- blood on the sword (lab_sword, the beta; sword.byinfo the test build's lab_sword_looks): the census (the pawn's
-- attached actors, each weapon mesh's owner, slot count and slot materials; the sockets, flags, parents and custom
-- primitive data are property reads), a donor's LoadAsset (a loader global) and its hold on the player controller's
-- keeper (ue.hold, as slicer.load; also a game MID's hold while ours is on its slots), our MID (the
-- library's), the copy, the swap with its read-back, the by-name writes and read-backs on our MID, the custom primitive
-- data setter on the game's mesh, the by-info probe, the restore (the slots, the data, the read-back)
local CPD_FLOAT = 'prim_set_custom_primitive_data_float'
B['sword.read'] = { 'actor_get_attached_actors', GET_OWNER, P_MATS, P_GET_MAT }
B['sword.load'] = { ADD, NO_CULL, HIDDEN, P_SET_MAT }
B['sword.mid'] = { 'kmat_create_dynamic_material_instance' }
B['sword.copy'] = { 'mid_k2_copy_material_instance_parameters' }
B['sword.mat'] = { P_SET_MAT, P_GET_MAT }
B['sword.amt'] = { 'mid_set_scalar_parameter_value', MID_COLOR, 'mid_k2_get_scalar_parameter_value',
    'mid_k2_get_vector_parameter_value' }
B['sword.cpd'] = { CPD_FLOAT }
B['sword.byinfo'] = { 'mid_set_scalar_parameter_value_by_info', 'mid_set_vector_parameter_value_by_info',
    'mid_k2_get_scalar_parameter_value_by_info' }
B['sword.restore'] = { P_SET_MAT, P_GET_MAT, CPD_FLOAT }
-- Jamon Iberico (lab_iberico): a parent's find or LoadAsset (a loader global), our PNG's import on the rendering
-- library's CDO, the texture's size getters (its other reads are properties), our atlas MID (the library's), its
-- texture parameter and the read-back; the hold is cap.keep's
B['cap.tex.load'] = {}
B['cap.tex.import'] = { 'krl_import_file_as_texture2d' }
B['cap.tex.read'] = { 'texture2d_blueprint_get_size_x', 'texture2d_blueprint_get_size_y' }
B['cap.tex.mid'] = { 'kmat_create_dynamic_material_instance', MID_TEX, 'mid_k2_get_texture_parameter_value' }
return setmetatable(C, { __index = B })
