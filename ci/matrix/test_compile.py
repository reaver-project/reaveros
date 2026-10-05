import copy
import pathlib
import unittest

import yaml
from compile import MatrixError, UniqueKeyLoader, compile_matrix

matrix_file = pathlib.Path(__file__).resolve().parents[1] / "matrix.yaml"


class MatrixCompilerTests(unittest.TestCase):
    def setUp(self):
        with matrix_file.open(encoding="utf-8") as source:
            self.matrix = yaml.load(source, Loader=UniqueKeyLoader)

    def test_current_matrix_has_independent_jobs_and_debug_release_image_chains(self):
        result = compile_matrix(self.matrix, "ci")
        independent = result["standalone"]["include"]
        self.assertEqual(
            [group["name"] for group in independent],
            ["Check build-system dependencies", "Unit tests"],
        )
        self.assertEqual(len(independent[0]["job_matrix"]["include"]), 1)
        unit_tests = independent[1]["job_matrix"]["include"]
        self.assertEqual(len(unit_tests), 2)
        self.assertEqual(
            {job["tags"]["configuration"] for job in unit_tests},
            {"debug", "release"},
        )
        images = result["producer"]["include"][0]["job_matrix"]["include"]
        smokes = result["consumer"]["include"][0]["job_matrix"]["include"]
        self.assertEqual(len(images), 2)
        self.assertEqual(len(smokes), 2)
        by_configuration = {job["tags"]["configuration"]: job for job in images}
        self.assertEqual(set(by_configuration), {"debug", "release"})
        self.assertEqual(len({job["artifact_output"] for job in images}), 2)
        for smoke in smokes:
            configuration = smoke["tags"]["configuration"]
            image = by_configuration[configuration]
            self.assertEqual(
                image["name"], f"Build image (uefi-efipart-amd64-{configuration})"
            )
            self.assertEqual(image["artifact_output"], smoke["artifact_input"])
            self.assertEqual(smoke["invoke"], "boot-smoke")
            self.assertEqual(smoke["tags"]["machine"], "q35")
            self.assertEqual(smoke["runner_class"], "validation-medium")

    def test_each_row_expands_only_its_own_dimensions_and_shares_producers(self):
        row = self.matrix["workflows"]["ci"][1]
        row["firmware"] = ["ovmf", "other"]
        row["machine"] = ["q35", "virt"]
        result = compile_matrix(self.matrix, "ci")
        images = result["producer"]["include"][0]["job_matrix"]["include"]
        smoke = result["consumer"]["include"][0]["job_matrix"]["include"]
        self.assertEqual(len(images), 2)
        self.assertEqual(len(smoke), 8)
        self.assertEqual(
            {job["artifact_input"] for job in smoke},
            {job["artifact_output"] for job in images},
        )
        for image in images:
            consumers = [
                job for job in smoke
                if job["artifact_input"] == image["artifact_output"]
            ]
            self.assertEqual(len(consumers), 4)
            self.assertEqual(
                {job["tags"]["configuration"] for job in consumers},
                {image["tags"]["configuration"]},
            )

    def test_new_job_type_uses_metadata_without_a_compiler_case(self):
        self.matrix["jobs"]["api-test"] = {
            "name": "System API test",
            "invoke": "run-unit-tests",
            "axes": ["architecture", "language"],
            "phase": "standalone",
            "runner_class": "validation-medium",
        }
        self.matrix["workflows"]["ci"].append(
            {"jobs": ["api-test"], "architecture": "amd64", "language": ["cpp", "rust"]}
        )
        result = compile_matrix(self.matrix, "ci")
        jobs = next(
            group["job_matrix"]["include"]
            for group in result["standalone"]["include"]
            if group["name"] == "System API test"
        )
        self.assertEqual([job["tags"]["language"] for job in jobs], ["cpp", "rust"])

    def test_workflow_can_omit_entire_phases(self):
        self.matrix["workflows"]["ci"] = self.matrix["workflows"]["ci"][:1]
        result = compile_matrix(self.matrix, "ci")
        self.assertEqual(len(result["standalone"]["include"]), 2)
        self.assertEqual(result["producer"], {"include": []})
        self.assertEqual(result["consumer"], {"include": []})

    def test_rejects_invalid_references_and_duplicate_dimensions(self):
        invalid = copy.deepcopy(self.matrix)
        invalid["workflows"]["ci"][0]["jobs"] = ["unknown"]
        with self.assertRaisesRegex(MatrixError, "unknown names"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["workflows"]["ci"][0]["architecture"] = ["amd64", "amd64"]
        with self.assertRaisesRegex(MatrixError, "repeats architecture"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        del invalid["workflows"]["ci"][1]["loader"]
        with self.assertRaisesRegex(MatrixError, "job image needs tag loader"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        del invalid["workflows"]["ci"][1]["configuration"]
        with self.assertRaisesRegex(MatrixError, "job image needs tag configuration"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["jobs"]["smoke"]["consumes"] = "serial"
        with self.assertRaisesRegex(MatrixError, "wrong producer artifact"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["workflows"]["ci"][0]["language"] = ["cpp", "rust"]
        with self.assertRaisesRegex(MatrixError, "unused tags"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["workflows"]["ci"][1]["firmware"] = [
            f"fw-{index}" for index in range(65)
        ]
        with self.assertRaisesRegex(MatrixError, "64-way expansion budget"):
            compile_matrix(invalid, "ci")

    def test_rejects_duplicate_yaml_keys(self):
        with self.assertRaisesRegex(MatrixError, "duplicate YAML key"):
            yaml.load("jobs: {}\njobs: {}\n", Loader=UniqueKeyLoader)

        with self.assertRaisesRegex(MatrixError, "unhashable YAML key"):
            yaml.load("? [a, b]\n: value\n", Loader=UniqueKeyLoader)

    def test_rejects_malformed_job_metadata(self):
        invalid = copy.deepcopy(self.matrix)
        invalid["jobs"]["smoke"]["needs"] = ["image"]
        with self.assertRaisesRegex(MatrixError, "unknown job"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["jobs"]["smoke"]["consumes"] = ["image"]
        with self.assertRaisesRegex(MatrixError, "unknown artifact"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["jobs"]["smoke"]["runner_class"] = ["validation-medium"]
        with self.assertRaisesRegex(MatrixError, "unknown runner class"):
            compile_matrix(invalid, "ci")

        invalid = copy.deepcopy(self.matrix)
        invalid["jobs"]["smoke"]["name"] = "Build image"
        with self.assertRaisesRegex(MatrixError, "repeats display name"):
            compile_matrix(invalid, "ci")

    def test_rejects_missing_job_script(self):
        with self.assertRaisesRegex(MatrixError, "missing script"):
            compile_matrix(self.matrix, "ci", pathlib.Path(__file__).parent)


if __name__ == "__main__":
    unittest.main()
