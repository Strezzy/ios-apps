import Foundation
import CoreImage
import ImageIO
import UniformTypeIdentifiers
@preconcurrency import AVFoundation

/// Project-owned auxiliary files. No URLs or scripts are accepted from look presets.
enum CreativeAssets {
    private static let lock=NSRecursiveLock()
    private static var sources:[UUID:URL]=[:]
    private static var generators:[UUID:AVAssetImageGenerator]=[:]
    private static var pictures:[String:CIImage]=[:]
    static var root:URL {FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Loop/CreativeAssets",isDirectory:true)}
    static func register(_ project:LoopProject,url:URL){lock.lock();sources[project.id]=url;lock.unlock()}
    static func save(_ image:CGImage,projectID:UUID)throws->String {
        let directory=root.appendingPathComponent(projectID.uuidString,isDirectory:true)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let name=projectID.uuidString+"/"+UUID().uuidString+".png",url=root.appendingPathComponent(name)
        guard let writer=CGImageDestinationCreateWithURL(url as CFURL,UTType.png.identifier as CFString,1,nil) else{throw LoopError.encoding("The reference frame could not be saved.")}
        CGImageDestinationAddImage(writer,image,nil)
        guard CGImageDestinationFinalize(writer) else{throw LoopError.encoding("The reference frame could not be saved.")}
        var values=URLResourceValues();values.isExcludedFromBackup=true;var u=url;try? u.setResourceValues(values)
        return name
    }
    static func image(_ name:String)throws->CIImage {
        lock.lock();defer{lock.unlock()}
        let pieces=name.split(separator:"/")
        guard pieces.count==2,UUID(uuidString:String(pieces[0])) != nil,
              UUID(uuidString:String(pieces[1]).replacingOccurrences(of:".png",with:"")) != nil else{throw LoopError.invalidSettings("The reference frame path is invalid.")}
        if let image=pictures[name]{return image}
        guard let image=CIImage(contentsOf:root.appendingPathComponent(name)) else{throw LoopError.invalidSettings("The saved still frame is missing. Choose a new still frame in Motion.")}
        if pictures.count>=3{pictures.removeAll()};pictures[name]=image;return image
    }
    static func source(project:LoopProject,time:Double,edge:Int,highRange:Bool=false)throws->CGImage {
        lock.lock();defer{lock.unlock()}
        guard let url=sources[project.id] else{throw LoopError.encoding("Reopen this project before using motion effects.")}
        let generator:AVAssetImageGenerator
        if let existing=generators[project.id]{generator=existing}
        else {if generators.count>=2{generators.removeAll()};generator=MediaEngine.makeGenerator(url:url,maximumDimension:edge);generators[project.id]=generator}
        generator.maximumSize=CGSize(width:edge,height:edge)
        generator.dynamicRangePolicy=highRange ? .matchSource:.forceSDR
        let t=max(0,min(project.metadata.duration-1/60000,time))
        return try generator.copyCGImage(at:CMTime(seconds:t,preferredTimescale:60000),actualTime:nil)
    }
    static func remove(_ id:UUID){lock.lock();defer{lock.unlock()};sources[id]=nil;generators[id]=nil;pictures.removeAll();try? FileManager.default.removeItem(at:root.appendingPathComponent(id.uuidString))}
    static func clear(){lock.lock();defer{lock.unlock()};generators.removeAll();pictures.removeAll()}
}

enum LookStorage {
    private static var url:URL{CreativeAssets.root.appendingPathComponent("SavedLooks.json")}
    static func load()->[SavedLook]{guard let data=try? Data(contentsOf:url) else{return []};return (try? JSONDecoder().decode([SavedLook].self,from:data)) ?? []}
    static func save(_ values:[SavedLook])throws {
        try FileManager.default.createDirectory(at:CreativeAssets.root,withIntermediateDirectories:true)
        try JSONEncoder().encode(Array(values.prefix(100))).write(to:url,options:.atomic)
    }
    static func portable(_ source:EffectSettings)->EffectSettings {
        var value=source;value.scene?.subjects=[];value.scene?.selectedID=nil;value.scene?.cameraKeys=nil
        value.tracks=value.tracks?.map{track in var t=track;t.subjectID=nil;t.target="all";t.keys=[];t.start=nil;t.end=nil;t.fadeIn=0;t.fadeOut=0;return t}
        return value
    }
}

enum CubeParser {
    static func parse(_ data:Data,name:String)throws->CubeLUT {
        guard data.count<=20_000_000,let text=String(data:data,encoding:.utf8) else{throw LoopError.invalidSettings("Choose a UTF-8 .cube file smaller than 20 MB.")}
        var size=0,low=[0.0,0,0],high=[1.0,1,1],samples=[Float]()
        for raw in text.split(whereSeparator:\.isNewline) {
            let line=raw.split(separator:"#",maxSplits:1,omittingEmptySubsequences:false)[0].trimmingCharacters(in:.whitespaces)
            guard !line.isEmpty else{continue}
            let parts=line.split(whereSeparator:\.isWhitespace)
            guard let token=parts.first else{continue}
            if token=="TITLE"{continue}
            if token=="LUT_1D_SIZE"{throw LoopError.invalidSettings("This is a 1D LUT. Loop accepts 3D .cube LUTs.")}
            if token=="LUT_3D_SIZE" {
                guard parts.count==2,let n=Int(parts[1]),(2...65).contains(n),size==0 else{throw LoopError.invalidSettings("Use a 3D LUT with 2 to 65 samples per edge.")}
                size=n;samples.reserveCapacity(n*n*n*4);continue
            }
            if token=="DOMAIN_MIN" || token=="DOMAIN_MAX" {
                let values=parts.dropFirst().compactMap{Double($0)}
                guard values.count==3,values.allSatisfy(\.isFinite) else{throw LoopError.invalidSettings("The LUT color range is invalid.")}
                if token=="DOMAIN_MIN"{low=values}else{high=values};continue
            }
            let values=parts.compactMap{Float($0)}
            guard size>0,values.count==3,values.allSatisfy(\.isFinite),samples.count<size*size*size*4 else{throw LoopError.invalidSettings("The .cube file contains unsupported or invalid data.")}
            samples += values;samples.append(1)
        }
        guard size>=2,samples.count==size*size*size*4,zip(low,high).allSatisfy({$0<$1}) else{throw LoopError.invalidSettings("The LUT is incomplete or has an invalid color range.")}
        let bytes=samples.withUnsafeBytes{Data($0)}
        return CubeLUT(name:String(name.prefix(80)),dimension:size,domainMin:low,domainMax:high,data:bytes)
    }
    static func apply(_ lut:CubeLUT,to image:CIImage)throws->CIImage {
        guard (2...65).contains(lut.dimension),lut.data.count==lut.dimension*lut.dimension*lut.dimension*16,lut.domainMin.count==3,lut.domainMax.count==3 else{throw LoopError.invalidSettings("Reimport this LUT; its saved data is invalid.")}
        let prepared=try RealismKernels.color("loopLUTDomain",extent:image.extent,arguments:[image,CIVector(values:lut.domainMin.map(CGFloat.init),count:3),CIVector(values:lut.domainMax.map(CGFloat.init),count:3)])
        let colored=prepared.applyingFilter("CIColorCubeWithColorSpace",parameters:["inputCubeDimension":lut.dimension,"inputCubeData":lut.data,"inputColorSpace":CGColorSpace(name:CGColorSpace.sRGB)!])
        return OfflineEffectsRenderer.blend(image,colored,amount:min(1,max(0,lut.amount))).cropped(to:image.extent)
    }
}
