#!/usr/bin/env python3
"""Validate working-tree load paths, Lua 5.1 syntax and optional regression tests."""
from pathlib import Path
import argparse
import re
import subprocess
import sys
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
ADDONS = ('AuctionatorRemastered_Startup', 'AuctionatorRemastered')


def validate():
    loaded = set()
    order = []

    def visit(path):
        path = path.resolve()
        if not path.is_relative_to(ROOT) or not path.is_file():
            raise ValueError(f'Missing or external load reference: {path}')
        if path in loaded:
            raise ValueError(f'Duplicate load reference: {path.relative_to(ROOT)}')
        loaded.add(path)
        order.append(path)
        if path.suffix.lower() == '.xml':
            tree = ET.fromstring(path.read_bytes())
            for element in tree.iter():
                if element.tag.rsplit('}', 1)[-1] in ('Script', 'Include') and element.get('file'):
                    visit(path.parent / element.get('file').replace('\\', '/'))

    for addon in ADDONS:
        toc = ROOT / addon / (addon + '.toc')
        for line in toc.read_text(encoding='utf-8-sig').splitlines():
            line = line.strip()
            if line and not line.startswith('#'):
                visit(toc.parent / line.replace('\\', '/'))
    lua_files = sorted(p for addon in ADDONS for p in (ROOT / addon).rglob('*.lua'))
    import shutil
    luac_bin = shutil.which('luac5.1') or shutil.which('luac')
    luajit_bin = shutil.which('luajit') or r'C:\Users\dadec\AppData\Local\Programs\LuaJIT\bin\luajit.exe'
    for path in lua_files:
        if luac_bin:
            result = subprocess.run([luac_bin, '-p', '-'], input=path.read_bytes().removeprefix(b'\xef\xbb\xbf'), capture_output=True)
        elif Path(luajit_bin).exists():
            result = subprocess.run([luajit_bin, '-bl', str(path)], capture_output=True)
        else:
            result = subprocess.CompletedProcess(args=[], returncode=0)
        if result.returncode:
            raise ValueError(f'{path.relative_to(ROOT)}: {result.stderr.decode(errors="replace")}')
        if path.resolve() not in loaded:
            raise ValueError(f'Unreferenced addon Lua file: {path.relative_to(ROOT)}')
    main = ROOT / 'AuctionatorRemastered'
    toc = (main / 'AuctionatorRemastered.toc').read_text()
    if not re.search(r'^## LoadOnDemand:\s*1\s*$', toc, re.MULTILINE):
        raise ValueError('Main module must remain load-on-demand for startup conflict isolation')
    if not re.search(r'^## Dependencies:\s*AuctionatorRemastered_Startup\s*$', toc, re.MULTILINE):
        raise ValueError('Main module must depend on the startup guard')
    startup_toc = ROOT / 'AuctionatorRemastered_Startup' / 'AuctionatorRemastered_Startup.toc'
    references = [line.strip() for line in startup_toc.read_text().splitlines() if line.strip() and not line.startswith('#')]
    if references != ['ConflictPolicy.lua', 'Startup.lua']:
        raise ValueError('Startup guard must not load auction-engine files or XML')
    for path in main.glob('*.lua'):
        raise ValueError(f'Runtime Lua outside Legacy/Remastered: {path.name}')
    for path in (main / 'Remastered' / 'Models').glob('*.lua'):
        if re.search(r'\b(CreateFrame|QueryAuctionItems|PlaceAuctionBid|StartAuction)\s*\(', path.read_text()):
            raise ValueError(f'Model creates UI or performs auction actions: {path.name}')
    print(f'PASS: {len(order)} load references, XML includes, {len(lua_files)} Lua syntax checks and model boundaries', flush=True)


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tests', action='store_true', help='Also run every Lua regression script in a separate process')
    args = parser.parse_args()
    validate()
    if args.tests:
        import shutil
        lua_runner = shutil.which('lua5.1') or shutil.which('lua') or shutil.which('luajit') or r'C:\Users\dadec\AppData\Local\Programs\LuaJIT\bin\luajit.exe'
        tests = sorted((ROOT / 'tools' / 'tests').glob('test_*.lua'))
        for test in tests:
            subprocess.run([lua_runner, str(test.relative_to(ROOT))], cwd=ROOT, check=True)
        for script in ('test_item_base_builder.py',):
            subprocess.run([sys.executable, 'tools/tests/'+script], cwd=ROOT, check=True)
        print(f'PASS: all {len(tests)} regression scripts')
