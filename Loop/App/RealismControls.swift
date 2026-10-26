import SwiftUI

struct RealismControls: View {
    @Binding var settings: EffectSettings
    var category: EffectCategory
    private var selected: String? {settings.layer(category)?.preset}
    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if category == .face,let id=selected {
                if id == "ageOlder" || id == "ageMature" {
                    Label("Local portrait aging",systemImage:"cpu").font(.subheadline.weight(.semibold))
                    Text("A bundled 512 px neural model changes facial texture, then blends it into the original-resolution frame. Best with a clear, mostly front-facing face. This is an appearance effect, not a prediction of your future face. Preview can be slower.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if id != "faceBlur" && id != "facePixel" {
                    DisclosureGroup("Fine-tune face & skin") {
                        VStack(spacing:12) {
                            faceSlider("Face width · fuller / slimmer",\.width)
                            faceSlider("Jaw · softer / narrower",\.jaw)
                            faceSlider("Chin · shorter / longer",\.chin)
                            faceSlider("Eyes · smaller / larger",\.eyes)
                            faceSlider("Nose · wider / narrower",\.nose)
                            faceSlider("Lips · finer / fuller",\.lips)
                            faceSlider("Skin smoothing",\.skin,range:0...1)
                            faceSlider("Texture detail",\.detail)
                            faceSlider("Skin warmth",\.warmth)
                            Button("Restore preset values") {settings.faceTuning=nil}.font(.caption)
                        }.padding(.top,10)
                    }.font(.subheadline)
                }
                if id == "youthRetouch" {Text("Youthful retouch softens existing texture and subtly adjusts proportions; it is not a trained age-regression model.").font(.caption).foregroundStyle(.secondary)}
                if id == "faceBlur" || id == "facePixel" {Text("Automatic face detection may miss turned or hidden faces. Use and review the existing privacy overlays when reliable redaction is required.").font(.caption).foregroundStyle(.secondary)}
            }
            if category == .body,selected != nil {
                DisclosureGroup("Fine-tune body proportions") {
                    VStack(spacing:12) {
                        bodySlider("Waist · fuller / narrower",\.waist)
                        bodySlider("Shoulders · narrower / broader",\.shoulders)
                        bodySlider("Hips · narrower / fuller",\.hips)
                        bodySlider("Legs · shorter / longer",\.legs)
                        bodySlider("Torso · shorter / longer",\.torso)
                        bodySlider("Upper arms · fuller / narrower",\.arms)
                        Button("Restore preset values"){settings.bodyTuning=nil}.font(.caption)
                    }.padding(.top,10)
                }.font(.subheadline)
                Text("Uses visible shoulder, hip and limb positions. Occluded joints are not invented. Strong shaping can bend nearby scenery; moderate values look more natural.").font(.caption).foregroundStyle(.secondary)
            }
            if [.body,.background,.atmosphere].contains(category) {
                DisclosureGroup("Subject & edge quality") {
                    VStack(spacing:12) {
                        Picker("Subject",selection:matte(\.subject)) {
                            Text("People").tag("people");Text("All foreground objects").tag("foreground")
                        }.pickerStyle(.menu)
                        if (settings.matteTuning ?? MatteTuning()).subject == "people" {
                            Picker("Cutout engine",selection:matte(\.quality)) {
                                Text("Studio · MODNet").tag("studio");Text("Native · Vision").tag("native")
                            }.pickerStyle(.menu)
                        }
                        tuneSlider("Temporal stability",matte(\.stability),range:0...1)
                        tuneSlider("Edge · contract / expand",matte(\.edge),range:-1...1)
                        tuneSlider("Soft edge",matte(\.feather),range:0...1)
                        Toggle("Inspect subject mask",isOn:matte(\.showMask)).font(.subheadline)
                        Text("The mask view is for preview only and is never exported. Stability resets when you seek or reverse direction. Both engines run offline; hair and fast motion can still need edge adjustments.").font(.caption).foregroundStyle(.secondary)
                    }.padding(.top,10)
                }.font(.subheadline)
            }
            if category == .atmosphere,selected != nil {
                Picker("Placement",selection:weather(\.placement)) {
                    Text("Layered").tag("layered");Text("Behind").tag("behind");Text("In front").tag("front")
                }.pickerStyle(.segmented)
                tuneSlider("Density",weather(\.density),range:0.05...1)
                tuneSlider("Motion speed",weather(\.speed),range:0.1...3)
                tuneSlider("Wind direction",weather(\.wind),range:-1...1)
                tuneSlider("Particle size",weather(\.size),range:0.1...1)
                Text("Layered places two particle fields behind the detected subject, with a lighter near-camera layer in front. This is subject occlusion, not a reconstructed 3D scene.").font(.caption).foregroundStyle(.secondary)
            }
            if category == .background,selected != nil {
                DisclosureGroup("Match the background") {
                    VStack(spacing:12) {
                        tuneSlider("Background blur",backdrop(\.blur),range:0...1)
                        tuneSlider("Background exposure",backdrop(\.exposure),range:-2...2)
                        tuneSlider("Background warmth",backdrop(\.warmth),range:-1...1)
                        if selected?.hasPrefix("ph_") == true || selected == "customBackground" {
                            tuneSlider("Background zoom",backdrop(\.zoom),range:1...2.5)
                            tuneSlider("Horizontal framing",backdrop(\.horizontal),range:0...1)
                            tuneSlider("Vertical framing",backdrop(\.vertical),range:0...1)
                        }
                    }.padding(.top,10)
                }.font(.subheadline)
                if selected?.hasPrefix("ph_") == true {Text("Photographic environment · Powered by Poly Haven · CC0").font(.caption2).foregroundStyle(.secondary)}
            }
        }
    }
    private func faceSlider(_ title:String,_ path:WritableKeyPath<FaceTuning,Double>,range:ClosedRange<Double> = -1...1)->some View {
        let value=Binding<Double>(get:{(settings.faceTuning ?? FaceTuning.recipe(selected ?? ""))[keyPath:path]},set:{newValue in
            var v=settings.faceTuning ?? FaceTuning.recipe(selected ?? "");v[keyPath:path]=newValue;settings.faceTuning=v
        })
        return tuneSlider(title,value,range:range)
    }
    private func bodySlider(_ title:String,_ path:WritableKeyPath<BodyTuning,Double>)->some View {
        let value=Binding<Double>(get:{(settings.bodyTuning ?? BodyTuning.recipe(selected ?? ""))[keyPath:path]},set:{newValue in
            var v=settings.bodyTuning ?? BodyTuning.recipe(selected ?? "");v[keyPath:path]=newValue;settings.bodyTuning=v
        })
        return tuneSlider(title,value,range:-1...1)
    }
    private func matte<T>(_ path:WritableKeyPath<MatteTuning,T>)->Binding<T> {
        Binding(get:{(settings.matteTuning ?? MatteTuning())[keyPath:path]},set:{x in var v=settings.matteTuning ?? MatteTuning();v[keyPath:path]=x;settings.matteTuning=v})
    }
    private func weather<T>(_ path:WritableKeyPath<AtmosphereTuning,T>)->Binding<T> {
        Binding(get:{(settings.atmosphereTuning ?? AtmosphereTuning())[keyPath:path]},set:{x in var v=settings.atmosphereTuning ?? AtmosphereTuning();v[keyPath:path]=x;settings.atmosphereTuning=v})
    }
    private func backdrop<T>(_ path:WritableKeyPath<BackdropTuning,T>)->Binding<T> {
        Binding(get:{(settings.backdropTuning ?? BackdropTuning())[keyPath:path]},set:{x in var v=settings.backdropTuning ?? BackdropTuning();v[keyPath:path]=x;settings.backdropTuning=v})
    }
    private func tuneSlider(_ title:String,_ binding:Binding<Double>,range:ClosedRange<Double>)->some View {
        ValueSlider(title:title,value:binding,range:range,display:String(format:"%+.2f",binding.wrappedValue))
    }
}
