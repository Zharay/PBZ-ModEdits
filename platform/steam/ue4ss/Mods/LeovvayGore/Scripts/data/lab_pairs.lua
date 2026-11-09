-- lab data: A5.3 filled MaleThug and death_source after TC-LAB-01; GuiChai keeps the mannequin guesses (RC never read
-- it: Summon left it invisible), so its rows read INCONCLUSIVE in TC-LAB-02
-- data/lab_pairs.lua: the two TC-LAB-02 pair layouts (spec M1a A1.10; D6, D8, D9, D10, D12). Pure data: no require.
-- The lab modules read it (dev, probe and the player beta); main.lua lists it in CODE for the code hash. Names and
-- buckets only: no radius, capsule size or other game-derived number lands here (rule 10, HR-FAL-PRIVACY); a stand-in
-- scale bucket is a rounded class (D8). tests/test_lab_data.lua refuses any other number and any key naming a radius.
-- * death_source (D6): the hook id TC-LAB-01 L0p chose (a data/hooks.lua hooks key such as 'h03'), written by A5.3; nil:
--   the poll stays the death source. lab_poll (A3.1) then reads the victim on the tick after that hook's fire.
-- * buckets (D8 [P]): the stand-in scale classes; A5.3 maps clamp(0.6 x r / 5 cm, 0.5, 3.0) to the nearest one and
--   commits only that class, never the radius r.
-- * pair[<label>], the labels of lab_probe LAB.PAIRS:
--   - class, class_path: the pawn class the spawn keys spawn (D12); class_path is '<package>.<class>', the form
--     ue.asset loads and Summon takes. Package paths: usmap_struct_paths.tsv:22305 and :23695 (spec M1a D12, 2.2).
--   - route (D10): 'body_copy' (the Piece is a posed copy of the body mesh, isolated in three writes) or 'meshhead' (the
--     Piece is the meshhead component's mesh plus the head components, posed from the leader, no isolation).
--   - head_comps: the head components data/hide_table.lua lists for the class (hidden and tagged at a head cut, D9).
--   - iso: the isolation root of the body copy; nil = the mesh's root bone (D10).
--   - parts[<part>] (the cap_attach part names): cut = the cut-bone candidates, child = its child candidates (the first
--     candidate GetBoneIndex finds wins, per mesh; the child gives the bone direction d of section 3.8), stump = the
--     stump-bone candidates (empty: the live GetParentBone of the cut bone, D9), scale = the stand-in scale bucket of
--     that joint (D8; 1.0 until A5.3).
--   Bone names are the UE mannequin names of lab_rc.lua M.TARGETS [inferred]; A5.3 replaces them with the RC names
--   per layout, and a layout RC did not read keeps these and reads INCONCLUSIVE in TC-LAB-02.
-- * The player beta's clone layouts (docs/research/beta-dismemberment-plan.md BD9, replacing beta port S3): BodyCopy
--   (MaleThug's route, parts and buckets) and MeshHead (GuiChai's), the layout data/cut_classes.lua gives every cut
--   class beyond the two pairs' own (lab_plan's beta decide passes it as d.pair). Their head part widens the bone
--   candidates for rigs no lab read: cut { neck_01, neck }, child { Head, head } (FName compares ignore case; the
--   second spelling serves a case-sensitive mock). No class or class_path: nothing spawns them. They sit behind
--   pair's __index, so pair_of(label) in lab_cut, lab_cap and lab_piece finds them while pairs(P.pair) (the
--   TC-LAB-02 pair checks of tests/test_lab_data.lua) still walks the two spawned pairs only.
local P = {}
-- A5.3 (TC-LAB-01 session 20261030-1522): h03 OnCodexTrackedEnemyDied and h18 SetCharacterToDie each fired once on
-- all 7 spawned MaleThug kills, one frame after the kill's h20 event and before the poll confirm; h03 taken (h18 the
-- same frames); neither fired on the 2 NPC kills by NPCs
P.death_source = 'h03'
P.buckets = { 0.75, 1.0, 1.25, 1.5, 2.0 }
P.pair = {
    MaleThug = {
        class = 'BP_Monster_MaleThug_Sword_Blue_C',
        class_path = '/PBZCombatAsset/ActorData/Mobs/003_MaleThug/BP_Monster_MaleThug_Sword_Blue'
            .. '.BP_Monster_MaleThug_Sword_Blue_C',
        route = 'body_copy',
        head_comps = {},                -- hide_table.lua: no head component on this class (one body mesh)
        iso = nil,                      -- RC: the mesh's root bone is Root
        -- A5.3: the RC names of MaleThug_Body (164 bones; neck_02 sits between neck_01 and Head, bone_dir walks it) and
        -- the D8 buckets from the RC physics bodies (no neck body: the head joint takes the Head body's bucket)
        parts = {
            head = { cut = { 'neck_01' }, child = { 'Head' }, stump = {}, scale = 1.0 },
            upperarm_l = { cut = { 'upperarm_l' }, child = { 'lowerarm_l' }, stump = {}, scale = 0.75 },
            upperarm_r = { cut = { 'upperarm_r' }, child = { 'lowerarm_r' }, stump = {}, scale = 0.75 },
            lowerarm_l = { cut = { 'lowerarm_l' }, child = { 'hand_l' }, stump = {}, scale = 0.75 },
            lowerarm_r = { cut = { 'lowerarm_r' }, child = { 'hand_r' }, stump = {}, scale = 0.75 },
            thigh_l = { cut = { 'thigh_l' }, child = { 'calf_l' }, stump = {}, scale = 1.25 },
            thigh_r = { cut = { 'thigh_r' }, child = { 'calf_r' }, stump = {}, scale = 1.25 },
            calf_l = { cut = { 'calf_l' }, child = { 'foot_l' }, stump = {}, scale = 0.75 },
            calf_r = { cut = { 'calf_r' }, child = { 'foot_r' }, stump = {}, scale = 0.75 },
        },
    },
    GuiChai = {
        class = 'BP_Monster_GuiChai_Black_TwinBlade_C',
        class_path = '/PBZCombatAsset/ActorData/Mobs/037_GuiChai/Blueprints/BP_Monster_GuiChai_Black_TwinBlade'
            .. '.BP_Monster_GuiChai_Black_TwinBlade_C',
        route = 'meshhead',
        head_comps = { 'meshhead' },    -- hide_table.lua: the head category of this class
        iso = nil,
        parts = {
            head = { cut = { 'neck_01', 'neck' }, child = { 'head' }, stump = {}, scale = 1.0 },
            upperarm_l = { cut = { 'upperarm_l' }, child = { 'lowerarm_l', 'forearm_l' }, stump = {}, scale = 1.0 },
            upperarm_r = { cut = { 'upperarm_r' }, child = { 'lowerarm_r', 'forearm_r' }, stump = {}, scale = 1.0 },
            lowerarm_l = { cut = { 'lowerarm_l', 'forearm_l' }, child = { 'hand_l' }, stump = {}, scale = 1.0 },
            lowerarm_r = { cut = { 'lowerarm_r', 'forearm_r' }, child = { 'hand_r' }, stump = {}, scale = 1.0 },
            thigh_l = { cut = { 'thigh_l' }, child = { 'calf_l' }, stump = {}, scale = 1.0 },
            thigh_r = { cut = { 'thigh_r' }, child = { 'calf_r' }, stump = {}, scale = 1.0 },
            calf_l = { cut = { 'calf_l' }, child = { 'foot_l' }, stump = {}, scale = 1.0 },
            calf_r = { cut = { 'calf_r' }, child = { 'foot_r' }, stump = {}, scale = 1.0 },
        },
    },
}
-- The beta's clone layouts (header): a copy of a pair's route, head components, iso and parts (lists copied, buckets
-- kept), its head part's candidates widened
local function clone(src, cut, child)
    local parts = {}
    for name, p in pairs(src.parts) do
        parts[name] = { cut = { table.unpack(p.cut) }, child = { table.unpack(p.child) },
            stump = { table.unpack(p.stump) }, scale = p.scale }
    end
    parts.head.cut, parts.head.child = cut, child
    return { route = src.route, head_comps = { table.unpack(src.head_comps) }, iso = src.iso, parts = parts }
end
setmetatable(P.pair, { __index = {
    BodyCopy = clone(P.pair.MaleThug, { 'neck_01', 'neck' }, { 'Head', 'head' }),
    MeshHead = clone(P.pair.GuiChai, { 'neck_01', 'neck' }, { 'Head', 'head' }),
} })
return P
