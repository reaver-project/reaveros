import argparse
import itertools
import json
import os
import pathlib
import re
import sys

import yaml

identifier = re.compile(r"[a-z][a-z0-9-]*\Z")
value_identifier = re.compile(r"[a-z0-9][a-z0-9-]*\Z")
phases = ("standalone", "producer", "consumer")
runner_classes = {
    "builder-medium",
    "builder-large",
    "validation-medium",
    "validation-large",
}


class MatrixError(ValueError):
    pass


class UniqueKeyLoader(yaml.SafeLoader):
    pass


def unique_mapping(loader, node):
    result = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        try:
            hash(key)
        except TypeError as error:
            raise MatrixError(
                f"unhashable YAML key at line {key_node.start_mark.line + 1}"
            ) from error
        if key in result:
            raise MatrixError(
                f"duplicate YAML key {key!r} at line {key_node.start_mark.line + 1}"
            )
        result[key] = loader.construct_object(value_node, deep=True)
    return result


UniqueKeyLoader.add_constructor(
    yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, unique_mapping
)


def mapping(value, description, required_keys, optional_keys=()):
    if not isinstance(value, dict):
        raise MatrixError(f"{description} must be a mapping")
    missing = set(required_keys) - value.keys()
    unknown = value.keys() - set(required_keys) - set(optional_keys)
    if missing or unknown:
        raise MatrixError(
            f"{description} has missing {sorted(map(str, missing))} "
            f"or unknown {sorted(map(str, unknown))} keys"
        )
    return value


def name(value, description):
    if not isinstance(value, str) or identifier.fullmatch(value) is None:
        raise MatrixError(f"{description} must be a lowercase identifier")
    return value


def tag_value(value, description):
    if not isinstance(value, str) or value_identifier.fullmatch(value) is None:
        raise MatrixError(f"{description} must be a lowercase identifier")
    return value


def names(value, description, allowed=None):
    if not isinstance(value, list) or not value:
        raise MatrixError(f"{description} must be a nonempty list")
    result = [name(item, description) for item in value]
    if len(set(result)) != len(result):
        raise MatrixError(f"{description} contains duplicates")
    if allowed is not None and not set(result) <= set(allowed):
        raise MatrixError(f"{description} contains unknown names")
    return result


def compile_matrix(document, workflow, scripts_dir=None):
    mapping(document, "matrix", ("tags", "artifacts", "jobs", "workflows"))

    tags = document["tags"]
    if not isinstance(tags, dict) or not tags:
        raise MatrixError("tags must be a nonempty mapping")
    for tag, definition in tags.items():
        name(tag, "tag name")
        mapping(definition, f"tag {tag}", (), ("required", "default"))
        if "required" in definition and type(definition["required"]) is not bool:
            raise MatrixError(f"tag {tag} required must be boolean")
        if "default" in definition:
            tag_value(definition["default"], f"tag {tag} default")

    artifacts = document["artifacts"]
    if not isinstance(artifacts, dict) or not artifacts:
        raise MatrixError("artifacts must be a nonempty mapping")
    for artifact, definition in artifacts.items():
        name(artifact, "artifact name")
        mapping(definition, f"artifact {artifact}", ("file",), ("on_failure",))
        if (
            not isinstance(definition["file"], str)
            or re.fullmatch(r"[a-z0-9][a-z0-9.-]*", definition["file"]) is None
        ):
            raise MatrixError(f"artifact {artifact} has an invalid filename")
        if "on_failure" in definition and type(definition["on_failure"]) is not bool:
            raise MatrixError(f"artifact {artifact} on_failure must be boolean")

    jobs = document["jobs"]
    if not isinstance(jobs, dict) or not jobs:
        raise MatrixError("jobs must be a nonempty mapping")
    display_names = set()
    for job_type, definition in jobs.items():
        name(job_type, "job type")
        mapping(
            definition,
            f"job {job_type}",
            ("name", "invoke", "axes", "phase", "runner_class"),
            ("build_environment", "needs", "produces", "consumes"),
        )
        display_name = definition["name"]
        if (
            not isinstance(display_name, str)
            or re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._/-]*", display_name) is None
        ):
            raise MatrixError(f"job {job_type} needs a simple display name")
        if display_name in display_names:
            raise MatrixError(f"job {job_type} repeats display name {display_name}")
        display_names.add(display_name)
        invoke = name(definition["invoke"], f"job {job_type} invoke")
        if scripts_dir is not None:
            script = scripts_dir / invoke
            if not script.is_file() or not os.access(script, os.X_OK):
                raise MatrixError(f"job {job_type} invokes missing script {invoke}")
        names(definition["axes"], f"job {job_type} axes", tags)
        if (
            not isinstance(definition["phase"], str)
            or definition["phase"] not in phases
        ):
            raise MatrixError(f"job {job_type} has an unknown phase")
        if (
            not isinstance(definition["runner_class"], str)
            or definition["runner_class"] not in runner_classes
        ):
            raise MatrixError(f"job {job_type} has an unknown runner class")
        if (
            "build_environment" in definition
            and type(definition["build_environment"]) is not bool
        ):
            raise MatrixError(f"job {job_type} build_environment must be boolean")
        for field in ("produces", "consumes"):
            if field in definition and (
                not isinstance(definition[field], str)
                or definition[field] not in artifacts
            ):
                raise MatrixError(f"job {job_type} references an unknown artifact")
        if "needs" in definition and (
            not isinstance(definition["needs"], str) or definition["needs"] not in jobs
        ):
            raise MatrixError(f"job {job_type} depends on an unknown job")
        if "consumes" in definition and "needs" not in definition:
            raise MatrixError(f"job {job_type} consumes an artifact without a producer")
        if definition["phase"] == "consumer" and "needs" not in definition:
            raise MatrixError(f"job {job_type} has no producer")

    for job_type, definition in jobs.items():
        if "needs" not in definition:
            continue
        producer = jobs[definition["needs"]]
        if definition["phase"] != "consumer" or producer["phase"] != "producer":
            raise MatrixError(f"job {job_type} needs an unsupported phase dependency")
        if not set(producer["axes"]) <= set(definition["axes"]):
            raise MatrixError(f"job {job_type} cannot identify its producer")
        if definition.get("consumes") != producer.get("produces"):
            raise MatrixError(f"job {job_type} consumes the wrong producer artifact")

    workflows = document["workflows"]
    if not isinstance(workflows, dict) or workflow not in workflows:
        raise MatrixError(f"workflow {workflow} is not defined")
    rows = workflows[workflow]
    if not isinstance(rows, list) or not rows:
        raise MatrixError(f"workflow {workflow} must have matrix rows")

    expanded = {}

    def add_job(job_type, coordinates):
        definition = jobs[job_type]
        selected = {}
        for axis in definition["axes"]:
            if axis not in coordinates:
                raise MatrixError(f"job {job_type} needs tag {axis}")
            selected[axis] = coordinates[axis]
        key = (job_type, tuple(selected.items()))
        if key in expanded:
            return expanded[key]
        if "needs" in definition:
            add_job(definition["needs"], coordinates)
        job_id = f"j{len(expanded) + 1}"
        display = "-".join(selected.values())
        spec = {
            "id": job_id,
            "name": f"{definition['name']} ({display})",
            "invoke": definition["invoke"],
            "runner_class": definition["runner_class"],
            "build_environment": definition.get("build_environment", False),
            "tags": selected,
            "artifact_input": "",
            "artifact_output": "",
            "artifact_file": "",
            "upload_on_failure": False,
        }
        if "produces" in definition:
            artifact = definition["produces"]
            spec["artifact_output"] = f"{artifact}-{job_id}"
            spec["artifact_file"] = artifacts[artifact]["file"]
            spec["upload_on_failure"] = artifacts[artifact].get("on_failure", False)
        expanded[key] = spec
        return spec

    for row_number, row in enumerate(rows, 1):
        mapping(row, f"workflow row {row_number}", ("jobs",), tags)
        requested_jobs = names(row["jobs"], f"workflow row {row_number} jobs", jobs)
        used_tags = set()
        for job_type in requested_jobs:
            definition = jobs[job_type]
            used_tags.update(definition["axes"])
            if "needs" in definition:
                used_tags.update(jobs[definition["needs"]]["axes"])
        unused_tags = row.keys() - {"jobs"} - used_tags
        if unused_tags:
            raise MatrixError(
                f"workflow row {row_number} has unused tags {sorted(unused_tags)}"
            )
        dimensions = {}
        for tag, definition in tags.items():
            if tag in row:
                value = row[tag]
            elif "default" in definition:
                value = definition["default"]
            elif definition.get("required", False):
                raise MatrixError(f"workflow row {row_number} needs tag {tag}")
            else:
                continue
            values = value if isinstance(value, list) else [value]
            if not values:
                raise MatrixError(f"workflow row {row_number} has an empty {tag} axis")
            dimensions[tag] = [
                tag_value(item, f"workflow row {row_number} {tag}") for item in values
            ]
            if len(set(dimensions[tag])) != len(dimensions[tag]):
                raise MatrixError(f"workflow row {row_number} repeats {tag} values")
        dimension_names = list(dimensions)
        combinations = 1
        for values in dimensions.values():
            combinations *= len(values)
        if combinations > 64:
            raise MatrixError(
                f"workflow row {row_number} exceeds the 64-way expansion budget"
            )
        for combination in itertools.product(
            *(dimensions[tag] for tag in dimension_names)
        ):
            coordinates = dict(zip(dimension_names, combination))
            for job_type in requested_jobs:
                add_job(job_type, coordinates)
            if len(expanded) > 64:
                raise MatrixError("workflow exceeds the 64-job CI budget")

    for (job_type, _), spec in expanded.items():
        definition = jobs[job_type]
        if "needs" not in definition:
            continue
        producer_type = definition["needs"]
        producer_axes = jobs[producer_type]["axes"]
        producer_key = (
            producer_type,
            tuple((axis, spec["tags"][axis]) for axis in producer_axes),
        )
        spec["artifact_input"] = expanded[producer_key]["artifact_output"]

    groups = {phase: {} for phase in phases}
    for (job_type, _), spec in expanded.items():
        definition = jobs[job_type]
        group = groups[definition["phase"]].setdefault(definition["name"], [])
        group.append(spec)
    return {
        phase: {
            "include": [
                {"name": group_name, "job_matrix": {"include": group_jobs}}
                for group_name, group_jobs in sorted(groups[phase].items())
            ]
        }
        for phase in phases
    }


def main():
    parser = argparse.ArgumentParser(
        description="Compile a ReaverOS CI workflow matrix"
    )
    parser.add_argument("matrix", type=pathlib.Path)
    parser.add_argument("--workflow", default="ci")
    args = parser.parse_args()
    try:
        with args.matrix.open(encoding="utf-8") as source:
            document = yaml.load(source, Loader=UniqueKeyLoader)
        result = compile_matrix(
            document,
            args.workflow,
            pathlib.Path(__file__).resolve().parents[1] / "jobs",
        )
    except (OSError, yaml.YAMLError, MatrixError) as error:
        print(f"Invalid CI matrix: {error}", file=sys.stderr)
        return 2
    output_file = os.environ.get("GITHUB_OUTPUT")
    if output_file is None:
        print(json.dumps(result, indent=2))
    else:
        with open(output_file, "a", encoding="utf-8") as output:
            for phase, group_matrix in result.items():
                print(
                    f"{phase}={json.dumps(group_matrix, separators=(',', ':'))}",
                    file=output,
                )
                print(
                    f"has_{phase}={str(bool(group_matrix['include'])).lower()}",
                    file=output,
                )
    return 0


if __name__ == "__main__":
    sys.exit(main())
