"use strict";
// PhantomHUD: generated from the same source as the PBZModLoader edition.
(function(externalRequire, entryExports) {
  const factories={"./main": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.ready = void 0;
exports.stop = stop;
const UE = require("ue");
const puerts_1 = require("puerts");
const renderer_1 = require("./renderer");
const buffs_1 = require("./buffs");
const native_1 = require("./native");
const ui_state_1 = require("./ui-state");
const fade_1 = require("./fade");
const settings_1 = require("./settings");
const native_bars_1 = require("./native-bars");
const BAR_PATH = '/Game/PBZContent/UI/Hud/PBZAnimProgressBar2.PBZAnimProgressBar2_C';
let timer;
let renderer, buffs;
let bar, hud;
let nextSearch = 0, lastTime = Date.now(), nextRefresh = 0, retryAt = 0, lastError = -Infinity;
let lastPawn, lastWorld;
let warnedHudLookup = false;
const fade = new fade_1.Fade();
const settings = new settings_1.Settings();
const nativeBars = new native_bars_1.NativeBars();
let duration = { show: .4, hide: .4 };
// Optional guard-break overlay backported from the verified 0.4.0 state reader.
// No health, layout, binding or visibility changes belong in this backport.
const guardBreakState = { tag: '', nextTag: 0, lastError: -Infinity, active: false };
function guardBreakBand(pawn, now) {
    try {
        if (!guardBreakState.tag && now >= guardBreakState.nextTag) {
            guardBreakState.nextTag = now + 5000;
            const cls = UE.Class.Load('/PBZCombatAsset/Prototypes/Hitreact/BP_HitreactEventListener_BreakEnd.BP_HitreactEventListener_BreakEnd_C');
            if (cls) {
                // Read the blueprint's default tag only; never register a listener.
                const definition = UE.NewObject(cls);
                const tag = definition?.Tag?.TagName;
                if (tag && tag !== 'None') {
                    guardBreakState.tag = String(tag);
                    (0, native_1.log)('break-end listener state tag: ' + guardBreakState.tag);
                }
            }
        }
        let broken = false;
        if (guardBreakState.tag) {
            const inf = UE.BlueprintGameplayTagLibrary.Conv_ObjectToGameplayTagAssetInterface(pawn);
            if (inf) {
                const tags = UE.BlueprintGameplayTagLibrary.GetOwnedGameplayTags(inf).GameplayTags;
                for (let i = 0; i < tags.Num(); i++) {
                    const tag = String(tags.Get(i).TagName);
                    if (tag === guardBreakState.tag || tag.startsWith(guardBreakState.tag + '.')) {
                        broken = true;
                        break;
                    }
                }
            }
        }
        if (broken !== guardBreakState.active) {
            guardBreakState.active = broken;
            (0, native_1.log)('guard break ' + (broken ? 'started' : 'ended'));
        }
        if (broken) return {
            from: 0, to: 1,
            color: (0, native_1.rgba)(2.5, .025, .012, 1),
            opacity: .72 + .12 * Math.sin(now / 1000 * Math.PI * 2),
        };
    } catch (e) {
        guardBreakState.active = false;
        if (now - guardBreakState.lastError > 5000) {
            guardBreakState.lastError = now;
            (0, native_1.log)('optional guard-break read unavailable: ' + String(e));
        }
    }
}

function find(context) {
    let current, authoritative = false;
    try {
        if (typeof UE.PBZHUDLayout?.GetHUDLayout === 'function') {
            current = UE.PBZHUDLayout.GetHUDLayout(context);
            authoritative = true;
        }
    }
    catch (e) {
        if (!warnedHudLookup) {
            warnedHudLookup = true;
            (0, native_1.log)('current HUD lookup unavailable; retaining stable baseline binding: ' + String(e));
        }
    }
    // Verified in game: null during loading, current embedded HUD during gameplay.
    // Do not draw an old cached HUD while the game has no current layout.
    if (authoritative && (!current || !(0, native_1.valid)(current)))
        return;
    const cls = UE.Class.Load(BAR_PATH);
    if (!cls)
        return;
    const out = (0, puerts_1.$ref)(undefined);
    UE.WidgetBlueprintLibrary.GetAllWidgetsOfClass(context, out, cls, false);
    const list = (0, puerts_1.$unref)(out);
    let fallback;
    for (let i = 0; i < list.Num(); i++) {
        const candidate = list.Get(i);
        if (candidate && (0, native_1.valid)(candidate) && candidate.MID_Bar && (0, native_1.valid)(candidate.MID_Bar)) {
            if (authoritative) {
                if ((0, ui_state_1.owningHud)(candidate) === current)
                    return candidate;
                continue;
            }
            if (!fallback)
                fallback = candidate;
            // Compatibility fallback only: preserve a valid binding, never oscillate
            // between cached HUDs based on visibility or enumeration order.
            if (candidate === bar)
                return candidate;
        }
    }
    return fallback;
}
function hide() { try { nativeBars.reset(); } catch { } try {
    renderer?.hide();
}
catch { } try {
    buffs?.hide();
}
catch { } fade.reset(); }
function release() {
    hide();
    try {
        renderer?.stop();
    }
    catch { }
    try {
        buffs?.stop();
    }
    catch { }
    renderer = undefined;
    buffs = undefined;
    bar = undefined;
    hud = undefined;
    guardBreakState.active = false;
    nextSearch = 0;
    nextRefresh = 0;
}
function tick() {
    const now = Date.now(), dt = Math.max(0, Math.min(.25, (now - lastTime) / 1000));
    lastTime = now;
    settings.update(now);
    if (now < retryAt)
        return;
    try {
        const gi = puerts_1.argv.getByName('GameInstance');
        if (!gi) {
            hide();
            return;
        }
        const pawn = UE.GameplayStatics.GetPlayerPawn(gi, 0);
        if (!pawn || !(0, native_1.valid)(pawn)) {
            hide();
            bar = undefined;
            hud = undefined;
            nextSearch = 0;
            return;
        }
        let changed = !!lastPawn && lastPawn !== pawn;
        // Optional transition hint, NOT a new requirement for rendering.
        try {
            const world = gi.GetWorld();
            if (world && (0, native_1.valid)(world)) {
                changed = changed || (!!lastWorld && lastWorld !== world);
                lastWorld = world;
            }
        }
        catch { /* Some contexts do not expose a usable world; keep the 0.2.2 path. */ }
        if (renderer && !renderer.isAttached())
            changed = true;
        if (changed)
            release();
        lastPawn = pawn;
        if (bar && now >= nextRefresh) {
            nextRefresh = now + 1000;
            const refreshed = find(gi);
            if (refreshed !== bar) {
                release();
                bar = refreshed;
                if (bar) {
                    hud = (0, ui_state_1.owningHud)(bar);
                    duration = (0, ui_state_1.hudDurations)(hud);
                    nextRefresh = now + 1000;
                    (0, native_1.log)('rebound ' + UE.KismetSystemLibrary.GetPathName(bar));
                }
            }
            else if (bar) {
                // A game can also reuse the same bar while moving it to another HUD.
                const owner = (0, ui_state_1.owningHud)(bar);
                if (owner !== hud) {
                    try {
                        buffs?.stop();
                    }
                    catch { }
                    buffs = undefined;
                    hud = owner;
                    duration = (0, ui_state_1.hudDurations)(hud);
                }
            }
        }
        if (!bar || !(0, native_1.valid)(bar) || !(0, native_1.valid)(bar.MID_Bar)) {
            hide();
            if (now < nextSearch)
                return;
            nextSearch = now + 1000;
            bar = find(gi);
            if (!bar)
                return;
            nextRefresh = now + 1000;
            hud = (0, ui_state_1.owningHud)(bar);
            duration = (0, ui_state_1.hudDurations)(hud);
            (0, native_1.log)('bound ' + UE.KismetSystemLibrary.GetPathName(bar));
            (0, native_1.log)('native HUD fade seconds ' + JSON.stringify(duration));
        }
        if (!renderer || !renderer.isAttached()) {
            renderer?.stop();
            renderer = new renderer_1.InkRenderer(gi);
        }
        if (!hud || !(0, native_1.valid)(hud))
            hud = (0, ui_state_1.owningHud)(bar);
        const mid = bar.MID_Bar;
        const fg = mid.K2_GetScalarParameterValue('BarRatio_FG'), bg = mid.K2_GetScalarParameterValue('BarRatio_BG');
        if (!Number.isFinite(fg) || !Number.isFinite(bg))
            throw new Error('Invalid material ratios');
        const bands = [
            { from: 0, to: bg, color: mid.K2_GetVectorParameterValue('Color_BG'), opacity: 1 },
            { from: 0, to: fg, color: mid.K2_GetVectorParameterValue('Color_FG'), opacity: 1 },
        ];
        const image = bar.ImageBar;
        if (!image || !(0, native_1.valid)(image)) {
            hide();
            return;
        }
        const tint = image.ColorAndOpacity;
        for (const band of bands) {
            band.color.R *= tint.R;
            band.color.G *= tint.G;
            band.color.B *= tint.B;
            band.color.A *= tint.A;
        }
        const breakBand = guardBreakBand(pawn, now);
        if (breakBand) bands.push(breakBand);
        const target = (0, fade_1.hideFullBar)(fg, bg, (0, ui_state_1.isOffCombat)(pawn)) ? 0 : (0, ui_state_1.sourceOpacity)(image);
        const opacity = fade.step(target, dt, duration.show, duration.hide);
        renderer.update(gi, bands, opacity, settings.values);
        if (hud && settings.values.Buffs) {
            if (!buffs || !buffs.isAttached()) {
                buffs?.stop();
                buffs = new buffs_1.BuffMirror(gi);
            }
            buffs.update(hud, dt, duration, opacity, settings.values);
        }
        else {
            buffs?.stop();
            buffs = undefined;
        }
        try { nativeBars.update(bar, settings.values, now, hud); } catch { /* Optional native-bar hiding never interrupts ink rendering. */ }
    }
    catch (e) {
        release();
        retryAt = now + 1000;
        if (now - lastError >= 5000) {
            lastError = now;
            (0, native_1.log)('temporary error; retry in 1s: ' + String(e));
        }
    }
}
function stop() {
    settings.stop();
    if (timer !== undefined) {
        clearInterval(timer);
        timer = undefined;
    }
    release();
    lastPawn = undefined;
    lastWorld = undefined;
    (0, native_1.log)('stopped; viewport resources released');
}
(0, native_1.log)('0.5.1 starting; optional Mods Menu settings; game-owned current HUD binding');
timer = setInterval(tick, 16);
exports.ready = true;

},
"./native": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.log = exports.rgba = exports.v2 = exports.valid = void 0;
exports.create = create;
exports.viewport = viewport;
const UE = require("ue");
const valid = (o) => UE.KismetSystemLibrary.IsValid(o);
exports.valid = valid;
const v2 = (x, y) => UE.KismetMathLibrary.MakeVector2D(x, y);
exports.v2 = v2;
const rgba = (r, g, b, a = 1) => UE.KismetMathLibrary.MakeColor(r, g, b, a);
exports.rgba = rgba;
const log = (message) => console.log(`[PBZMOD] PhantomHUD ${message}`);
exports.log = log;
function create(type, outer) {
    // The SDK only declares the one-argument factory. Check the result's Outer
    // before relying on the bridge's optional Outer argument on this game build.
    const factory = UE.NewObject;
    const obj = outer ? factory(type.StaticClass(), outer) : UE.NewObject(type.StaticClass());
    if (!obj || !(0, exports.valid)(obj))
        throw new Error('Cannot construct ' + type.StaticClass().GetName());
    if (outer && obj.GetOuter() !== outer)
        throw new Error('NewObject Outer argument not supported');
    return obj;
}
function viewport() {
    const s = UE.SubsystemBlueprintLibrary.GetEngineSubsystem(UE.GameViewportSubsystem.StaticClass());
    if (!s || !(0, exports.valid)(s))
        throw new Error('Viewport subsystem unavailable');
    return s;
}

},
"./renderer": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.InkRenderer = void 0;
exports.placements = placements;
exports.backdropSlices = backdropSlices;
exports.reflectedRect = reflectedRect;
const UE = require("ue");
const native_1 = require("./native");
const layout_1 = require("./layout");
const settings_1 = require("./settings");
// Preserve the original bar dimensions. MirrorX flips only the local artwork;
// MirrorY swaps the two regions without reversing either bar's fill direction.
const HAS_HEALTH = false;
const clamp = (value, min, max) => Math.max(min, Math.min(max, value));
const percent = (value, fallback = 100) => Number.isFinite(value) ? Number(value) / 100 : fallback / 100;
function placements(g, s) {
    const regions = HAS_HEALTH ? ['health', 'energy'] : ['energy'];
    return regions.map(region => {
        const health = region === 'health', upper = health !== !!s.MirrorY;
        const top = HAS_HEALTH ? (upper ? 133.6 : 766 + 1488 * .016 / 2) : 245.2;
        const bottom = HAS_HEALTH ? (upper ? 766 - 1488 * .016 / 2 : 133.6 + 1264.8) : 245.2 + 1041.6;
        return { region, top, bottom, length: bottom - top, dx: 0, width: g.tw,
            opacity: clamp(percent(health ? s.HealthOpacity : s.EnergyOpacity), 0, 1) };
    }).sort((a, b) => a.top - b.top);
}
function backdropSlices(p) {
    const slices = p.map(v => ({ ...v }));
    // Bridge the centre gap exactly once. Equal adjacent slices are merged to
    // preserve the original unbroken background at default size and opacity.
    for (let i = 0; i < slices.length - 1; i++)
        slices[i].bottom = slices[i + 1].top;
    const innerTop = HAS_HEALTH ? 133.6 : 245.2, innerBottom = HAS_HEALTH ? 1398.4 : 1286.8;
    if (slices[0].top <= innerTop + 1e-6 && slices[slices.length - 1].bottom >= innerBottom - 1e-6) {
        slices[0].top = 0;
        slices[slices.length - 1].bottom = 1536;
    }
    const out = [];
    for (const s of slices) {
        const prev = out[out.length - 1];
        if (prev && Math.abs(prev.bottom - s.top) < 1e-6 && prev.width === s.width && prev.dx === s.dx && prev.opacity === s.opacity)
            prev.bottom = s.bottom;
        else
            out.push(s);
    }
    return out;
}
function reflectedRect(g, dx, width, top, bottom, s) {
    const x = g.tx + dx, y = g.ty + top * g.scale, h = Math.max(0, (bottom - top) * g.scale);
    return { x: s.MirrorX ? 2 * g.cx - x - width : x, y, width, height: h, imageY: g.ty };
}
class InkRenderer {
    constructor(context) {
        this.bases = [];
        this.layers = [];
        this.textures = [];
        this.width = -1;
        this.height = -1;
        this.root = (0, native_1.create)(UE.CanvasPanel, context);
        this.system = (0, native_1.viewport)();
        this.root.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
        try {
            const dir = UE.BlueprintPathsLibrary.ProjectDir() + 'Content/JavaScript/PBZModsMenu/Mods/PhantomHUD/assets/';
            for (const filename of ['ink-base.png', HAS_HEALTH ? 'ink-inner-baked.png' : 'ink-fill.png']) {
                const texture = UE.KismetRenderingLibrary.ImportFileAsTexture2D(context, dir + filename);
                if (!texture)
                    throw new Error('Cannot import ' + filename);
                this.textures.push(texture);
            }
            const pair = (texture, z) => {
                const clip = (0, native_1.create)(UE.CanvasPanel), image = (0, native_1.create)(UE.Image);
                clip.SetClipping(UE.EWidgetClipping.ClipToBoundsAlways);
                clip.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
                image.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
                image.SetBrushFromTexture(texture, false);
                image.SetRenderTransformPivot((0, native_1.v2)(.5, .5));
                const clipSlot = this.root.AddChildToCanvas(clip), imageSlot = clip.AddChildToCanvas(image);
                if (!clipSlot || !imageSlot)
                    throw new Error('Layer slot unavailable');
                clipSlot.SetZOrder(z);
                return { clip, image, clipSlot, imageSlot };
            };
            for (let i = 0; i < (HAS_HEALTH ? 2 : 1); i++)
                this.bases.push(pair(this.textures[0], i));
            for (let i = 0; i < (HAS_HEALTH ? 5 : 4); i++)
                this.layers.push(pair(this.textures[1], 10 + i));
            const slot = this.system.GetWidgetSlot(this.root);
            slot.Anchors.Minimum = (0, native_1.v2)(0, 0);
            slot.Anchors.Maximum = (0, native_1.v2)(0, 0);
            slot.Alignment = (0, native_1.v2)(0, 0);
            slot.Offsets.Left = 0;
            slot.Offsets.Top = 0;
            slot.ZOrder = 20;
            slot.bAutoRemoveOnWorldRemoved = true;
            if (!this.system.AddWidget(this.root, slot))
                throw new Error('Cannot add HUD to viewport');
            (0, native_1.log)('viewport canvas created; static ink with horizontal mirror, bar order and opacity controls');
        }
        catch (e) {
            this.system.RemoveWidget(this.root);
            throw e;
        }
    }
    isAttached() { return (0, native_1.valid)(this.root) && this.system.IsWidgetAdded(this.root); }
    place(pair, g, p, top, bottom, s) {
        const r = reflectedRect(g, p.dx, p.width, top, bottom, s);
        pair.clipSlot.SetPosition((0, native_1.v2)(r.x, r.y));
        pair.clipSlot.SetSize((0, native_1.v2)(r.width, r.height));
        pair.imageSlot.SetPosition((0, native_1.v2)(0, r.imageY - r.y));
        pair.imageSlot.SetSize((0, native_1.v2)(r.width, g.th));
        pair.image.SetRenderScale((0, native_1.v2)(s.MirrorX ? -1 : 1, 1));
    }
    update(context, bands, opacity, settings = settings_1.DEFAULTS) {
        const size = UE.WidgetLayoutLibrary.GetViewportSize(context), dpi = UE.WidgetLayoutLibrary.GetViewportScale(context);
        if (size.X <= 0 || size.Y <= 0 || dpi <= 0) {
            this.root.SetRenderOpacity(0);
            return;
        }
        const g = (0, layout_1.geometry)(size.X, size.Y, dpi, settings);
        if (g.vw !== this.width || g.vh !== this.height) {
            this.width = g.vw;
            this.height = g.vh;
            const slot = this.system.GetWidgetSlot(this.root);
            slot.Offsets.Right = g.vw;
            slot.Offsets.Bottom = g.vh;
            this.system.SetWidgetSlot(this.root, slot);
        }
        this.root.SetRenderOpacity(clamp(opacity, 0, 1));
        const p = placements(g, settings), slices = backdropSlices(p);
        for (let i = 0; i < this.bases.length; i++) {
            const pair = this.bases[i], slice = slices[i];
            if (!slice || slice.opacity <= 0) {
                pair.clip.SetRenderOpacity(0);
                continue;
            }
            this.place(pair, g, slice, slice.top, slice.bottom, settings);
            pair.clip.SetRenderOpacity(slice.opacity);
        }
        for (let i = 0; i < this.layers.length; i++) {
            const pair = this.layers[i], band = bands[i], region = band?.region ?? 'energy', placement = p.find(v => v.region === region);
            if (!band || !placement || band.to <= band.from || band.opacity <= 0 || placement.opacity <= 0) {
                pair.clip.SetRenderOpacity(0);
                continue;
            }
            const from = clamp(band.from, 0, 1), to = clamp(band.to, 0, 1);
            this.place(pair, g, placement, placement.top + placement.length * (1 - to), placement.top + placement.length * (1 - from), settings);
            pair.clip.SetRenderOpacity(band.opacity * placement.opacity);
            pair.image.SetColorAndOpacity(band.color);
        }
    }
    hide() { if ((0, native_1.valid)(this.root))
        this.root.SetRenderOpacity(0); }
    stop() { if ((0, native_1.valid)(this.root))
        this.system.RemoveWidget(this.root); this.textures = []; this.bases = []; this.layers = []; }
}
exports.InkRenderer = InkRenderer;

},
"./layout": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.INNER_HEIGHT = exports.INNER_TOP = void 0;
exports.geometry = geometry;
exports.buffPosition = buffPosition;
exports.INNER_TOP = 245.2;
exports.INNER_HEIGHT = 1041.6;
function geometry(width, height, dpi, settings = { X: 60, Y: 50, Scale: 100 }) {
    if (!Number.isFinite(width + height + dpi) || width <= 0 || height <= 0 || dpi <= 0)
        throw new Error('Invalid viewport');
    const vw = width / dpi, vh = height / dpi, zoom = settings.Scale / 100, scale = vh * .15 * zoom / 1488;
    const cx = vw * settings.X / 100, cy = vh * settings.Y / 100;
    return { vw, vh, scale, zoom, cx, cy, bodyHeight: vh * .15 * zoom,
        tx: cx - (326 + 471 / 2) * scale, ty: cy - (22 + 1488 / 2) * scale,
        tw: 1024 * scale, th: 1536 * scale };
}
function buffPosition(index, g, iconSize) {
    const row = index % 3, column = Math.floor(index / 3), angle = (row - 1) * Math.PI / 3;
    const rowRadius = Math.max(g.bodyHeight * .4, iconSize * 1.3);
    return { x: g.cx + g.bodyHeight * .23 + Math.cos(angle) * g.bodyHeight * .19 + column * iconSize * 1.3,
        y: g.cy + Math.sin(angle) * rowRadius };
}

},
"./fade": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Fade = void 0;
exports.hideFullBar = hideFullBar;
class Fade {
    constructor() {
        this.value = 0;
    }
    step(target, seconds, showSeconds, hideSeconds) {
        target = Math.max(0, Math.min(1, target));
        const duration = target > this.value ? showSeconds : hideSeconds;
        const delta = Math.max(0, seconds) / Math.max(.001, duration);
        this.value = target > this.value ? Math.min(target, this.value + delta) : Math.max(target, this.value - delta);
        return this.value;
    }
    reset() { this.value = 0; }
}
exports.Fade = Fade;
// Require explicit evidence of OffCombat. Unknown state must not hide a full bar.
function hideFullBar(foreground, lag, offCombat) {
    return offCombat && foreground >= .9999 && lag >= .9999;
}

},
"./ui-state": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.isA = isA;
exports.visualParent = visualParent;
exports.sourceOpacity = sourceOpacity;
exports.owningHud = owningHud;
exports.hudDurations = hudDurations;
exports.isOffCombat = isOffCombat;
const UE = require("ue");
const native_1 = require("./native");
function isA(object, type) {
    return UE.KismetMathLibrary.ClassIsChildOf(object.GetClass(), type);
}
function visualParent(widget) {
    const parent = widget.GetParent();
    if (parent)
        return parent;
    const owner = widget.GetOuter()?.GetOuter();
    if (owner && isA(owner, UE.Widget.StaticClass()))
        return owner;
}
function sourceOpacity(start, stopBefore) {
    if (!start)
        return 0;
    let current = start, opacity = 1;
    const seen = new Set();
    for (let n = 0; current && n < 40; n++) {
        if (current === stopBefore)
            break;
        if (!(0, native_1.valid)(current) || seen.has(current))
            return 0;
        seen.add(current);
        const v = current.GetVisibility();
        if (v === UE.ESlateVisibility.Hidden || v === UE.ESlateVisibility.Collapsed)
            return 0;
        opacity *= current.GetRenderOpacity();
        if (isA(current, UE.UserWidget.StaticClass()))
            opacity *= current.ColorAndOpacity.A;
        current = visualParent(current);
    }
    return Number.isFinite(opacity) ? Math.max(0, Math.min(1, opacity)) : 0;
}
function owningHud(widget) {
    let current = widget;
    for (let n = 0; current && n < 40; n++) {
        if (current.GetClass().GetName() === 'W_FrontEndHUDLayout_C')
            return current;
        current = visualParent(current);
    }
}
function hudDurations(hud) {
    const duration = (a) => {
        if (!a || !(0, native_1.valid)(a))
            return .4;
        const t = a.GetEndTime() - a.GetStartTime();
        return Number.isFinite(t) && t > 0 ? t : .4;
    };
    return { show: duration(hud?.hudshowencounter), hide: duration(hud?.hudhide) };
}
function isOffCombat(pawn) {
    const inf = UE.BlueprintGameplayTagLibrary.Conv_ObjectToGameplayTagAssetInterface(pawn);
    if (!inf)
        return false;
    const tags = UE.BlueprintGameplayTagLibrary.GetOwnedGameplayTags(inf).GameplayTags;
    for (let i = 0; i < tags.Num(); i++)
        if (tags.Get(i).TagName === 'CharacterState.OffCombat')
            return true;
    return false;
}

},
"./buffs": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BuffMirror = void 0;
const UE = require("ue");
const native_1 = require("./native");
const ui_state_1 = require("./ui-state");
const layout_1 = require("./layout");
function children(widget) {
    if ((0, ui_state_1.isA)(widget, UE.UserWidget.StaticClass())) {
        const root = widget.WidgetTree?.RootWidget;
        return root ? [root] : [];
    }
    if ((0, ui_state_1.isA)(widget, UE.PanelWidget.StaticClass())) {
        const a = widget.GetAllChildren(), out = [];
        for (let i = 0; i < a.Num(); i++) {
            const child = a.Get(i);
            if (child)
                out.push(child);
        }
        return out;
    }
    return [];
}
function pairTree(source, copy, out) {
    if (source.GetClass() !== copy.GetClass())
        throw new Error('Buff template type mismatch');
    out.push({ source, copy });
    const a = children(source), b = children(copy);
    if (a.length !== b.length)
        throw new Error('Buff template tree mismatch');
    for (let i = 0; i < a.length; i++)
        pairTree(a[i], b[i], out);
}
// Copy evaluated UMG state, not guessed animation durations. Material brushes
// keep the ORIGINAL live MID, so countdown/shader effects have one clock.
function sync({ source: s, copy: d }) {
    d.SetRenderOpacity(s.GetRenderOpacity());
    d.SetRenderTransform(s.RenderTransform);
    d.SetRenderTransformPivot(s.RenderTransformPivot);
    const visibility = s.GetVisibility();
    d.SetVisibility(visibility === UE.ESlateVisibility.Hidden || visibility === UE.ESlateVisibility.Collapsed ? visibility : UE.ESlateVisibility.HitTestInvisible);
    if ((0, ui_state_1.isA)(s, UE.UserWidget.StaticClass()))
        d.SetColorAndOpacity(s.ColorAndOpacity);
    if ((0, ui_state_1.isA)(s, UE.Image.StaticClass())) {
        const a = s, b = d;
        b.SetBrush(a.Brush);
        b.SetColorAndOpacity(a.ColorAndOpacity);
    }
    if ((0, ui_state_1.isA)(s, UE.WidgetSwitcher.StaticClass()))
        d.SetActiveWidgetIndex(s.GetActiveWidgetIndex());
    const a = s.Slot, b = d.Slot;
    if (a && b && (0, ui_state_1.isA)(a, UE.OverlaySlot.StaticClass()) && (0, ui_state_1.isA)(b, UE.OverlaySlot.StaticClass())) {
        const x = a, y = b;
        y.SetPadding(x.Padding);
        y.SetHorizontalAlignment(x.HorizontalAlignment);
        y.SetVerticalAlignment(x.VerticalAlignment);
    }
    if (a && b && (0, ui_state_1.isA)(a, UE.CanvasPanelSlot.StaticClass()) && (0, ui_state_1.isA)(b, UE.CanvasPanelSlot.StaticClass())) {
        const x = a, y = b;
        y.SetLayout(x.LayoutData);
        y.SetAutoSize(x.bAutoSize);
        y.SetZOrder(x.ZOrder);
    }
}
class BuffMirror {
    constructor(context) {
        this.context = context;
        this.system = (0, native_1.viewport)();
        this.entries = new Map();
        this.sourceContainers = [];
        this.vw = -1;
        this.vh = -1;
        this.root = (0, native_1.create)(UE.CanvasPanel, context);
        this.root.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
        const slot = this.system.GetWidgetSlot(this.root);
        slot.Anchors.Minimum = (0, native_1.v2)(0, 0);
        slot.Anchors.Maximum = (0, native_1.v2)(0, 0);
        slot.Alignment = (0, native_1.v2)(0, 0);
        slot.Offsets.Left = 0;
        slot.Offsets.Top = 0;
        slot.ZOrder = 21;
        slot.bAutoRemoveOnWorldRemoved = true;
        if (!this.system.AddWidget(this.root, slot))
            throw new Error('Cannot add buff canvas');
    }
    isAttached() { return (0, native_1.valid)(this.root) && this.system.IsWidgetAdded(this.root); }
    discard(entry) {
        // Only our copies are removed; original game widgets are never changed.
        try {
            if ((0, native_1.valid)(entry.copy))
                entry.copy.RemoveFromParent();
        }
        catch { }
        try {
            if ((0, native_1.valid)(entry.holder))
                entry.holder.RemoveFromParent();
        }
        catch { }
    }
    clearEntries() { for (const entry of this.entries.values())
        this.discard(entry); this.entries.clear(); }
    update(hud, dt, durations, groupOpacity = 1, settings) {
        const bar = hud.W_BuffBar;
        if (!bar || !(0, native_1.valid)(bar)) {
            this.clearEntries();
            this.sourceContainers = [];
            this.sourceHud = undefined;
            this.hide();
            return;
        }
        const containers = [bar, bar.BuffEntryBox, bar.DeBuffEntryBox, bar.FanStrip?.BuffEntryBox];
        if (hud !== this.sourceHud || containers.some((c, i) => c !== this.sourceContainers[i])) {
            this.clearEntries();
            this.sourceHud = hud;
            this.sourceContainers = containers;
            (0, native_1.log)('buff source rebound ' + hud.GetName());
        }
        const size = UE.WidgetLayoutLibrary.GetViewportSize(this.context), dpi = UE.WidgetLayoutLibrary.GetViewportScale(this.context);
        if (size.X <= 0 || size.Y <= 0 || dpi <= 0) {
            this.hide();
            return;
        }
        const g = (0, layout_1.geometry)(size.X, size.Y, dpi, settings);
        if (g.vw !== this.vw || g.vh !== this.vh) {
            this.vw = g.vw;
            this.vh = g.vh;
            const slot = this.system.GetWidgetSlot(this.root);
            slot.Offsets.Right = g.vw;
            slot.Offsets.Bottom = g.vh;
            this.system.SetWidgetSlot(this.root, slot);
        }
        this.root.SetRenderOpacity(groupOpacity * Math.max(0, Math.min(1, Number(settings?.BuffOpacity ?? 100) / 100)));
        const sources = [];
        const boxes = new Map();
        for (const box of [bar.BuffEntryBox, bar.DeBuffEntryBox, bar.FanStrip?.BuffEntryBox]) {
            if (!box || !(0, native_1.valid)(box))
                continue;
            const list = box.GetAllEntries();
            for (let i = 0; i < list.Num(); i++) {
                const source = list.Get(i);
                if (source && (0, native_1.valid)(source) && source.GetVisibility() !== UE.ESlateVisibility.Collapsed && !sources.includes(source)) {
                    sources.push(source);
                    boxes.set(source, box);
                }
            }
        }
        for (const [source, entry] of this.entries) {
            if (!sources.includes(source)) {
                this.discard(entry);
                this.entries.delete(source);
            }
        }
        for (let index = 0; index < sources.length; index++) {
            const source = sources[index];
            let entry = this.entries.get(source);
            if (entry && (!(0, native_1.valid)(entry.copy) || !(0, native_1.valid)(entry.holder) || entry.copy.GetParent() !== entry.holder || entry.holder.GetParent() !== this.root || entry.pairs.some(p => !(0, native_1.valid)(p.source) || !(0, native_1.valid)(p.copy)))) {
                this.discard(entry);
                this.entries.delete(source);
                entry = undefined;
            }
            if (!entry) {
                // W_BuffIcon is a presentation-only blueprint. Never clone the BuffBar
                // mixin itself, which would subscribe twice to gameplay events.
                if (source.GetClass().GetName() !== 'W_BuffIcon_C') {
                    (0, native_1.log)('unsupported buff type ' + source.GetClass().GetName());
                    continue;
                }
                const copy = UE.WidgetBlueprintLibrary.Create(this.context, source.GetClass(), UE.GameplayStatics.GetPlayerController(this.context, 0));
                if (!copy)
                    throw new Error('Cannot create native buff icon');
                copy.bIsFocusable = false;
                const holder = (0, native_1.create)(UE.CanvasPanel), slot = this.root.AddChildToCanvas(holder), childSlot = holder.AddChildToCanvas(copy);
                if (!slot || !childSlot)
                    throw new Error('Buff slots unavailable');
                holder.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
                const pairs = [];
                pairTree(source, copy, pairs);
                entry = { source, copy, holder, slot, childSlot, pairs };
                this.entries.set(source, entry);
                (0, native_1.log)('mirroring native buff ' + source.GetName());
            }
            for (const pair of entry.pairs)
                sync(pair);
            const geo = source.GetCachedGeometry();
            const local = UE.SlateBlueprintLibrary.GetLocalSize(geo);
            const desired = source.GetDesiredSize();
            const width = local.X > 0 ? local.X : Math.max(1, desired.X), height = local.Y > 0 ? local.Y : Math.max(1, desired.Y);
            // Preserve original on-screen icon size while moving its anchor only.
            // DynamicEntryBox owns Slate entries without a UPanelWidget parent link.
            // Use the box we enumerated, not entry.GetParent(), which can be null.
            const parent = boxes.get(source), pg = parent?.GetCachedGeometry();
            const pl = pg ? UE.SlateBlueprintLibrary.GetLocalSize(pg) : undefined;
            const pa = pg ? UE.SlateBlueprintLibrary.GetAbsoluteSize(pg) : undefined;
            const buffSize = Math.max(.5, Math.min(2, Number(settings?.BuffSize ?? 100) / 100));
            const sx = (pl && pa && pl.X > 0 ? pa.X / dpi / pl.X : 1) * g.zoom * buffSize, sy = (pl && pa && pl.Y > 0 ? pa.Y / dpi / pl.Y : 1) * g.zoom * buffSize;
            const iconSize = Math.max(width * sx, height * sy), position = (0, layout_1.buffPosition)(index, g, iconSize);
            if (settings?.MirrorX) position.x = 2 * g.cx - position.x;
            entry.slot.SetPosition((0, native_1.v2)(position.x - width * sx / 2, position.y - height * sy / 2));
            entry.slot.SetSize((0, native_1.v2)(width, height));
            entry.holder.SetRenderTransformPivot((0, native_1.v2)(0, 0));
            entry.holder.SetRenderScale((0, native_1.v2)(sx, sy));
            entry.childSlot.SetPosition((0, native_1.v2)(0, 0));
            entry.childSlot.SetSize((0, native_1.v2)(width, height));
            // The shared playerhud fade is already applied once to the whole group.
            const parentOpacity = (0, ui_state_1.sourceOpacity)(parent, hud.playerhud ?? hud);
            entry.holder.SetRenderOpacity(parentOpacity);
        }
    }
    hide() { if ((0, native_1.valid)(this.root))
        this.root.SetRenderOpacity(0); }
    stop() { this.clearEntries(); if ((0, native_1.valid)(this.root))
        this.system.RemoveWidget(this.root); this.sourceHud = undefined; this.sourceContainers = []; }
}
exports.BuffMirror = BuffMirror;

},
"./settings": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.Settings = exports.DEFAULTS = void 0;
exports.checked = checked;
exports.parseSettings = parseSettings;
const UE = require("ue");
const puerts_1 = require("puerts");
const native_1 = require("./native");
// Replaced with false only when bundling the existing single-bar edition.
const HAS_HEALTH = false;
exports.DEFAULTS = Object.freeze({ X: 60, Y: 50, Scale: 100, Buffs: true,
    MirrorX: false, MirrorY: false, HealthOpacity: 100, EnergyOpacity: 100,
    BuffSize: 100, BuffOpacity: 100, HideNativeHealth: false, HideNativeEnergy: false, HideNativeBuffs: false });
const host = globalThis;
const text = (en, zh) => ({ en, 'zh-Hans': zh });
function numberRow(key, en, zh, min, max, helpEn, helpZh) {
    return { key, type: 'number', slider: true, label: text(en, zh), min, max, step: 5, default: exports.DEFAULTS[key], help: text(helpEn, helpZh) };
}
function checked(key, value) {
    const s = String(value ?? '').trim();
    if (key === 'Buffs' || key === 'MirrorX' || key === 'MirrorY' || key === 'HideNativeHealth' || key === 'HideNativeEnergy' || key === 'HideNativeBuffs')
        return /^(on|true|1|yes)$/i.test(s) ? true : /^(off|false|0|no)$/i.test(s) ? false : exports.DEFAULTS[key];
    const n = Number(s);
    if (s === '' || !Number.isFinite(n))
        return exports.DEFAULTS[key];
    const min = key === 'Scale' || key === 'BuffSize' ? 50 : 0;
    const max = key === 'Scale' || key === 'BuffSize' ? 200 : 100;
    // Preserve the original position and scale handling. New numeric rows use
    // the same five-point grid as the 0.6.2 custom size/opacity controls.
    const snapped = ['X', 'Y', 'Scale'].includes(key) ? n : Math.round(n / 5) * 5;
    return Math.max(min, Math.min(max, snapped));
}
function parseSettings(source) {
    const result = { ...exports.DEFAULTS }, seen = new Set();
    for (const line of source.replace(/^\uFEFF/, '').split(/\r?\n/)) {
        const m = /^\s*([A-Za-z0-9_]+)\s*=\s*(.*?)\s*$/.exec(line.replace(/[;#].*$/, ''));
        if (m && Object.prototype.hasOwnProperty.call(exports.DEFAULTS, m[1]) && !seen.has(m[1])) {
            const key = m[1];
            seen.add(key);
            Object.assign(result, { [key]: checked(key, m[2]) });
        }
    }
    return result;
}
// Optional integration: never read stale preferences when the menu is absent.
// No extra timers, no hard require of the menu, no writes to shared config.
class Settings {
    constructor() {
        this.values = { ...exports.DEFAULTS };
        this.nextCheck = 0;
        this.stopped = false;
        this.warned = false;
    }
    update(now) {
        if (this.stopped || now < this.nextCheck)
            return;
        this.nextCheck = now + 2000;
        try {
            const menu = host.PBZModsMenu;
            if (!menu || Array.isArray(menu) || typeof menu.push !== 'function' || typeof menu.value !== 'function' || typeof menu.open !== 'function') {
                this.registered = undefined;
                Object.assign(this.values, exports.DEFAULTS);
                return;
            }
            if (menu !== this.registered) {
                menu.push({ id: 'PhantomHUD', title: 'PhantomHUD', version: '0.5.1', file: 'PhantomHUD.txt',
                    description: text('Ink position, horizontal mirroring, bar order and opacity. Close Settings to see the result.', '调整墨痕的位置、左右镜像、上下条顺序和透明度。关闭设置菜单后查看效果。'),
                    settings: [
                        { key: 'X', type: 'number', slider: true, label: text('Horizontal position (%)', '水平位置（%）'), min: 0, max: 100, step: 1, default: exports.DEFAULTS.X,
                            help: text('Ink center, measured from the left edge. Default: 60%.', '以墨痕中心为锚点，从屏幕左边起算。默认 60%。') },
                        { key: 'Y', type: 'number', slider: true, label: text('Vertical position (%)', '垂直位置（%）'), min: 0, max: 100, step: 1, default: exports.DEFAULTS.Y,
                            help: text('Ink center, measured from the top edge. Default: 50%.', '以墨痕中心为锚点，从屏幕上边起算。默认 50%。') },
                        { key: 'Scale', type: 'number', slider: true, label: text('HUD scale (%)', 'HUD 整体缩放（%）'), min: 50, max: 200, step: 5, default: exports.DEFAULTS.Scale,
                            help: text('Scales ink and copied buffs together. At 100%, ink height is ' + (HAS_HEALTH ? '25%' : '15%') + ' of the screen.', '同时缩放墨痕和复制的 Buff。100% 时墨痕高度为屏幕高度的 ' + (HAS_HEALTH ? '25%' : '15%') + '。') },
                        { key: 'Buffs', type: 'toggle', label: text('Show buffs', '显示 Buff'), default: exports.DEFAULTS.Buffs,
                            help: text('Controls only the copied buffs beside the ink. Original buffs stay unchanged.', '只控制墨痕旁的 Buff 副本，原版 Buff 显示保持不变。') },
                        { key: 'HideNativeHealth', type: 'toggle', label: text('Hide original health bar', '隐藏原版生命条'), default: false,
                            help: text('Hides only the original health bar and its background. Medicines, quick slots and buffs stay unchanged.', '仅隐藏原版生命条及其背景，不隐藏药品、快捷栏或 Buff。') },
                        { key: 'HideNativeEnergy', type: 'toggle', label: text('Hide original killing intent bar', '隐藏原版杀气条'), default: false,
                            help: text('Hides only the original killing-intent bar, background and effects. Both switches off restores the bars.', '仅隐藏原版杀气条、背景及其特效。关闭开关即可恢复对应原条。') },
                        { key: 'HideNativeBuffs', type: 'toggle', label: text('Hide original buff list', '隐藏原版 Buff 列表'), default: false,
                            help: text('Moves only the original buff/debuff list off screen, without scaling. Copied buffs keep their size and remain controlled by Show buffs.', '只将原版增益/减益列表移出屏幕，不缩放。墨痕旁的 Buff 副本保持大小，仍由「显示 Buff」控制。') },
                        { key: 'MirrorX', type: 'toggle', label: text('Mirror HUD horizontally', '水平镜像 HUD'), default: false,
                            help: text('Mirrors ink around its own X anchor. Buffs move left, with rows top to bottom and columns right to left. Icons and screen position do not flip.', '以墨痕自身的 X 锚点左右翻转。Buff 列表移到左侧，列内从上到下、列从右到左；图标方向和 HUD 屏幕位置不变。') },
                        ...(HAS_HEALTH ? [{ key: 'MirrorY', type: 'toggle', label: text('Swap health / killing intent positions', '交换生命条与杀气条上下位置'), default: false,
                                help: text('Moves health below killing intent. Both bars still drain from top to bottom; guard-break glow follows killing intent.', '开启后生命在下、杀气在上。两条都从上向下扣减，破防红光随杀气条移动。') }] : []),
                        ...(HAS_HEALTH ? [
                            numberRow('HealthOpacity', 'Health opacity (%)', '血条不透明度（%）', 0, 100, 'Fades the fill and its backdrop together, including the trailing layer.', '同时调整内条、滞后层及对应底图。'),
                        ] : []),
                        numberRow('EnergyOpacity', 'Killing intent opacity (%)', '杀气条不透明度（%）', 0, 100, 'Fades fill, trailing layer, guard-break glow and backdrop together.', '同时调整内条、滞后层、破防红光及对应底图。'),
                        numberRow('BuffSize', 'Buff icon size (%)', 'Buff 图标大小（%）', 50, 200, 'Scales copied buff icons and their spacing.', '缩放 Buff 副本图标及其间距。'),
                        numberRow('BuffOpacity', 'Buff opacity (%)', 'Buff 不透明度（%）', 0, 100, 'Only affects copied buffs and follows the original HUD fade.', '只调整 Buff 副本，并叠加原 HUD 的显隐。'),
                    ],
                    // Mods Menu supplies Restore defaults and persists the visible rows.
                    onChange: (key, value) => {
                        if (!this.stopped && host.PBZModsMenu === menu && Object.prototype.hasOwnProperty.call(exports.DEFAULTS, key))
                            Object.assign(this.values, { [key]: checked(key, value) });
                    },
                });
                this.registered = menu;
                (0, native_1.log)('Mods Menu settings registered');
            }
            const dir = UE.KismetSystemLibrary.GetProjectContentDirectory();
            const path = UE.KismetSystemLibrary.ConvertToAbsolutePath(dir.replace(/[\\/]?$/, '/') + 'Paks/~mods/PhantomHUD.txt');
            if (!UE.BlueprintPathsLibrary.FileExists(path)) {
                Object.assign(this.values, exports.DEFAULTS);
                return;
            }
            const out = (0, puerts_1.$ref)('');
            // Preserve current values if another writer has the file locked mid-save.
            if (UE.EasyCsv.LoadStringFromLocalFile(path, out))
                Object.assign(this.values, parseSettings(String((0, puerts_1.$unref)(out))));
        }
        catch (e) {
            if (!this.warned) {
                this.warned = true;
                (0, native_1.log)('optional settings unavailable; HUD continues: ' + String(e));
            }
        }
    }
    stop() { this.stopped = true; }
}
exports.Settings = Settings;

},
"./native-bars": function(exports, require) {
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.NativeBars = void 0;
const native_1 = require("./native");
const ui_state_1 = require("./ui-state");
const HIDDEN_SCALE = .001, OFFSCREEN = 100000;
// The reflected WB_PlayerHPBar(_V1) properties distinguish the animated bars,
// their decorative images and sha-chi FX. Never hide their owner, root panel,
// generic Overlays, or siblings such as consumables/quick slots. The separate
// buff-list option translates W_BuffBar only and never scales source geometry.
const HEALTH_KEYS = ['AnimHPBar_1', 'Image_HpBG'];
const ENERGY_KEYS = ['Image_ShaChiBarBG', 'Image_ShaChiBarRedGlow',
    'NS_UI_ShaChiBar_Full_001', 'NS_UI_ShaChiBar_Full_002', 'NS_UI_ShaChiBar_Break_001'];
const copy = (v) => ({ X: v.X, Y: v.Y });
const same = (v, x, y = x) => Math.abs(v.X - x) < 1e-6 && Math.abs(v.Y - y) < 1e-6;
function channels(w) {
    const t = w.RenderTransform, scale = copy(t.Scale), translation = copy(t.Translation);
    if (![scale.X, scale.Y, translation.X, translation.Y].every(Number.isFinite))
        throw new Error('Invalid native widget transform');
    return { scale, translation };
}
class NativeBars {
    constructor() {
        this.saved = new Map();
        this.nextFind = 0;
        this.warned = false;
    }
    report(e) {
        if (!this.warned) {
            this.warned = true;
            (0, native_1.log)('optional native-bar hiding unavailable; ink HUD continues: ' + String(e));
        }
    }
    restore(w, s) {
        if (!(0, native_1.valid)(w))
            return;
        const current = channels(w);
        // Restore only channels still owned by us. Keep later game-side changes,
        // and never replace the complete transform (which includes rotation/shear).
        if (s.scaled && same(current.scale, HIDDEN_SCALE))
            w.SetRenderScale((0, native_1.v2)(s.scale.X, s.scale.Y));
        if (s.translated && same(current.translation, OFFSCREEN))
            w.SetRenderTranslation((0, native_1.v2)(s.translation.X, s.translation.Y));
    }
    reset() {
        for (const [w, s] of this.saved)
            try {
                this.restore(w, s);
            }
            catch (e) {
                this.report(e);
            }
        this.saved.clear();
        this.bar = undefined;
        this.owner = undefined;
        this.nextFind = 0;
    }
    findOwner(bar, now) {
        if (now < this.nextFind) {
            if (!this.owner)
                return;
            if ((0, native_1.valid)(this.owner) && this.owner.AnimBreakmeterBar === bar)
                return this.owner;
        }
        this.nextFind = now + 1000;
        this.owner = undefined;
        const seen = new Set();
        for (let w = (0, ui_state_1.visualParent)(bar), n = 0; w && n < 40 && !seen.has(w); w = (0, ui_state_1.visualParent)(w), n++) {
            seen.add(w);
            const candidate = w;
            if (candidate.AnimBreakmeterBar === bar) {
                this.owner = candidate;
                break;
            }
        }
        return this.owner;
    }
    hide(w, translationOnly = false) {
        const current = channels(w);
        let saved = this.saved.get(w);
        if (!saved) {
            saved = { ...current, scaled: false, translated: false };
            this.saved.set(w, saved);
        }
        // A native animation may replace a channel. Save its newer value before
        // reapplying our hiding transform, without any Set* on stable frames.
        if (!translationOnly && !same(current.scale, HIDDEN_SCALE)) {
            saved.scale = current.scale;
            w.SetRenderScale((0, native_1.v2)(HIDDEN_SCALE, HIDDEN_SCALE));
            saved.scaled = true;
        }
        if (!same(current.translation, OFFSCREEN)) {
            saved.translation = current.translation;
            w.SetRenderTranslation((0, native_1.v2)(OFFSCREEN, OFFSCREEN));
            saved.translated = true;
        }
    }
    update(bar, values, now, hud) {
        if (!values.HideNativeHealth && !values.HideNativeEnergy && !values.HideNativeBuffs) {
            if (this.saved.size)
                this.reset();
            return;
        }
        if (!bar || !(0, native_1.valid)(bar)) {
            this.reset();
            return;
        }
        try {
            if (bar !== this.bar) {
                this.reset();
                this.bar = bar;
            }
            const owner = this.findOwner(bar, now), desired = new Map();
            const add = (w) => {
                if (w && (0, native_1.valid)(w) && w !== owner && w !== owner?.WidgetTree?.RootWidget)
                    desired.set(w, false);
            };
            if (values.HideNativeEnergy) {
                add(bar);
                if (owner)
                    for (const key of ENERGY_KEYS)
                        add(owner[key]);
            }
            if (owner && values.HideNativeHealth)
                for (const key of HEALTH_KEYS)
                    if (owner[key] !== bar)
                        add(owner[key]);
            // The translucent light frame is shared. Hide it with either bar so it
            // cannot remain visible behind a bar the player chose to remove.
            if (owner && (values.HideNativeHealth || values.HideNativeEnergy))
                add(owner.Image_OverallBG);
            if (values.HideNativeBuffs && hud && (0, native_1.valid)(hud)) {
                const buffs = hud.W_BuffBar;
                if (buffs && (0, native_1.valid)(buffs) && buffs !== owner && buffs !== owner?.WidgetTree?.RootWidget &&
                    buffs !== hud && buffs !== bar && buffs !== owner?.AnimHPBar_1 && buffs !== hud.WidgetTree?.RootWidget && !desired.has(buffs))
                    desired.set(buffs, true);
            }
            for (const [w, s] of this.saved)
                if (!desired.has(w)) {
                    try {
                        this.restore(w, s);
                    }
                    catch (e) {
                        this.report(e);
                    }
                    this.saved.delete(w);
                }
            for (const [w, translationOnly] of desired)
                try {
                    this.hide(w, translationOnly);
                }
                catch (e) {
                    this.report(e);
                }
        }
        catch (e) {
            this.report(e);
        }
    }
}
exports.NativeBars = NativeBars;

}
};
  const cache=Object.create(null);
  function localRequire(id) {
    if(id==='ue'||id==='puerts')return externalRequire(id);
    if(!Object.prototype.hasOwnProperty.call(factories,id))throw new Error('Unknown PhantomHUD module '+id);
    if(cache[id])return cache[id];
    const result=cache[id]={};factories[id](result,localRequire);return result;
  }
  Object.assign(entryExports,localRequire('./main'));
})(require,exports);
