#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOGS = [
    ROOT / "DevHub/Localizable.xcstrings",
    ROOT / "Packages/DevHubCore/Sources/DevHubCore/Resources/Localizable.xcstrings",
]
PLURAL_FORMS = {
    "ru": {"one", "few", "many", "other"},
    "ja": {"other"},
    "ko": {"other"},
    "zh-Hans": {"other"},
}
DEFAULT_PLURAL_FORMS = {"one", "other"}
PLACEHOLDER = re.compile(r"%(?:\d+\$)?(?:lld|ld|d|@|f)")


def placeholders(text):
    return sorted(re.sub(r"%\d+\$", "%", found) for found in PLACEHOLDER.findall(text))


def check(catalog):
    problems = []
    data = json.loads(catalog.read_text(encoding="utf-8"))
    languages = sorted(
        {lang for entry in data["strings"].values() for lang in entry.get("localizations", {})} - {data["sourceLanguage"]}
    )
    for key, entry in sorted(data["strings"].items()):
        if entry.get("shouldTranslate") is False:
            continue
        if entry.get("extractionState") == "stale":
            problems.append(f"{key!r}: stale, no longer used in the code")
        localizations = entry.get("localizations", {})
        for lang in languages:
            localized = localizations.get(lang)
            if localized is None:
                problems.append(f"{key!r}: missing {lang}")
                continue
            if "variations" in localized:
                forms = localized["variations"]["plural"]
                missing = PLURAL_FORMS.get(lang, DEFAULT_PLURAL_FORMS) - forms.keys()
                if missing:
                    problems.append(f"{key!r}: {lang} lacks plural forms {sorted(missing)}")
                units = [form["stringUnit"] for form in forms.values()]
            else:
                units = [localized["stringUnit"]]
            for unit in units:
                value = unit.get("value", "")
                if not value.strip():
                    problems.append(f"{key!r}: {lang} is empty")
                elif unit.get("state") != "translated":
                    problems.append(f"{key!r}: {lang} is {unit.get('state')}, not translated")
                elif placeholders(value) != placeholders(key):
                    problems.append(f"{key!r}: {lang} has different placeholders: {value!r}")
    return languages, problems


def main():
    failed = False
    for catalog in CATALOGS:
        languages, problems = check(catalog)
        name = catalog.relative_to(ROOT)
        if problems:
            failed = True
            print(f"{name}: {len(problems)} problem(s)")
            for problem in problems:
                print(f"  {problem}")
        else:
            print(f"{name}: ok ({len(languages)} languages: {', '.join(languages)})")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
