#!/usr/bin/env python3
"""Apply bounded renderer backpressure, retaining every source pixel and frame."""
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'DepthCheck/DepthCheck/Imaging/StereoRenderer.swift'
text=p.read_text()
old='''        let result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault, pools[key]!,
            [kCVPixelBufferPoolAllocationThresholdKey as String: 10] as CFDictionary, &value)
        guard result == kCVReturnSuccess, let value else {'''
new='''        let allocation = [kCVPixelBufferPoolAllocationThresholdKey as String: 10] as CFDictionary
        var result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
            pools[key]!, allocation, &value)
        // Writer readiness does not imply that its earlier input buffers have
        // already been released. Drop only unused cached texture references,
        // then allow the encoder a bounded interval to release in-flight frames.
        // The ten-buffer cap and output dimensions remain unchanged.
        let deadline = ProcessInfo.processInfo.systemUptime + 2
        while result == kCVReturnWouldExceedAllocationThreshold {
            try Task.checkCancellation()
            CVMetalTextureCacheFlush(cache, 0)
            result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(kCFAllocatorDefault,
                pools[key]!, allocation, &value)
            if result != kCVReturnWouldExceedAllocationThreshold { break }
            if ProcessInfo.processInfo.systemUptime >= deadline { break }
            // This synchronous renderer runs on the export worker. Sleeping
            // yields CPU time instead of spinning or increasing memory use.
            Thread.sleep(forTimeInterval: 0.005)
        }
        guard result == kCVReturnSuccess, let value else {'''
if old in text:
    assert text.count(old)==1
    p.write_text(text.replace(old,new))
else:
    assert new in text, 'The renderer changed; review instead of applying an uncertain patch.'
print('Facet renderer retains its fixed buffer cap and waits briefly for encoder backpressure.')
