import contextlib
import importlib.util
import io
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location(
    "compress_videos", Path(__file__).resolve().parents[1] / "scripts/compress-videos.py")
m = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = m  # dataclasses precisam do módulo registrado
spec.loader.exec_module(m)

HAS_FFMPEG = shutil.which("ffmpeg") and shutil.which("ffprobe")


def make_video(path: Path, seconds: int = 3, bitrate: str = "4M") -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y",
         "-f", "lavfi", "-i", f"testsrc2=size=320x240:rate=30:duration={seconds}",
         "-f", "lavfi", "-i", f"sine=duration={seconds}",
         "-c:v", "libx264", "-b:v", bitrate, "-c:a", "aac", "-shortest", str(path)],
        check=True,
    )


def run(*args: str) -> str:
    out = io.StringIO()
    with contextlib.redirect_stdout(out):
        m.main(list(args))
    return out.getvalue()


@unittest.skipUnless(HAS_FFMPEG, "ffmpeg/ffprobe não estão no PATH")
class CompressVideosTests(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp())
        self.src = self.tmp / "origem"
        self.dst = self.tmp / "destino"
        self.big = self.src / "A" / "Jogo Grande (U) [!].mp4"
        self.small = self.src / "B" / "Jogo Pequeno.mp4"
        make_video(self.big)
        make_video(self.small, seconds=1, bitrate="100k")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def compress(self):
        return run("compress", str(self.src), str(self.dst), "--preset", "veryfast",
                   "-j", "2", "--tamanho-minimo", "0.2")

    def test_compress_keeps_originals_and_structure(self):
        original = self.big.read_bytes()
        self.compress()
        out = self.dst / "A" / "Jogo Grande (U) [!].mp4"
        self.assertEqual(self.big.read_bytes(), original)
        self.assertLess(out.stat().st_size, len(original))
        p = m.probe(out)
        self.assertTrue(p and p.vcodec == "h264" and p.has_audio)
        self.assertLess(abs(p.duration - 3), 0.5)
        self.assertEqual((self.dst / "B" / "Jogo Pequeno.mp4").read_bytes(), self.small.read_bytes())
        self.assertEqual(list(self.dst.rglob("*.partial.mp4")), [])
        self.assertIn("Tudo certo", run("verify", str(self.src), str(self.dst)))

    def test_compress_resumes_without_redoing(self):
        self.compress()
        self.assertIn("2 pulado", self.compress())

    def test_rejects_destination_inside_source(self):
        with self.assertRaises(SystemExit):
            run("compress", str(self.src), str(self.src / "saida"))

    def test_verify_reports_missing_files(self):
        self.dst.mkdir()
        with self.assertRaises(SystemExit), contextlib.redirect_stdout(io.StringIO()):
            m.main(["verify", str(self.src), str(self.dst)])


if __name__ == "__main__":
    unittest.main()
