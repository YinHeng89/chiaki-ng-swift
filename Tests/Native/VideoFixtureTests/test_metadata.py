import importlib.util
import json
from pathlib import Path
import types
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("fixture", Path(__file__).resolve().parents[3] / "Tools/VideoFixture/import.py")
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)

class MetadataTests(unittest.TestCase):
    def check_input(self, **changes):
        stream = dict(codec_name="hevc", pix_fmt="yuv420p10le", color_transfer="smpte2084",
                      color_primaries="bt2020", color_space="bt2020nc", width=1920, height=1080)
        stream.update(changes)
        with patch.object(fixture.subprocess, "run", return_value=types.SimpleNamespace(stdout=json.dumps({"streams": [stream]}))):
            return fixture.inspect("unused")
    def test_accepts_pq(self):
        self.assertEqual(self.check_input()["color_transfer"], "smpte2084")
    def test_rejects_sdr_and_hlg(self):
        for transfer in [None, "bt709", "arib-std-b67"]:
            with self.assertRaises(ValueError): self.check_input(color_transfer=transfer)
    def test_rejects_eight_bit(self):
        with self.assertRaises(ValueError): self.check_input(pix_fmt="yuv420p")
    def test_rejects_wrong_gamut(self):
        with self.assertRaises(ValueError): self.check_input(color_primaries="bt709")
    def test_rejects_oversized(self):
        with self.assertRaises(ValueError): self.check_input(width=8000)

if __name__ == "__main__": unittest.main()
