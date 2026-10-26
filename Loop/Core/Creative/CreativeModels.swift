import Foundation
import CoreGraphics

struct StrengthKey: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var time: Double
    var value: Double
}

/// One card in a non-destructive mix. Times are always source-video seconds.
struct EffectTrack: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var preset: String
    var amount: Double = 1
    var enabled = true
    var target = "all"
    var subjectID: UUID?
    var start: Double?
    var end: Double?
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var keys: [StrengthKey] = []
    func strength(at time: Double) -> Double {
        guard enabled, time.isFinite else { return 0 }
        let first = start ?? 0, last = end ?? Double.greatestFiniteMagnitude
        guard time >= first, time <= last, first <= last else { return 0 }
        var value = amount
        let valid = keys.filter { $0.time.isFinite && $0.value.isFinite }.sorted { $0.time < $1.time }
        if let a = valid.first, let b = valid.last {
            if time <= a.time { value = a.value }
            else if time >= b.time { value = b.value }
            else if let i = valid.firstIndex(where: { $0.time >= time }), i > 0 {
                let a = valid[i-1], b = valid[i]
                let t = (time-a.time)/max(0.000001,b.time-a.time)
                value = a.value+(b.value-a.value)*t
            }
        }
        if fadeIn > 0 { value *= min(1,max(0,(time-first)/fadeIn)) }
        if fadeOut > 0 { value *= min(1,max(0,(last-time)/fadeOut)) }
        return value.isFinite ? min(1,max(0,value)) : 0
    }
    mutating func remember(_ value: Double, at time: Double) {
        guard time.isFinite else { return }
        keys.removeAll { abs($0.time-time)<0.01 }
        keys.append(StrengthKey(time:time,value:min(1,max(0,value))))
        keys.sort { $0.time < $1.time }
    }
}

struct SelectionPoint: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var include: Bool = true
}
struct MaskStroke: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    /// Positions are relative to the tracked subject box, in top-left coordinates.
    var points: [SelectionPoint]
    var width: Double = 0.08
    var include: Bool = true
}
struct SceneSubject: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name: String = "Subject"
    var anchorTime: Double = 0
    var rect: NormalizedRect = .centered
    var points: [SelectionPoint] = []
    var strokes: [MaskStroke] = []
    var path: [TrackingKeyframe] = []
    var needsReview = false
    func box(at time: Double) -> NormalizedRect {
        var item = OverlayItem(kind:.cover,startTime:0,endTime:Double.greatestFiniteMagnitude)
        item.rect=rect;item.keyframes=path
        return item.rect(at:time)
    }
    func covers(_ time: Double) -> Bool {
        if needsReview { return false }
        if path.isEmpty { return abs(time-anchorTime)<0.05 }
        return path.allSatisfy { $0.time.isFinite && $0.confidence >= 0.3 } && time >= path[0].time-0.02 && time <= path[path.count-1].time+0.02
    }
}
struct SceneSettings: Codable, Equatable, Sendable {
    var subjects: [SceneSubject] = []
    var selectedID: UUID?
    var depthEnabled = false
    var flowEnabled = true
    var relight: Double = 0
    var lightWarmth: Double = 0
    var lightDirection: Double = -0.5
    var depthFog: Double = 0
    var focus: Double = 0.65
    var depthBlur: Double = 0
    var matchLighting: Double = 0
    var protectBackground = true
    var preciseSelection = true
    var cameraKeys: [CameraKey]?
}
struct MotionSettings: Codable, Equatable, Sendable {
    /// off, moveSubject, freezeSubject
    var mode = "off"
    var referenceTime: Double = 0
    var referenceAsset: String?
    var subjectID: UUID?
    var seamBlend: Double = 0
    var echoCount: Int = 0
    var echoSpacing: Double = 0.09
    var echoStrength: Double = 0.25
}
struct CubeLUT: Codable, Equatable, Sendable {
    var name: String
    var dimension: Int
    var domainMin: [Double]
    var domainMax: [Double]
    var data: Data
    var amount: Double = 1
}
struct SavedLook: Codable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var effects: EffectSettings
}

extension EffectSettings {
    var hasWork: Bool { !bypass && (!activeLayers.isEmpty || !(tracks ?? []).isEmpty || lut != nil || scene?.depthEnabled == true) }
    var visibleTracks: [EffectTrack] {
        let legacy = activeLayers.map { EffectTrack(preset:$0.preset,amount:$0.amount,enabled:$0.enabled) }
        return legacy + (tracks ?? [])
    }
    mutating func add(_ preset: String, target: String = "all", subjectID: UUID? = nil) {
        guard EffectLibrary.preset(preset) != nil, (tracks?.count ?? 0)<12 else { return }
        if tracks == nil { tracks=[] }
        tracks?.append(EffectTrack(preset:preset,target:target,subjectID:subjectID))
        bypass=false
    }
    mutating func moveLegacyToMix() {
        var mix=tracks ?? []
        mix.insert(contentsOf:activeLayers.map{EffectTrack(preset:$0.preset,amount:$0.amount,enabled:$0.enabled)},at:0)
        tracks=Array(mix.prefix(12));layers=[]
    }
}

enum CinematicWorld: String, CaseIterable, Identifiable {
    case neonRain, forestMorning, goldenPortrait, winter, moonlit, cleanStudio
    var id:String {rawValue}
    var title:String {
        switch self {case .neonRain:return "Neon Rain";case .forestMorning:return "Forest Morning";case .goldenPortrait:return "Golden Portrait";case .winter:return "Winter";case .moonlit:return "Moonlit";case .cleanStudio:return "Clean Studio"}
    }
    var symbol:String {
        switch self {case .neonRain:return "cloud.rain";case .forestMorning:return "leaf";case .goldenPortrait:return "sun.max";case .winter:return "snowflake";case .moonlit:return "moon.stars";case .cleanStudio:return "camera.aperture"}
    }
    func apply(to old:EffectSettings)->EffectSettings {
        var value=old;value.layers=[];value.tracks=[];value.bypass=false;value.faceTuning=nil;value.bodyTuning=nil;value.lut=nil;value.backdropTuning=nil
        var scene=old.scene ?? SceneSettings();scene.depthEnabled=true;scene.depthFog=0;scene.depthBlur=0;scene.focus=0.65;scene.lightDirection = -0.5;scene.relight=0.15;scene.matchLighting=0.3
        var weather=AtmosphereTuning();weather.placement="layered"
        switch self {
        case .neonRain:
            value.add("ph_modern_buildings_2");value.add("rain");value.add("neonNight");scene.lightWarmth = -0.7;scene.depthFog=0.2
        case .forestMorning:
            value.add("ph_forest_slope");value.add("fog");value.add("goldenHour");scene.lightWarmth=0.25;scene.depthFog=0.12;weather.density=0.3
        case .goldenPortrait:
            value.add("skinSilk");value.add("goldenHour");scene.depthBlur=0.35;scene.lightWarmth=0.4
        case .winter:
            value.add("snow");value.add("arctic");scene.lightWarmth = -0.4;scene.depthFog=0.2
        case .moonlit:
            value.add("ph_moonless_golf");value.add("fireflies");value.add("moonlight");scene.lightWarmth = -0.5;weather.density=0.35
        case .cleanStudio:
            value.add("ph_studio_small_03");value.add("portraitEditorial");scene.lightWarmth=0;scene.relight=0.1
        }
        value.scene=scene;value.atmosphereTuning=weather
        return value
    }
}

struct CameraKey:Codable,Equatable,Sendable {
    var time:Double
    var x:Double
    var y:Double
    static func offset(_ keys:[CameraKey],at time:Double)->CGPoint {
        guard let first=keys.first,let last=keys.last else{return .zero}
        if time<=first.time{return CGPoint(x:first.x,y:first.y)}
        if time>=last.time{return CGPoint(x:last.x,y:last.y)}
        var lo=0,hi=keys.count-1
        while lo+1<hi{let mid=(lo+hi)/2;if keys[mid].time<=time{lo=mid}else{hi=mid}}
        let f=(time-keys[lo].time)/max(0.000001,keys[hi].time-keys[lo].time)
        return CGPoint(x:keys[lo].x+(keys[hi].x-keys[lo].x)*f,y:keys[lo].y+(keys[hi].y-keys[lo].y)*f)
    }
}
