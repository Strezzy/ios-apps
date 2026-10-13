#!/usr/bin/env python3
"""Compile/link the native iOS executable with restored Linux LLVM tools.

Packaging remains an explicit final action. No simulator or device is emulated.
"""
import argparse
import os
import shlex
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
from make_sdk import make_sdk


def run(arguments, env):
    print(shlex.join(map(str, arguments)), flush=True)
    subprocess.run(list(map(str, arguments)), check=True, env=env)


def main():
    support = Path(__file__).resolve().parent
    default_project = support.parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=default_project)
    parser.add_argument("--toolchain", type=Path)
    parser.add_argument("--build-dir", type=Path)
    parser.add_argument("--compile-only", action="store_true")
    parser.add_argument("--package", action="store_true")
    args = parser.parse_args()
    project = args.project.resolve()
    toolchain = (args.toolchain or default_project.parent / "ios-toolchain").resolve()
    build = (args.build_dir or project / "Build").resolve()
    if args.package and (args.compile_only or build != project / "Build"):
        parser.error("--package requires the project's standard Build directory and a full build")
    tools = toolchain / "usr/lib/llvm-20/bin"
    for name in ("clang", "ld64.lld", "llvm-objdump"):
        if not (tools / name).is_file():
            parser.error("Missing compiler tools; run Support/toolchain/bootstrap.py first")
    env = os.environ.copy()
    env["PATH"] = str(tools) + os.pathsep + env.get("PATH", "")
    build.mkdir(parents=True, exist_ok=True)
    framework_arguments = make_sdk(build / "sdk", support / "symbols.json")
    run([tools / "clang", "-target", "arm64-apple-ios16.0", "-Oz", "-fobjc-arc", "-fblocks",
         "-Wall", "-Wextra", "-Werror", "-Wno-unused-parameter", "-c",
         project / "Sources/main.m", "-o", build / "main.o"], env)
    run([sys.executable, support.parent / "verify_objc_layout.py", build / "main.o",
         "--objdump", tools / "llvm-objdump", "--report", build / "ABI-LAYOUT-REPORT.json"], env)
    if args.compile_only:
        return
    run([tools / "ld64.lld", "-arch", "arm64", "-platform_version", "ios", "16.0", "26.0",
         "-e", "_main", "-pie", "-adhoc_codesign", "-no_fixup_chains",
         "-syslibroot", build / "sdk", *framework_arguments,
         "-o", build / "GlassMusic", build / "main.o"], env)
    if args.package:
        run([sys.executable, project / "Support/package_and_verify.py"], env)
    else:
        print("Built native arm64 executable: " + str(build / "GlassMusic"))


if __name__ == "__main__":
    main()
