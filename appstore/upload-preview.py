#!/usr/bin/env python3
"""Uploads appstore/preview/preview.mp4 as the Mac app preview (preview set DESKTOP).

ascpilot uploads screenshots but not app previews, so this does the same dance for a
preview: find or create the set, delete what is there, reserve, PUT the parts, commit with
the MD5, and set the poster frame. It borrows ascpilot's auth and API helpers rather than
copying them (ascpilot's bin/asc.py is loaded as a module; nothing in it is changed).

    export ASC_PLATFORM=MAC_OS ASC_META=~/Documents/GitHub/kevinbrowncodes/mission-control/appstore/asc_meta.json
    python3 appstore/preview/make_preview.py      # builds preview.mp4
    python3 appstore/upload-preview.py            # uploads it

Then `python3 appstore/upload-preview.py --status` until the preview's state is COMPLETE.
"""
import hashlib
import importlib.util
import os
import sys
import time
import urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ASCPILOT = os.path.expanduser("~/Documents/GitHub/kevinbrowncodes/ascpilot/bin/asc.py")
VIDEO = os.path.join(HERE, "preview", "preview.mp4")
PREVIEW_TYPE = "DESKTOP"
POSTER = "00:00:06:15"  # mid "Name your Spaces" (4.7–8.2 s), clear of both crossfades

spec = importlib.util.spec_from_file_location("asc", ASCPILOT)
asc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(asc)


def preview_set(localization: str, create: bool):
    sets = asc.api("GET", f"/v1/appStoreVersionLocalizations/{localization}/appPreviewSets")["data"]
    for s in sets:
        if s["attributes"]["previewType"] == PREVIEW_TYPE:
            return s["id"]
    if not create:
        return None
    return asc.api("POST", "/v1/appPreviewSets", {"data": {
        "type": "appPreviewSets",
        "attributes": {"previewType": PREVIEW_TYPE},
        "relationships": {"appStoreVersionLocalization": {
            "data": {"type": "appStoreVersionLocalizations", "id": localization}}}}})["data"]["id"]


def localization_id() -> str:
    version = asc.version_id(asc.app_id())
    return asc.api("GET", f"/v1/appStoreVersions/{version}/appStoreVersionLocalizations")["data"][0]["id"]


def status():
    sid = preview_set(localization_id(), create=False)
    if not sid:
        print("no DESKTOP preview set")
        return
    for p in asc.api("GET", f"/v1/appPreviewSets/{sid}/appPreviews")["data"]:
        a = p["attributes"]
        state = (a.get("assetDeliveryState") or {}).get("state")
        errors = (a.get("assetDeliveryState") or {}).get("errors")
        print(f"{a.get('fileName')}: {state}" + (f" {errors}" if errors else ""))


def upload():
    if not os.path.exists(VIDEO):
        sys.exit(f"{VIDEO} is missing: run python3 appstore/preview/make_preview.py first")
    data = open(VIDEO, "rb").read()
    sid = preview_set(localization_id(), create=True)
    for old in asc.api("GET", f"/v1/appPreviewSets/{sid}/appPreviews")["data"]:
        asc.api("DELETE", f"/v1/appPreviews/{old['id']}")
    preview = asc.api("POST", "/v1/appPreviews", {"data": {
        "type": "appPreviews",
        "attributes": {"fileName": os.path.basename(VIDEO), "fileSize": len(data),
                       "mimeType": "video/mp4", "previewFrameTimeCode": POSTER},
        "relationships": {"appPreviewSet": {"data": {"type": "appPreviewSets", "id": sid}}}}})["data"]
    operations = preview["attributes"]["uploadOperations"]
    for n, op in enumerate(operations, start=1):
        chunk = data[op["offset"]: op["offset"] + op["length"]]
        req = urllib.request.Request(op["url"], data=chunk, method=op["method"])
        for h in op["requestHeaders"]:
            req.add_header(h["name"], h["value"])
        with urllib.request.urlopen(req) as r:
            r.read()
        print(f"\rpart {n}/{len(operations)}", end="", flush=True)
    print()
    asc.api("PATCH", f"/v1/appPreviews/{preview['id']}", {"data": {
        "type": "appPreviews", "id": preview["id"],
        "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(data).hexdigest()}}})
    print(f"uploaded {os.path.basename(VIDEO)} ({len(data) // 1_000_000} MB); App Store Connect processes it")
    time.sleep(5)
    status()


if __name__ == "__main__":
    status() if "--status" in sys.argv else upload()
