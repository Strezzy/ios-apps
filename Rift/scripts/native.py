#!/usr/bin/env python3
import os, platform, subprocess
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]; SOURCE=ROOT/'ThirdParty/llama'; BUILD=ROOT/'Build'
def run(args):
    print('+',' '.join(map(str,args)),flush=True); subprocess.run(list(map(str,args)),check=True)
def build(sdk):
    destination=BUILD/'Native'/sdk
    if (destination/'libruntime.a').exists(): print('Native cache:',sdk); return
    directory=BUILD/('cmake-'+sdk)
    arch='arm64' if sdk=='iphoneos' else platform.machine()
    options=['-DCMAKE_BUILD_TYPE=Release','-DBUILD_SHARED_LIBS=OFF','-DLLAMA_BUILD_COMMON=ON','-DLLAMA_BUILD_TESTS=OFF','-DLLAMA_BUILD_TOOLS=OFF','-DLLAMA_BUILD_EXAMPLES=OFF','-DLLAMA_BUILD_SERVER=OFF','-DLLAMA_SUBPROCESS=OFF','-DGGML_NATIVE=OFF','-DGGML_OPENMP=OFF','-DGGML_ACCELERATE=ON','-DGGML_METAL='+('ON' if sdk=='iphoneos' or (sdk=='macosx' and os.getenv('RIFT_MAC_METAL')=='1') else 'OFF'),'-DGGML_METAL_EMBED_LIBRARY=ON','-DGGML_BLAS=OFF','-DLLAMA_OPENSSL=OFF','-DLLAMA_CURL=OFF','-DHTTPLIB_USE_OPENSSL_IF_AVAILABLE=OFF','-DHTTPLIB_USE_ZLIB_IF_AVAILABLE=OFF','-DHTTPLIB_USE_BROTLI_IF_AVAILABLE=OFF','-DHTTPLIB_USE_ZSTD_IF_AVAILABLE=OFF','-DCMAKE_OSX_ARCHITECTURES='+arch]
    if sdk!='macosx': options += ['-DCMAKE_SYSTEM_NAME=iOS','-DCMAKE_OSX_SYSROOT='+sdk,'-DCMAKE_OSX_DEPLOYMENT_TARGET=26.0']
    run(['cmake','-S',SOURCE,'-B',directory]+options)
    run(['cmake','--build',directory,'--config','Release','--target','llama-common','--parallel',str(min(8,os.cpu_count() or 4))])
    libs=sorted(directory.rglob('*.a')); assert libs,'No static native libraries were built'
    destination.mkdir(parents=True,exist_ok=True)
    run(['xcrun','libtool','-static','-o',destination/'libruntime.a']+libs)
    run(['xcrun','lipo','-info',destination/'libruntime.a'])
if __name__=='__main__':
    import sys
    for sdk in (sys.argv[1:] or ['iphonesimulator','iphoneos','macosx']): build(sdk)
