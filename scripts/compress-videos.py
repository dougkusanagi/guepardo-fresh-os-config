"""CLI para analisar e compactar vídeos mantendo a compatibilidade (MP4, H.264 e AAC).

Os originais nunca são alterados: o resultado vai para uma pasta separada,
com a mesma estrutura de subpastas e os mesmos nomes de arquivo.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass
from pathlib import Path

__version__ = "0.1.0"

VIDEO_EXTS = {".mp4", ".mkv", ".avi", ".webm", ".mov", ".m4v"}
PARTIAL_SUFFIX = ".partial.mp4"
_print_lock = threading.Lock()


def log(msg: str) -> None:
    with _print_lock:
        print(msg, flush=True)


def fmt_size(n: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if abs(n) < 1000 or unit == "GB":
            return f"{n:.1f} {unit}" if unit != "B" else f"{int(n)} B"
        n /= 1000
    return f"{n:.1f} GB"


def require_tools() -> None:
    missing = [t for t in ("ffmpeg", "ffprobe") if shutil.which(t) is None]
    if missing:
        sys.exit(
            f"Não encontrei {', '.join(missing)} no PATH. "
            "Instale o FFmpeg (por exemplo: scoop install ffmpeg) e tente de novo."
        )


def find_videos(root: Path) -> list[Path]:
    return sorted(
        p
        for p in root.rglob("*")
        if p.is_file()
        and p.suffix.lower() in VIDEO_EXTS
        and not p.name.endswith(PARTIAL_SUFFIX)
    )


@dataclass
class Probe:
    duration: float
    vcodec: str | None
    width: int | None
    height: int | None
    has_audio: bool


def probe(path: Path) -> Probe | None:
    """Lê os metadados com ffprobe. Retorna None se o arquivo não for um vídeo válido."""
    r = subprocess.run(
        ["ffprobe", "-v", "error", "-print_format", "json",
         "-show_format", "-show_streams", str(path)],
        capture_output=True, text=True, encoding="utf-8", errors="replace",
    )
    if r.returncode != 0:
        return None
    try:
        data = json.loads(r.stdout)
    except json.JSONDecodeError:
        return None
    streams = data.get("streams", [])
    video = next((s for s in streams if s.get("codec_type") == "video"), None)
    if video is None:
        return None
    try:
        duration = float(data.get("format", {}).get("duration", 0))
    except ValueError:
        duration = 0.0
    return Probe(
        duration=duration,
        vcodec=video.get("codec_name"),
        width=video.get("width"),
        height=video.get("height"),
        has_audio=any(s.get("codec_type") == "audio" for s in streams),
    )


# ---------------------------------------------------------------- codificação

@dataclass
class EncodeOptions:
    codec: str = "h264"
    crf: int | None = None
    preset: str = "slow"
    audio_bitrate: str = "96k"
    max_height: int | None = None

    @property
    def effective_crf(self) -> int:
        if self.crf is not None:
            return self.crf
        return 26 if self.codec == "h264" else 28


def ffmpeg_args(src: Path, dst: Path, opts: EncodeOptions) -> list[str]:
    # Dimensões pares são exigidas por yuv420p; limite de altura é opcional.
    scale = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    if opts.max_height:
        scale = f"scale=-2:'min({opts.max_height},trunc(ih/2)*2)'"
    args = ["ffmpeg", "-v", "error", "-nostdin", "-y", "-i", str(src),
            "-map", "0:v:0", "-map", "0:a:0?", "-vf", scale]
    if opts.codec == "h264":
        args += ["-c:v", "libx264", "-profile:v", "high"]
    else:
        # hvc1 é a marcação mais compatível de HEVC em MP4.
        args += ["-c:v", "libx265", "-tag:v", "hvc1", "-x265-params", "log-level=error"]
    args += ["-preset", opts.preset, "-crf", str(opts.effective_crf),
             "-pix_fmt", "yuv420p",
             "-c:a", "aac", "-b:a", opts.audio_bitrate,
             "-map_metadata", "-1", "-movflags", "+faststart",
             "-f", "mp4", str(dst)]
    return args


@dataclass
class Result:
    src: Path
    dst: Path
    status: str  # "compactado", "copiado", "pulado", "erro"
    before: int = 0
    after: int = 0
    message: str = ""


def process_file(src: Path, dst: Path, opts: EncodeOptions, min_size: int,
                 min_saving: float, force: bool, dry_run: bool) -> Result:
    before = src.stat().st_size
    if dst.exists() and not force:
        return Result(src, dst, "pulado", before, dst.stat().st_size, "já existe no destino")
    if dry_run:
        action = "copiar" if before < min_size else "compactar"
        return Result(src, dst, "pulado", before, 0, f"simulação: iria {action}")

    dst.parent.mkdir(parents=True, exist_ok=True)

    if before < min_size:
        shutil.copy2(src, dst)
        return Result(src, dst, "copiado", before, before, "arquivo pequeno, copiado sem mudança")

    original = probe(src)
    if original is None:
        shutil.copy2(src, dst)
        return Result(src, dst, "copiado", before, before,
                      "não consegui ler o vídeo; copiei o original sem mudança")

    partial = dst.with_name(dst.stem + PARTIAL_SUFFIX)
    r = subprocess.run(ffmpeg_args(src, partial, opts), capture_output=True,
                       text=True, encoding="utf-8", errors="replace")
    encoded = probe(partial) if r.returncode == 0 and partial.exists() else None
    ok = encoded is not None and (
        original.duration == 0 or abs(encoded.duration - original.duration) <= 1.0
    )
    if not ok:
        partial.unlink(missing_ok=True)
        shutil.copy2(src, dst)
        detail = (r.stderr.strip().splitlines() or ["duração diferente do original"])[-1]
        return Result(src, dst, "copiado", before, before,
                      f"a conversão falhou ({detail}); copiei o original sem mudança")

    after = partial.stat().st_size
    if after > before * (1 - min_saving):
        partial.unlink()
        shutil.copy2(src, dst)
        return Result(src, dst, "copiado", before, before,
                      "a versão nova não ficou menor; copiei o original")

    os.replace(partial, dst)
    return Result(src, dst, "compactado", before, after)


def dest_for(src: Path, src_root: Path, dst_root: Path) -> Path:
    # Mesmo nome e subpastas; extensão .mp4, aceita por praticamente todo player.
    return (dst_root / src.relative_to(src_root)).with_suffix(".mp4")


def check_dirs(src: Path, dst: Path) -> None:
    if not src.is_dir():
        sys.exit(f"A pasta de origem não existe: {src}")
    s, d = src.resolve(), dst.resolve()
    if s == d or s in d.parents or d in s.parents:
        sys.exit("A pasta de destino precisa ficar fora da pasta de origem (e vice-versa), "
                 "para os originais continuarem intactos.")


# ------------------------------------------------------------------- comandos

def cmd_scan(args: argparse.Namespace) -> None:
    root = Path(args.origem)
    if not root.is_dir():
        sys.exit(f"A pasta não existe: {root}")
    files = find_videos(root)
    if not files:
        log("Nenhum vídeo encontrado.")
        return
    sizes = [f.stat().st_size for f in files]
    total = sum(sizes)
    log(f"{len(files)} vídeos, {fmt_size(total)} no total "
        f"(média {fmt_size(total / len(files))}).")
    buckets = [("abaixo de 5 MB", 0, 5e6), ("5 a 15 MB", 5e6, 15e6),
               ("acima de 15 MB", 15e6, float("inf"))]
    for label, lo, hi in buckets:
        sel = [s for s in sizes if lo <= s < hi]
        log(f"  {label}: {len(sel)} arquivos, {fmt_size(sum(sel))}")
    if args.codecs:
        counts: dict[str, int] = {}
        for f in files:
            p = probe(f)
            key = f"{p.vcodec} {p.width}x{p.height}" if p else "ilegível"
            counts[key] = counts.get(key, 0) + 1
        log("Codecs e resoluções:")
        for k, v in sorted(counts.items(), key=lambda kv: -kv[1]):
            log(f"  {k}: {v}")


def encode_opts(args: argparse.Namespace) -> EncodeOptions:
    return EncodeOptions(codec=args.codec, crf=args.crf, preset=args.preset,
                         audio_bitrate=args.audio_bitrate, max_height=args.max_height)


def cmd_estimate(args: argparse.Namespace) -> None:
    require_tools()
    root = Path(args.origem)
    if not root.is_dir():
        sys.exit(f"A pasta não existe: {root}")
    files = sorted(find_videos(root), key=lambda f: f.stat().st_size)
    if not files:
        sys.exit("Nenhum vídeo encontrado.")
    n = max(1, min(args.amostra, len(files)))
    # Divide os arquivos em n grupos por tamanho e testa o do meio de cada grupo.
    groups = [files[i * len(files) // n:(i + 1) * len(files) // n] for i in range(n)]
    groups = [g for g in groups if g]
    opts = encode_opts(args)
    log(f"Convertendo {len(groups)} arquivos de amostra com {opts.codec}, "
        f"CRF {opts.effective_crf}. Os originais não são alterados.")
    with tempfile.TemporaryDirectory(prefix="compress-videos-") as tmp:
        def run(i_group):
            i, g = i_group
            sample = g[len(g) // 2]
            res = process_file(sample, Path(tmp) / f"{i}.mp4", opts, 0, 0.0, True, False)
            ratio = res.after / res.before if res.before else 1.0
            log(f"  {sample.name}: {fmt_size(res.before)} → {fmt_size(res.after)} "
                f"({(ratio - 1) * 100:+.0f}%)")
            return sum(f.stat().st_size for f in g), ratio
        with ThreadPoolExecutor(args.jobs) as ex:
            parts = list(ex.map(run, enumerate(groups)))
    before = sum(b for b, _ in parts)
    after = sum(b * r for b, r in parts)
    log(f"\nEstimativa: {fmt_size(before)} → {fmt_size(after)} "
        f"(economia de {fmt_size(before - after)}, {(1 - after / before) * 100:.0f}%).")


def cmd_compress(args: argparse.Namespace) -> None:
    require_tools()
    src_root, dst_root = Path(args.origem), Path(args.destino)
    check_dirs(src_root, dst_root)
    files = find_videos(src_root)
    if not files:
        sys.exit("Nenhum vídeo encontrado na origem.")
    if dst_root.exists():
        for leftover in dst_root.rglob("*" + PARTIAL_SUFFIX):
            leftover.unlink()  # sobras de uma execução interrompida
    opts = encode_opts(args)
    min_size = int(args.tamanho_minimo * 1_000_000)
    log(f"{len(files)} vídeos. Codec {opts.codec}, CRF {opts.effective_crf}, "
        f"{args.jobs} em paralelo. Destino: {dst_root}")
    total = len(files)
    counter = {"n": 0}

    def run(src: Path) -> Result:
        try:
            res = process_file(src, dest_for(src, src_root, dst_root), opts, min_size,
                               args.economia_minima / 100, args.force, args.dry_run)
        except OSError as e:
            res = Result(src, dest_for(src, src_root, dst_root), "erro",
                         message=f"erro de arquivo: {e}")
        with _print_lock:
            counter["n"] += 1
            line = f"[{counter['n']}/{total}] {src.relative_to(src_root)}: "
            if res.status == "compactado":
                line += (f"{fmt_size(res.before)} → {fmt_size(res.after)} "
                         f"({(res.after / res.before - 1) * 100:+.0f}%)")
            else:
                line += f"{res.status}, {res.message}"
            print(line, flush=True)
        return res

    try:
        with ThreadPoolExecutor(args.jobs) as ex:
            results = list(ex.map(run, files))
    except KeyboardInterrupt:
        sys.exit("\nInterrompido. Rode o mesmo comando de novo para continuar de onde parou.")

    done = [r for r in results if r.status != "pulado" or r.after]
    before = sum(r.before for r in done)
    after = sum(r.after for r in done)
    by_status: dict[str, int] = {}
    for r in results:
        by_status[r.status] = by_status.get(r.status, 0) + 1
    log("\nResumo: " + ", ".join(f"{v} {k}" for k, v in sorted(by_status.items())))
    if before and not args.dry_run:
        log(f"Tamanho: {fmt_size(before)} → {fmt_size(after)} "
            f"(economia de {fmt_size(before - after)}, {(1 - after / before) * 100:.0f}%).")
    if by_status.get("erro"):
        sys.exit(1)


def cmd_verify(args: argparse.Namespace) -> None:
    require_tools()
    src_root, dst_root = Path(args.origem), Path(args.destino)
    check_dirs(src_root, dst_root)
    files = find_videos(src_root)
    problems = 0
    for src in files:
        dst = dest_for(src, src_root, dst_root)
        rel = src.relative_to(src_root)
        if not dst.exists():
            log(f"Falta no destino: {rel}")
            problems += 1
            continue
        p = probe(dst)
        if p is None:
            log(f"Vídeo ilegível no destino: {rel}")
            problems += 1
    if problems:
        sys.exit(f"\n{problems} problema(s) em {len(files)} vídeos. "
                 "Rode o comando compress de novo para refazer os que faltam.")
    log(f"Tudo certo: os {len(files)} vídeos existem no destino e abrem normalmente.")


# ----------------------------------------------------------------------- main

def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="compress-videos",
        description="Analisa e compacta vídeos para outra pasta, mantendo os originais.",
    )
    p.add_argument("--version", action="version", version=f"%(prog)s {__version__}")
    sub = p.add_subparsers(dest="comando", required=True, metavar="comando")

    s = sub.add_parser("scan", help="mostra quantidade, tamanho e distribuição dos vídeos")
    s.add_argument("origem", help="pasta com os vídeos")
    s.add_argument("--codecs", action="store_true",
                   help="também lista codecs e resoluções (mais lento)")
    s.set_defaults(func=cmd_scan)

    def add_encode(sp: argparse.ArgumentParser) -> None:
        sp.add_argument("--codec", choices=["h264", "h265"], default="h264",
                        help="h264 (padrão, mais compatível) ou h265 (menor, mais pesado de tocar)")
        sp.add_argument("--crf", type=int,
                        help="qualidade: menor = melhor e maior (padrão: 26 em h264, 28 em h265)")
        sp.add_argument("--preset", default="slow",
                        help="velocidade do codificador: veryfast, fast, medium, slow (padrão)…")
        sp.add_argument("--audio-bitrate", default="96k", help="taxa do áudio AAC (padrão: 96k)")
        sp.add_argument("--max-height", type=int,
                        help="reduz a altura do vídeo até este valor (ex.: 480); padrão: mantém")
        sp.add_argument("-j", "--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2),
                        help="conversões em paralelo (padrão: metade dos núcleos)")

    e = sub.add_parser("estimate", help="converte uma amostra e estima a economia total")
    e.add_argument("origem", help="pasta com os vídeos")
    e.add_argument("--amostra", type=int, default=20, help="quantos arquivos testar (padrão: 20)")
    add_encode(e)
    e.set_defaults(func=cmd_estimate)

    c = sub.add_parser("compress", help="compacta os vídeos para outra pasta, sem tocar nos originais")
    c.add_argument("origem", help="pasta com os vídeos originais")
    c.add_argument("destino", help="pasta nova onde ficam os vídeos compactados")
    add_encode(c)
    c.add_argument("--tamanho-minimo", type=float, default=1.0, metavar="MB",
                   help="arquivos menores que isto são só copiados (padrão: 1 MB)")
    c.add_argument("--economia-minima", type=float, default=5.0, metavar="PCT",
                   help="se a economia for menor que isto, copia o original (padrão: 5%%)")
    c.add_argument("--force", action="store_true",
                   help="refaz arquivos que já existem no destino")
    c.add_argument("--dry-run", action="store_true", help="só mostra o que faria")
    c.set_defaults(func=cmd_compress)

    v = sub.add_parser("verify", help="confere se todos os vídeos existem no destino e abrem")
    v.add_argument("origem", help="pasta com os vídeos originais")
    v.add_argument("destino", help="pasta com os vídeos compactados")
    v.set_defaults(func=cmd_verify)
    return p


def main(argv: list[str] | None = None) -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
    args = build_parser().parse_args(argv)
    if getattr(args, "jobs", 1) < 1:
        sys.exit("--jobs precisa ser 1 ou mais.")
    args.func(args)


if __name__ == "__main__":
    main()
