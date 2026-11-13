"""Synthetic unsigned profiles for the mocked device tests; never install these."""
from pathlib import Path
import datetime
import plistlib
import sys
import uuid
import zipfile

root = Path(sys.argv[1])
root.mkdir(exist_ok=True)

def container(tag, value):
    return bytes([tag, 0x82]) + len(value).to_bytes(2, 'big') + value

def profile(bundle, revision):
    plist = plistlib.dumps({
        'Name': bundle, 'UUID': str(uuid.uuid5(uuid.NAMESPACE_DNS, f'{bundle}-{revision}')),
        'TeamIdentifier': ['TESTTEAM'], 'CreationDate': datetime.datetime(2026, 1, 1),
        'ExpirationDate': datetime.datetime(2026, 1, 7 + revision), 'LocalProvision': True,
        'Entitlements': {'application-identifier': f'TESTTEAM.{bundle}'},
    })
    oid = b'\x06\x09\x2a\x86\x48\x86\xf7\x0d\x01\x07\x01'
    return container(0x30, oid + container(0xa0, container(0x30,
        b'\x02\x01\x01\x31\x00' + container(0x30, oid + container(0xa0, container(4, plist))))))

for name in ['A', 'B', 'C', 'D']:
    (root / f'{name}.mobileprovision').write_bytes(profile(name, 0))
    app = root / f'{name}.app'
    app.mkdir(exist_ok=True)
    (app / 'Info.plist').write_bytes(plistlib.dumps({
        'CFBundleName': name, 'CFBundleIdentifier': name, 'CFBundleShortVersionString': '1.0'}))
    (app / 'embedded.mobileprovision').write_bytes(profile(name, 1))
    with zipfile.ZipFile(root / f'{name}.ipa', 'w') as archive:
        for path in app.iterdir():
            archive.write(path, f'Payload/{app.name}/{path.name}')
