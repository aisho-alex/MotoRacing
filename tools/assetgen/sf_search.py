#!/usr/bin/env python3
"""Sketchfab search helper: query downloadable models, client-side license filter.

Token is read from /tmp/opencode/sketchfab_token (never committed).

Usage: sf_search.py <query> [min_faces] [max_faces] [count]
Prints: uid | faces | license | author | name
"""
import json
import sys
import urllib.request

TOKEN = open("/tmp/opencode/sketchfab_token").read().strip()
OK_LICENSES = {"CC Attribution", "CC0", "Public Domain"}


def search(query, min_faces, max_faces, count=24):
    url = ("https://api.sketchfab.com/v3/search?type=models&downloadable=true"
           f"&q={urllib.parse.quote(query)}&count={count}&sort_by=-likeCount")
    req = urllib.request.Request(url, headers={"Authorization": f"Token {TOKEN}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        data = json.load(r)
    out = []
    for m in data.get("results", []):
        lic = (m.get("license") or {}).get("label", "?")
        if lic not in OK_LICENSES:
            continue
        faces = m.get("faceCount") or 0
        if not (min_faces <= faces <= max_faces):
            continue
        out.append({
            "uid": m["uid"],
            "name": m["name"],
            "faces": faces,
            "license": lic,
            "author": m["user"]["username"],
            "vertexColors": m.get("vertexColors", False),
            "animated": m.get("animated", False),
        })
    return out


if __name__ == "__main__":
    import urllib.parse
    query = sys.argv[1]
    lo = int(sys.argv[2]) if len(sys.argv) > 2 else 8000
    hi = int(sys.argv[3]) if len(sys.argv) > 3 else 60000
    for m in search(query, lo, hi, int(sys.argv[4]) if len(sys.argv) > 4 else 24):
        print(f"{m['uid']} | {m['faces']:7d} | {m['license']:14s} | {m['author'][:16]:16s} | {m['name'][:48]}")
