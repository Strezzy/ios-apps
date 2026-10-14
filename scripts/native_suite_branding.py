#!/usr/bin/env python3
"""Apply approved native identities. Does not publish or alter existing releases."""
from __future__ import annotations
import argparse, hashlib, json, plistlib, re, struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPS = {
    'Facet': ('DepthCheck', 'depthcheck', 'ba493a16349b4e9515ae1bc9846c17ecd0f4bf6b'),
    'Veil': ('Rinse', 'rinse', 'a1dde20ed7acb7e18803da9425ec67aa5fe7fe58'),
    'Lucid': ('LumaLift', 'lumalift', '0507eb4389f3bba47cbc2e1dda7361bf5e17c769'),
}
TEXT = {'.swift', '.py', '.sh', '.json', '.plist', '.pbxproj', '.yml', '.yaml', '.xcconfig', '.xcscheme'}

def put(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding='utf-8')

def change(path, old, new):
    text = path.read_text()
    if old not in text:
        if new in text: return
        raise ValueError('Expected source not found: '+str(path))
    put(path, text.replace(old, new))

def asset(root, image, imageset='AppIcon.appiconset'):
    directory = root / imageset
    directory.mkdir(parents=True, exist_ok=True)
    filename = 'Suite.png'
    (directory / filename).write_bytes(image)
    entry = {'idiom':'universal', 'filename':filename}
    if imageset.endswith('.appiconset'): entry.update(platform='ios', size='1024x1024')
    put(directory/'Contents.json', json.dumps({'images':[entry], 'info':{'version':1,'author':'xcode'}}, indent=2)+'\n')

VEIL_HERO = r'''    private var hero: some View {
        HStack(alignment: .center, spacing: 16) {
            Image("Brand").resizable().scaledToFit()
                .frame(width: 60, height: 60)
                .clipShape(.rect(cornerRadius: 17)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text("Remove metadata")
                    .font(.system(.title2, design: .rounded, weight: .bold))
                Text("Clean copies. Originals untouched.")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }.padding(.vertical, 6)
    }
    private var importControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Import").font(.headline)
            GlassEffectContainer(spacing: 12) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 12) { importChoices }
                } else {
                    HStack(spacing: 12) { importChoices }
                }
            }
        }.disabled(store.busy || store.importing)
    }
    @ViewBuilder private var importChoices: some View {
        importButton("Photos", icon: "photo.on.rectangle.angled", kind: .photos)
        importButton("Files", icon: "doc", kind: .files)
        importButton("Folder", icon: "folder", kind: .folder)
    }
    private func importButton(_ title: String, icon: String, kind: PickerKind) -> some View {
        Button { picker = kind } label: {
            VStack(spacing: 10) {
                Image(systemName: icon).font(.title2).foregroundStyle(RinseTheme.accent)
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(.primary)
            }.frame(maxWidth: .infinity).padding(.vertical, 22)
        }
        .buttonStyle(.plain)
        .modifier(VeilCard(interactive: true))
        .accessibilityLabel("Import \(title.lowercased())")
        .accessibilityIdentifier("veil.import.\(kind.rawValue)")
    }
    private var emptyState: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 42, weight: .light)).foregroundStyle(RinseTheme.accent)
                .padding(.top, 16).accessibilityHidden(true)
            VStack(spacing: 7) {
                Text("Choose photos or videos").font(.headline)
                Text("Import a single file, a batch, or a folder.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }.multilineTextAlignment(.center)
            Divider().padding(.horizontal, 10)
            VStack(alignment: .leading, spacing: 12) {
                Label("Processed on your device", systemImage: "iphone.gen3")
                Label("Separate, verified clean copies", systemImage: "checkmark.shield")
            }.font(.subheadline).foregroundStyle(.secondary)
            Text("JPEG, PNG, HEIC, MOV and MP4. SDR videos up to 4K / 60 fps. Photos export as SDR. See Privacy for format limits.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity).padding(24)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 28))
            .overlay(RoundedRectangle(cornerRadius: 28).strokeBorder(RinseTheme.glow.opacity(0.18)))
    }
'''
VEIL_CARD = r'''
private struct VeilCard: ViewModifier {
    var interactive = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(RinseTheme.glow.opacity(0.30)))
        } else {
            content.glassEffect(interactive ? .regular.interactive() : .regular, in: .rect(cornerRadius: 24))
        }
    }
}
'''
VEIL_TESTS = '''import XCTest
import UIKit
@testable import Rinse

final class VeilBrandingTests: XCTestCase {
    func testVeilInstalledIdentity() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.billy.veil")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String, "Veil")
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String, "Veil")
        XCTAssertNotNil(UIImage(named: "Brand"))
    }
    func testVeilAccentIsGreenInBothAppearances() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let color = UIColor(RinseTheme.accent).resolvedColor(with: UITraitCollection(userInterfaceStyle: style))
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertGreaterThan(g, b)
            XCTAssertGreaterThan(b, r)
            XCTAssertEqual(a, 1, accuracy: 0.001)
        }
    }
}
'''

def veil_ui(folder):
    view = folder/'App/RinseView.swift'
    text = view.read_text()
    if 'private struct VeilCard' in text: return
    text = text.replace('import SwiftUI', 'import SwiftUI\nimport UIKit', 1)
    text = text.replace('static let accent = Color(red: 0.05, green: 0.76, blue: 0.76)', '''static let glow = Color(red: 32.0/255, green: 184.0/255, blue: 148.0/255)
    static let accent = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.34, green: 0.86, blue: 0.66, alpha: 1)
            : UIColor(red: 0.025, green: 0.46, blue: 0.32, alpha: 1)
    })''')
    text = text.replace('@Environment(\\.colorScheme) private var colorScheme', '@Environment(\\.colorScheme) private var colorScheme\n    @Environment(\\.dynamicTypeSize) private var dynamicTypeSize')
    text = text.replace('RinseTheme.accent.opacity(colorScheme', 'RinseTheme.glow.opacity(colorScheme')
    text = text.replace('Color.blue.opacity(0.07)', 'Color(red: 0.02, green: 0.40, blue: 0.27).opacity(0.07)')
    start, end = text.index('    private var hero:'), text.index('    private var queue:')
    text = text[:start] + VEIL_HERO + text[end:] + VEIL_CARD
    text = text.replace('.padding(16).glassEffect(.regular, in: .rect(cornerRadius: 22))', '.padding(16).modifier(VeilCard())')
    text = text.replace('systemImage: "drop.fill"', 'systemImage: "shield.lefthalf.filled"')
    put(view, text)
    put(folder/'Tests/VeilBrandingTests.swift', VEIL_TESTS)

def apply(name):
    old, suffix, expected_blob = APPS[name]
    folder = ROOT/old
    artwork = (ROOT/'branding/app-icons'/f'{name}.png').read_bytes()
    blob = hashlib.sha1(b'blob '+str(len(artwork)).encode()+b'\0'+artwork).hexdigest()
    if blob != expected_blob: raise ValueError('Approved artwork changed for '+name)
    if artwork[:8] != b'\x89PNG\r\n\x1a\n' or struct.unpack('>II',artwork[16:24]) != (1024,1024) or artwork[25] != 2:
        raise ValueError('Native artwork must be opaque 1024px RGB PNG')
    old_id, new_id = 'com.billy.'+suffix, 'com.billy.'+name.lower()
    for path in folder.rglob('*'):
        if not path.is_file() or path.suffix not in TEXT: continue
        if any(part in ('Build','Vendor','Packages','.git','.build','__pycache__') for part in path.relative_to(folder).parts): continue
        try: text = path.read_text()
        except UnicodeError: continue
        text = text.replace(old_id,new_id)
        if name == 'Facet' and path.suffix == '.py': text=text.replace('"Depth Check"','"Facet"')
        if path.suffix == '.swift' and ('App' in path.parts or 'UI' in path.parts or 'Share' in path.parts):
            display = 'Depth Check' if name == 'Facet' else old
            for a,b in [(f'"{display}"',f'"{name}"'),(f'"{display} ',f'"{name} '),
                        (f'with {display}"',f'with {name}"'),(f'open {display}.',f'open {name}.'),
                        (f'Keep {display} ',f'Keep {name} ')]:
                text=text.replace(a,b)
        if text != path.read_text(): put(path,text)
    if name == 'Facet':
        p=folder/'DepthCheck/Info.plist'; data=plistlib.loads(p.read_bytes())
        data.update(CFBundleDisplayName=name,CFBundleName=name,CFBundleShortVersionString='1.1')
        for key in list(data):
            if key.startswith('NS') and isinstance(data[key],str): data[key]=data[key].replace('Depth Check',name)
        p.write_bytes(plistlib.dumps(data))
        asset(folder/'DepthCheck/Assets.xcassets',artwork)
        change(folder/'scripts/generate_project.py','"MARKETING_VERSION": "1.0"','"MARKETING_VERSION": "1.1"')
    else:
        (folder/'Artwork.png').write_bytes(artwork)
        spec=folder/'project.yml'; text=spec.read_text()
        text=re.sub(r'MARKETING_VERSION: [\'\"]1\.0(?:\.0)?[\'\"]','MARKETING_VERSION: "1.1"',text)
        text=text.replace('CFBundleDisplayName: '+old, 'CFBundleName: '+name+'\n        CFBundleDisplayName: '+name)
        text=text.replace('CFBundleDisplayName: Clean with '+old,'CFBundleName: '+name+'Share\n        CFBundleDisplayName: Clean with '+name)
        put(spec,text)
        if name == 'Veil':
            prepare=folder/'scripts/prepare.py'; text=prepare.read_text()
            begin=text.index('    artwork = ROOT / '); end=text.index('    assets = ROOT / "Assets.xcassets"')
            text=text[:begin]+'''    artwork = ROOT / "Artwork.png"
    data = artwork.read_bytes()
    expected = "a1dde20ed7acb7e18803da9425ec67aa5fe7fe58"
    blob = hashlib.sha1(b"blob " + str(len(data)).encode() + b"\\0" + data).hexdigest()
    if blob != expected:
        raise RuntimeError("Veil artwork failed its approved-source integrity check.")
'''+text[end:]
            text=text.replace('Brand.jpg','Brand.png')
            put(prepare,text)
            change(folder/'scripts/build_ios.py','ROOT / "Artwork.jpg"','ROOT / "Artwork.png"')
            veil_ui(folder)
            share=folder/'Share/ShareViewController.swift'
            if share.exists():
                text=share.read_text().replace('Color(red: 0.05, green: 0.76, blue: 0.76)','Color(red: 0.025, green: 0.46, blue: 0.32)')
                put(share,text)
        else:
            change(folder/'scripts/prepare_assets.py',
                "subprocess.run(['swift', str(ROOT / 'scripts/Icon.swift'), str(icon)], check=True)",
                "shutil.copyfile(ROOT / 'Artwork.png', icon)")
    print('Prepared native '+name+' ('+new_id+')')

def main():
    parser=argparse.ArgumentParser(); parser.add_argument('app',choices=['all',*APPS]); args=parser.parse_args()
    for name in APPS if args.app=='all' else [args.app]: apply(name)

if __name__=='__main__': main()
