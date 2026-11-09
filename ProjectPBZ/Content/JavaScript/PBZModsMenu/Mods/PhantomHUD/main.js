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
const BAR_PATH = '/Game/PBZContent/UI/Hud/PBZAnimProgressBar2.PBZAnimProgressBar2_C';
let timer;
let renderer, buffs;
let bar, hud;
let nextSearch = 0, lastTime = Date.now(), nextRefresh = 0, retryAt = 0, lastError = -Infinity;
let lastPawn, lastWorld;
let warnedHudLookup = false;
const fade = new fade_1.Fade();
const settings = new settings_1.Settings();
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
function hide() { try {
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
(0, native_1.log)('0.3.0 starting; optional Mods Menu settings; game-owned current HUD binding');
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
const UE = require("ue");
const native_1 = require("./native");
const layout_1 = require("./layout");
class InkRenderer {
    constructor(context) {
        this.layers = [];
        this.textures = [];
        this.width = -1;
        this.height = -1;
        this.root = (0, native_1.create)(UE.CanvasPanel, context);
        this.system = (0, native_1.viewport)();
        this.root.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
        try {
            const dir = UE.BlueprintPathsLibrary.ProjectDir() + 'Content/JavaScript/PBZModsMenu/Mods/PhantomHUD/assets/';
            for (const filename of ['ink-base.png', 'ink-fill.png']) {
                const texture = UE.KismetRenderingLibrary.ImportFileAsTexture2D(context, dir + filename);
                if (!texture)
                    throw new Error('Cannot import ' + filename);
                this.textures.push(texture);
            }
            this.base = (0, native_1.create)(UE.Image);
            this.base.SetBrushFromTexture(this.textures[0], false);
            this.base.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
            const bs = this.root.AddChildToCanvas(this.base);
            if (!bs)
                throw new Error('Base slot unavailable');
            this.baseSlot = bs;
            for (let i = 0; i < 4; i++) {
                const clip = (0, native_1.create)(UE.CanvasPanel), image = (0, native_1.create)(UE.Image);
                clip.SetClipping(UE.EWidgetClipping.ClipToBoundsAlways);
                clip.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
                image.SetVisibility(UE.ESlateVisibility.HitTestInvisible);
                image.SetBrushFromTexture(this.textures[1], false);
                const clipSlot = this.root.AddChildToCanvas(clip), imageSlot = clip.AddChildToCanvas(image);
                if (!clipSlot || !imageSlot)
                    throw new Error('Layer slot unavailable');
                clipSlot.SetZOrder(i + 1);
                this.layers.push({ clip, image, clipSlot, imageSlot });
            }
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
            (0, native_1.log)('viewport canvas created; texture import succeeded');
        }
        catch (e) {
            this.system.RemoveWidget(this.root);
            throw e;
        }
    }
    isAttached() { return (0, native_1.valid)(this.root) && this.system.IsWidgetAdded(this.root); }
    update(context, bands, opacity, settings) {
        const size = UE.WidgetLayoutLibrary.GetViewportSize(context);
        const dpi = UE.WidgetLayoutLibrary.GetViewportScale(context);
        if (size.X <= 0 || size.Y <= 0 || dpi <= 0) {
            this.root.SetRenderOpacity(0);
            return;
        }
        const g = (0, layout_1.geometry)(size.X, size.Y, dpi, settings), { vw, vh } = g;
        if (vw !== this.width || vh !== this.height) {
            this.width = vw;
            this.height = vh;
            const slot = this.system.GetWidgetSlot(this.root);
            slot.Offsets.Right = vw;
            slot.Offsets.Bottom = vh;
            this.system.SetWidgetSlot(this.root, slot);
            (0, native_1.log)('viewport ' + JSON.stringify({ width: size.X, height: size.Y, dpi, visibleInkHeight: size.Y * .15 * g.zoom }));
        }
        const { scale, tw, th, tx, ty } = g;
        this.baseSlot.SetPosition((0, native_1.v2)(tx, ty));
        this.baseSlot.SetSize((0, native_1.v2)(tw, th));
        this.root.SetRenderOpacity(Math.max(0, Math.min(1, opacity)));
        for (let i = 0; i < this.layers.length; i++) {
            const layer = this.layers[i], band = bands[i];
            if (!band || band.to <= band.from || band.opacity <= 0) {
                layer.clip.SetRenderOpacity(0);
                continue;
            }
            const from = Math.max(0, Math.min(1, band.from)), to = Math.max(0, Math.min(1, band.to));
            const top = ty + (layout_1.INNER_TOP + layout_1.INNER_HEIGHT * (1 - to)) * scale;
            const bottom = ty + (layout_1.INNER_TOP + layout_1.INNER_HEIGHT * (1 - from)) * scale;
            layer.clip.SetRenderOpacity(band.opacity);
            layer.clipSlot.SetPosition((0, native_1.v2)(tx, top));
            layer.clipSlot.SetSize((0, native_1.v2)(tw, Math.max(0, bottom - top)));
            layer.imageSlot.SetPosition((0, native_1.v2)(0, ty - top));
            layer.imageSlot.SetSize((0, native_1.v2)(tw, th));
            layer.image.SetColorAndOpacity(band.color);
        }
    }
    hide() { if ((0, native_1.valid)(this.root))
        this.root.SetRenderOpacity(0); }
    stop() { if ((0, native_1.valid)(this.root))
        this.system.RemoveWidget(this.root); this.textures = []; this.layers = []; }
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
        this.root.SetRenderOpacity(groupOpacity);
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
            const sx = (pl && pa && pl.X > 0 ? pa.X / dpi / pl.X : 1) * g.zoom, sy = (pl && pa && pl.Y > 0 ? pa.Y / dpi / pl.Y : 1) * g.zoom;
            const iconSize = Math.max(width * sx, height * sy), position = (0, layout_1.buffPosition)(index, g, iconSize);
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
exports.DEFAULTS = Object.freeze({ X: 60, Y: 50, Scale: 100, Buffs: true });
const host = globalThis;
const text = (en, zh) => ({ en, 'zh-Hans': zh });
function checked(key, value) {
    const s = String(value ?? '').trim();
    if (key === 'Buffs')
        return /^(on|true|1)$/i.test(s) ? true : /^(off|false|0)$/i.test(s) ? false : exports.DEFAULTS.Buffs;
    const n = Number(s), min = key === 'Scale' ? 50 : 0, max = key === 'Scale' ? 200 : 100;
    return s !== '' && Number.isFinite(n) ? Math.max(min, Math.min(max, n)) : exports.DEFAULTS[key];
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
                menu.push({ id: 'PhantomHUD', title: 'PhantomHUD', version: '0.3.0', file: 'PhantomHUD.txt',
                    description: text('Ink HUD position, size and buff visibility. Close Settings to see the result.', '调整墨痕 HUD 的位置、大小和 Buff 显示。关闭设置菜单后查看效果。'),
                    settings: [
                        { key: 'X', type: 'number', slider: true, label: text('Horizontal position (%)', '水平位置（%）'), min: 0, max: 100, step: 1, default: exports.DEFAULTS.X,
                            help: text('Ink center, measured from the left edge. Default: 60%.', '以墨痕中心为锚点，从屏幕左边起算。默认 60%。') },
                        { key: 'Y', type: 'number', slider: true, label: text('Vertical position (%)', '垂直位置（%）'), min: 0, max: 100, step: 1, default: exports.DEFAULTS.Y,
                            help: text('Ink center, measured from the top edge. Default: 50%.', '以墨痕中心为锚点，从屏幕上边起算。默认 50%。') },
                        { key: 'Scale', type: 'number', slider: true, label: text('HUD scale (%)', 'HUD 整体缩放（%）'), min: 50, max: 200, step: 5, default: exports.DEFAULTS.Scale,
                            help: text('Scales the ink and copied buffs together. At 100%, ink height is 15% of the screen.', '同时缩放墨痕和复制的 Buff。100% 时墨痕高度为屏幕高度的 15%。') },
                        { key: 'Buffs', type: 'toggle', label: text('Show buffs', '显示 Buff'), default: exports.DEFAULTS.Buffs,
                            help: text('Controls only the copied buffs beside the ink. Original buffs stay unchanged.', '只控制墨痕旁的 Buff 副本，原版 Buff 显示保持不变。') },
                    ],
                    // Mods Menu supplies its own Restore defaults row and persists all four defaults.
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

}};
  const cache=Object.create(null);
  function localRequire(id) {
    if(id==='ue'||id==='puerts')return externalRequire(id);
    if(!Object.prototype.hasOwnProperty.call(factories,id))throw new Error('Unknown PhantomHUD module '+id);
    if(cache[id])return cache[id];
    const result=cache[id]={};factories[id](result,localRequire);return result;
  }
  Object.assign(entryExports,localRequire('./main'));
})(require,exports);
