#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
MAP_PATH="$REPO_ROOT/Specs/ux/interaction-map.yaml"
UITESTS_DIR="$REPO_ROOT/SwiftMTPUITests"
UXFLOW_PATH="$REPO_ROOT/SwiftMTPKit/Sources/SwiftMTPUI/UXFlowID.swift"
A11Y_PATH="$REPO_ROOT/SwiftMTPKit/Sources/SwiftMTPUI/AccessibilityID.swift"
SCHEMA_PATH="$REPO_ROOT/Specs/ux/interaction-map.schema.json"

if [[ ! -f "$MAP_PATH" ]]; then
  echo "❌ Missing interaction map: $MAP_PATH"
  exit 1
fi

if [[ ! -f "$UXFLOW_PATH" ]]; then
  echo "❌ Missing UX flow IDs file: $UXFLOW_PATH"
  exit 1
fi

if [[ ! -f "$A11Y_PATH" ]]; then
  echo "❌ Missing accessibility IDs file: $A11Y_PATH"
  exit 1
fi

if [[ ! -f "$SCHEMA_PATH" ]]; then
  echo "❌ Missing interaction map schema: $SCHEMA_PATH"
  exit 1
fi

python3 - "$MAP_PATH" "$UITESTS_DIR" "$UXFLOW_PATH" "$A11Y_PATH" "$REPO_ROOT" "$SCHEMA_PATH" <<'PY'
import re
import sys
from collections import Counter
from pathlib import Path
from typing import Optional
import json

map_path = Path(sys.argv[1])
ui_tests_dir = Path(sys.argv[2])
ux_flow_path = Path(sys.argv[3])
accessibility_path = Path(sys.argv[4])
repo_root = Path(sys.argv[5])
schema_path = Path(sys.argv[6])

required_scalar_fields = [
    "id",
    "screen",
    "kind",
    "risk",
    "assertion_level",
    "priority",
    "gate",
    "preconditions",
    "user_action",
    "expected_ui",
    "expected_state",
]
required_list_fields = [
    "oracles",
    "test_kinds",
    "test_refs",
    "accessibility_ids",
    "negative_cases",
]
non_empty_list_fields = [
    "oracles",
    "test_kinds",
    "test_refs",
    "accessibility_ids",
]

allowed_kinds = {"tap", "toggle", "navigate", "edit", "confirm", "background_update"}
allowed_risks = {"low", "medium", "high"}
allowed_assertions = {"state-only", "view-tree", "automation", "hardware"}
allowed_priorities = {"P0", "P1", "P2"}
expected_gate_by_priority = {"P0": "pr-hard", "P1": "nightly-soft", "P2": "tracked"}
allowed_oracles = {"state_marker", "rendered_text", "ux_event", "model_state"}
allowed_test_kinds = {"automation", "unit", "snapshot", "hardware", "manual"}


def unquote(raw: str) -> str:
    value = raw.strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        return value[1:-1]
    return value


def parse_inline_list(raw: str) -> list[str]:
    value = raw.strip()
    if value in ("", "[]"):
        return []
    if value.startswith("[") and value.endswith("]"):
        inner = value[1:-1].strip()
        if not inner:
            return []
        return [unquote(part.strip()) for part in inner.split(",") if part.strip()]
    return [unquote(value)]


def new_interaction() -> dict[str, object]:
    interaction = {field: [] for field in required_list_fields}
    interaction.update({field: "" for field in required_scalar_fields})
    return interaction


def parse_map(path: Path) -> list[dict[str, object]]:
    lines = path.read_text(encoding="utf-8").splitlines()
    interactions: list[dict[str, object]] = []
    current: Optional[dict[str, object]] = None
    active_list: Optional[str] = None

    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped.startswith("- id:"):
            if current is not None:
                interactions.append(current)
            current = new_interaction()
            current["id"] = unquote(stripped.split(":", 1)[1].strip())
            active_list = None
            continue

        if current is None:
            continue

        list_header = re.match(r"^([A-Za-z_]+):\s*$", stripped)
        if list_header and list_header.group(1) in required_list_fields:
            active_list = list_header.group(1)
            continue

        scalar_match = re.match(r"^([A-Za-z_]+):\s*(.+)$", stripped)
        if scalar_match:
            key = scalar_match.group(1)
            raw_value = scalar_match.group(2)
            if key in required_list_fields:
                values = parse_inline_list(raw_value)
                cast_list = current[key]
                if not isinstance(cast_list, list):
                    cast_list = []
                    current[key] = cast_list
                cast_list.extend(values)
            else:
                current[key] = unquote(raw_value)
            active_list = None
            continue

        if active_list and stripped.startswith("- "):
            cast_list = current[active_list]
            if not isinstance(cast_list, list):
                cast_list = []
                current[active_list] = cast_list
            cast_list.append(unquote(stripped[2:].strip()))
            continue

        if re.match(r"^[A-Za-z_]+:", stripped):
            active_list = None

    if current is not None:
        interactions.append(current)

    return interactions


def parse_available_ui_tests(path: Path) -> set[str]:
    available_tests: set[str] = set()
    for swift_file in sorted(path.rglob("*.swift")):
        class_name = None
        for source_line in swift_file.read_text(encoding="utf-8").splitlines():
            class_match = re.search(r"\bclass\s+(\w+)\s*:\s*XCTestCase", source_line)
            if class_match:
                class_name = class_match.group(1)

            func_match = re.search(r"\bfunc\s+([A-Za-z0-9_]+)\s*\(", source_line)
            if func_match:
                method = func_match.group(1)
                available_tests.add(method)
                if class_name:
                    available_tests.add(f"{class_name}.{method}")
    return available_tests


def parse_flow_ids(path: Path) -> set[str]:
    text = path.read_text(encoding="utf-8")
    return set(re.findall(r'case\s+\w+\s*=\s*"([^"]+)"', text))


def parse_map_metadata(path: Path) -> tuple[str, str]:
    version = ""
    owner = ""
    for line in path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue

        if stripped.startswith("version:") and not version:
            version = unquote(stripped.split(":", 1)[1].strip())
            if version:
                continue

        if stripped.startswith("owner:") and not owner:
            owner = unquote(stripped.split(":", 1)[1].strip())

        if version and owner:
            break

    return version, owner


def validate_with_schema(
    schema_path: Path,
    map_path: Path,
    interactions: list[dict[str, object]],
) -> list[str]:
    try:
        import jsonschema
    except ModuleNotFoundError:
        return ["JSON schema validation skipped: install Python jsonschema (python3 -m pip install jsonschema)"]

    try:
        schema = json.loads(schema_path.read_text(encoding="utf-8"))
    except Exception as exc:
        return [f"interaction map schema is not valid JSON: {schema_path}: {exc}"]

    version, owner = parse_map_metadata(map_path)
    data = {
        "version": version,
        "owner": owner,
        "interactions": interactions,
    }

    try:
        if hasattr(jsonschema, "Draft202012Validator"):
            validator = jsonschema.Draft202012Validator(schema)
            errors: list[str] = []
            for error in sorted(validator.iter_errors(data), key=lambda e: "/".join(str(part) for part in error.absolute_path)):
                location = "/".join(str(part) for part in error.absolute_path) or "<root>"
                errors.append(f"{location}: {error.message}")
            return errors

        jsonschema.validate(instance=data, schema=schema)
        return []
    except Exception as exc:
        return [f"interaction map failed JSON schema validation: {exc}"]


def parse_accessibility_ids(path: Path) -> tuple[set[str], set[str]]:
    text = path.read_text(encoding="utf-8")
    static_ids = set(re.findall(r'public\s+static\s+let\s+\w+\s*=\s*"([^"]+)"', text))
    dynamic_prefixes = set(re.findall(r'"([A-Za-z0-9._-]+)\\\(', text))
    dynamic_prefixes = {prefix for prefix in dynamic_prefixes if prefix not in static_ids}
    return static_ids, dynamic_prefixes


def token_matches_id(token: str, identifier: str) -> bool:
    if token.endswith("*"):
        return identifier.startswith(token[:-1])
    return token == identifier

if not ui_tests_dir.exists():
    print(f"❌ UI tests directory does not exist: {ui_tests_dir}")
    sys.exit(1)

interactions = parse_map(map_path)
schema_errors = validate_with_schema(schema_path, map_path, interactions)
flow_ids = parse_flow_ids(ux_flow_path)
static_accessibility_ids, dynamic_accessibility_prefixes = parse_accessibility_ids(accessibility_path)
available_tests = parse_available_ui_tests(ui_tests_dir)

if not interactions:
    print(f"❌ No interactions found in {map_path}")
    sys.exit(1)

errors: list[str] = []

for schema_error in schema_errors:
    errors.append(f"schema: {schema_error}")

interaction_ids = [str(item.get("id", "")).strip() for item in interactions]

duplicate_ids = sorted({flow_id for flow_id in interaction_ids if interaction_ids.count(flow_id) > 1 and flow_id})
if duplicate_ids:
    errors.append("Duplicate interaction IDs found: " + ", ".join(duplicate_ids))

for item in interactions:
    interaction_id = str(item.get("id", "")).strip()
    item_errors: list[str] = []

    for field in required_scalar_fields:
        raw_value = str(item.get(field, "")).strip()
        if not raw_value:
            item_errors.append(f"missing required field '{field}'")

    for field in non_empty_list_fields:
        values = item.get(field, [])
        if not isinstance(values, list) or not values:
            item_errors.append(f"missing non-empty list '{field}'")

    kind = str(item.get("kind", "")).strip()
    risk = str(item.get("risk", "")).strip()
    assertion_level = str(item.get("assertion_level", "")).strip()
    priority = str(item.get("priority", "")).strip()
    gate = str(item.get("gate", "")).strip()
    oracles = list(item.get("oracles", []))
    test_kinds = list(item.get("test_kinds", []))
    test_refs = list(item.get("test_refs", []))
    accessibility_ids = list(item.get("accessibility_ids", []))

    if kind and kind not in allowed_kinds:
        item_errors.append(f"invalid kind '{kind}'")
    if risk and risk not in allowed_risks:
        item_errors.append(f"invalid risk '{risk}'")
    if assertion_level and assertion_level not in allowed_assertions:
        item_errors.append(f"invalid assertion_level '{assertion_level}'")
    if priority and priority not in allowed_priorities:
        item_errors.append(f"invalid priority '{priority}'")
    if priority in expected_gate_by_priority and gate != expected_gate_by_priority[priority]:
        item_errors.append(
            f"priority '{priority}' must use gate '{expected_gate_by_priority[priority]}' (found '{gate}')"
        )

    for oracle in oracles:
        if oracle not in allowed_oracles:
            item_errors.append(f"invalid oracle '{oracle}'")

    normalized_test_kinds = set()
    for test_kind in test_kinds:
        if test_kind not in allowed_test_kinds:
            item_errors.append(f"invalid test kind '{test_kind}'")
        else:
            normalized_test_kinds.add(test_kind)

    automation_ref_count = 0
    for test_ref in test_refs:
        if ":" not in test_ref:
            item_errors.append(f"test ref '{test_ref}' must be formatted as '<kind>:<identifier>'")
            continue

        ref_kind, ref_value = test_ref.split(":", 1)
        ref_kind = ref_kind.strip()
        ref_value = ref_value.strip()

        if ref_kind not in allowed_test_kinds:
            item_errors.append(f"test ref '{test_ref}' has unknown kind '{ref_kind}'")
            continue

        if ref_kind not in normalized_test_kinds:
            item_errors.append(f"test ref '{test_ref}' kind '{ref_kind}' is missing in test_kinds")

        if not ref_value:
            item_errors.append(f"test ref '{test_ref}' has empty identifier")
            continue

        if ref_kind == "automation":
            automation_ref_count += 1
            if ref_value not in available_tests:
                item_errors.append(f"automation test '{ref_value}' does not exist in SwiftMTPUITests")

        if ref_kind == "manual":
            manual_path = ref_value.split("#", 1)[0]
            if not (repo_root / manual_path).exists():
                item_errors.append(f"manual test path '{manual_path}' does not exist")

    if priority == "P0":
        if "automation" not in normalized_test_kinds:
            item_errors.append("P0 interactions must include 'automation' in test_kinds")
        if automation_ref_count == 0:
            item_errors.append("P0 interactions must include at least one automation test ref")
        if not set(oracles).intersection({"state_marker", "ux_event"}):
            item_errors.append("P0 interactions must include oracle 'state_marker' or 'ux_event'")
        if assertion_level != "automation":
            item_errors.append("P0 interactions must use assertion_level 'automation'")

    if interaction_id and not re.match(r"^ux\.[a-z0-9]+(?:[._][a-z0-9]+)*$", interaction_id):
        item_errors.append(f"interaction id '{interaction_id}' must use stable ux.* naming")

    for a11y_token in accessibility_ids:
        if "*" in a11y_token and not a11y_token.endswith("*"):
            item_errors.append(
                f"accessibility token '{a11y_token}' uses wildcard in unsupported position; use trailing '*' only"
            )

        if a11y_token.endswith("*"):
            prefix = a11y_token[:-1]
            if not any(candidate.startswith(prefix) for candidate in static_accessibility_ids) and not any(
                candidate.startswith(prefix) for candidate in dynamic_accessibility_prefixes
            ):
                item_errors.append(f"accessibility wildcard '{a11y_token}' does not match any known ID or prefix")
        else:
            if a11y_token not in static_accessibility_ids:
                item_errors.append(f"unknown accessibility id '{a11y_token}'")

    if item_errors:
        label = interaction_id or "<missing id>"
        for item_error in item_errors:
            errors.append(f"{label}: {item_error}")

p0_interactions = [item for item in interactions if item.get("priority") == "P0"]
if not p0_interactions:
    errors.append(f"No P0 interactions defined in {map_path}")

map_ids = set(interaction_ids)
missing_in_map = sorted(flow_ids - map_ids)
extra_in_map = sorted(map_ids - flow_ids)
if missing_in_map:
    errors.append("UXFlowID values missing from interaction map: " + ", ".join(missing_in_map))
if extra_in_map:
    errors.append("interaction map IDs missing from UXFlowID enum: " + ", ".join(extra_in_map))

all_accessibility_tokens = {
    token
    for item in interactions
    for token in item.get("accessibility_ids", [])
    if isinstance(token, str) and token
}

missing_static_accessibility = [
    identifier
    for identifier in sorted(static_accessibility_ids)
    if not any(token_matches_id(token, identifier) for token in all_accessibility_tokens)
]
if missing_static_accessibility:
    errors.append(
        "Accessibility IDs missing from interaction map coverage: " + ", ".join(missing_static_accessibility)
    )

missing_dynamic_prefixes = []
for prefix in sorted(dynamic_accessibility_prefixes):
    covered = any(
        token.endswith("*") and prefix.startswith(token[:-1]) for token in all_accessibility_tokens
    )
    if not covered:
        missing_dynamic_prefixes.append(prefix)
if missing_dynamic_prefixes:
    errors.append(
        "Dynamic accessibility prefixes missing wildcard coverage in interaction map: "
        + ", ".join(missing_dynamic_prefixes)
    )

if errors:
    print("❌ UX interaction map validation failed:")
    for error in errors:
        print(f"  - {error}")
    sys.exit(1)

priority_counts = Counter(str(item.get("priority", "")) for item in interactions)

print(
    "✅ UX map validated: "
    f"{len(interactions)} interactions "
    f"(P0={priority_counts.get('P0', 0)}, P1={priority_counts.get('P1', 0)}, P2={priority_counts.get('P2', 0)})."
)
print(
    "✅ Flow coverage validated: "
    f"{len(flow_ids)} UXFlowID values are synchronized with interaction-map IDs."
)
print(
    "✅ Accessibility coverage validated: "
    f"{len(static_accessibility_ids)} static IDs + {len(dynamic_accessibility_prefixes)} dynamic prefixes mapped."
)
PY
