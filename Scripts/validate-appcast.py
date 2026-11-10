#!/usr/bin/env python3
"""Check staged release metadata before promoting it to GitHub Pages."""

import base64
import pathlib
import re
import sys
import urllib.parse
import xml.etree.ElementTree as ET


def validate(appcast, dmg):
    sparkle = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
    items = ET.parse(appcast).findall("./channel/item")
    if len(items) != 1:
        raise ValueError("Expected exactly one staged update")
    item = items[0]
    version = item.findtext(f"{sparkle}shortVersionString", "")
    build = item.findtext(f"{sparkle}version", "")
    if not build.isdigit() or int(build) < 1 or not version:
        raise ValueError("Missing application version or build number")
    if dmg.name != f"pile-{version}.dmg":
        raise ValueError("Appcast version does not match the DMG filename")
    enclosure = item.find("enclosure")
    if enclosure is None:
        raise ValueError("Missing update enclosure")
    signature = enclosure.get(f"{sparkle}edSignature", "")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Missing or invalid EdDSA update signature")
    if dmg.stat().st_size == 0 or int(enclosure.get("length", "0")) != dmg.stat().st_size:
        raise ValueError("Appcast length does not match the DMG")
    url = enclosure.get("url", "")
    parsed = urllib.parse.urlsplit(url)
    expected_path = rf"/akira1ce/pile/releases/download/v?{re.escape(version)}/{re.escape(dmg.name)}"
    if (parsed.scheme != "https" or parsed.netloc != "github.com"
            or not re.fullmatch(expected_path, parsed.path) or parsed.query or parsed.fragment):
        raise ValueError("Update must point to the matching pile GitHub Release asset")
    return url, signature


if __name__ == "__main__":
    try:
        if len(sys.argv) != 3:
            raise ValueError("Usage: validate-appcast.py <appcast.xml> <pile-version.dmg>")
        print("\t".join(validate(pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2]))))
    except (ValueError, OSError, ET.ParseError) as error:
        sys.exit(f"Invalid appcast: {error}")
