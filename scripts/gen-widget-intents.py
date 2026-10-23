"""ウィジェットの「編集」画面用の App Intents メタデータ (Metadata.appintents) を Linux で作る。

Xcode は macOS 専用の appintentsmetadataprocessor でこれを作るが、xtool では動かない。
xtool-on-linux の生成器 (https://github.com/cyberneel/xtool-on-linux, MIT) で土台を作り、
それが未対応の「エンティティ型のパラメータ」と EntityQuery を、Apple 製の実物
(xcode-tools 26.3 が出力したもの) と同じ形に書き足す。

使い方 (Intent やエンティティを変えたら作り直す):
    xtool dev build
    git clone https://github.com/cyberneel/xtool-on-linux /tmp/xol
    python3 scripts/gen-widget-intents.py /tmp/xol/appintents/appintents-gen.py
"""

import json
import subprocess
import sys
from pathlib import Path

MODULE = "comadoWidget"
# xtool は無料チームの bundle ID に XTL-<チーム ID> を付ける
APP_ID = "XTL-BE7S85FN44.com.example.comado"
WIDGET_ID = APP_ID + ".comadoWidget"
CONST_VALUES = Path(".build/out/Intermediates.noindex/comado.build/Debug-iphoneos/"
                    "comadoWidget-t.build/Objects-normal/arm64/Widget.swiftconstvalues")
OUT = Path("Resources/Widget/Metadata.appintents")


def main(generator: str) -> None:
    subprocess.run([sys.executable, "-I", generator, "--module", MODULE, "--bundle-id", WIDGET_ID,
                    "--extra-bundle-id", APP_ID, "--out", str(OUT), str(CONST_VALUES)], check=True)
    types = json.loads(CONST_VALUES.read_text())
    entities = {t["typeName"].split(".")[-1] for t in types if "AppIntents.AppEntity" in t["conformances"]}
    queries = [t for t in types if "AppIntents.EntityQuery" in t["conformances"]]

    path = OUT / "extract.actionsdata"
    data = json.loads(path.read_text())

    # エンティティ型のパラメータ: 生成器は文字列扱いにするので、エンティティ参照に直す
    for action_type in types:
        action = data["actions"].get(action_type["typeName"].split(".")[-1])
        if not action:
            continue
        swift_types = {p["label"][1:]: p["type"] for p in action_type.get("properties", [])
                       if p.get("label", "").startswith("_")}
        for param in action["parameters"]:
            entity = next((e for e in entities if f".{e}" in swift_types.get(param["name"], "")), None)
            if entity:
                param["valueType"] = {"entity": {"wrapper": {"typeName": entity}}}
                param["dynamicOptionsSupport"] = 2
                param["resolvableInputTypes"] = []

    # EntityQuery と、エンティティからの参照
    for q in queries:
        name = q["typeName"].split(".")[-1]
        entity = next(t["typeName"].split(".")[-1] for t in types
                      if t["typeName"].split(".")[-1] in entities
                      and any(p.get("label") == "defaultQuery" and name in json.dumps(p) for p in t.get("properties", [])))
        data["queries"][name] = {
            "availabilityAnnotations": {"LNPlatformNameWildcard": {"introducedVersion": "*"}},
            "capabilities": 6,
            "defaultQueryForEntity": True,
            "effectiveBundleIdentifiers": [],
            "entityType": entity,
            "fullyQualifiedIdentifier": f"{MODULE}.{name}",
            "identifier": name,
            "mangledTypeName": q["mangledTypeName"],
            "mangledTypeNameByBundleIdentifier": {},
            "parameters": [],
            "queryType": name,
            "resultValueType": {"entity": {"wrapper": {"typeName": entity}}},
            "sortingOptions": [],
            "visibilityMetadata": {"assistantOnly": False, "isDiscoverable": True},
        }
        e = data["entities"][entity]
        e["defaultQueryIdentifier"] = f"{MODULE}.{name}"
        e.setdefault("numericFormatTypeName", e["displayTypeName"])

    path.write_text(json.dumps(data, ensure_ascii=False, sort_keys=True))
    print(f"patched: {path}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
