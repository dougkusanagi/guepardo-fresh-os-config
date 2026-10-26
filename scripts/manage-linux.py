"""Read-only inventory and explicit missing-app selection; standard library only."""
import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
LABELS = {"installed": "Instalado", "missing": "Faltando", "unknown": "Não identificado", "unavailable": "Indisponível no WSL"}


def load_catalog():
    apps = json.loads((ROOT / "catalog/linux-apps.json").read_text())
    ids = [a["id"] for a in apps]
    if len(ids) != len(set(ids)):
        raise ValueError("IDs duplicados no catálogo Linux")
    for app in apps:
        if not re.fullmatch(r"[a-z0-9-]+", app["id"]):
            raise ValueError("ID inválido")
        if any(d not in ids for d in app.get("dependsOn", [])):
            raise ValueError("Dependência desconhecida")
    return apps


def detect_distro():
    data = dict(line.split("=", 1) for line in Path("/etc/os-release").read_text().splitlines() if "=" in line)
    identity = (data.get("ID", "") + " " + data.get("ID_LIKE", "")).replace('"', '').split()
    if any(d in identity for d in ("ubuntu", "debian")):
        return "ubuntu"
    if any(d in identity for d in ("fedora", "nobara")):
        return "fedora"
    raise ValueError("Este gerenciador atende Ubuntu e Fedora/Nobara.")


def scan(apps, which=shutil.which, flatpaks=None, wsl=None):
    if wsl is None:
        wsl = bool(os.environ.get("WSL_DISTRO_NAME") or os.environ.get("WSL_INTEROP")) or "microsoft" in os.uname().release.lower()
    if flatpaks is None:
        flatpaks = set()
        if which("flatpak"):
            try:
                result = subprocess.run(["flatpak", "list", "--app", "--columns=application"], capture_output=True, text=True, timeout=15)
                flatpaks = set(result.stdout.splitlines()) if result.returncode == 0 else None
            except (OSError, subprocess.TimeoutExpired):
                flatpaks = None
    rows = []
    for app in apps:
        executable = all(any(which(c) for c in group) for group in app["checks"])
        installed = executable or (flatpaks is not None and app.get("flatpak") in flatpaks)
        status = "installed" if installed else "unavailable" if wsl and app.get("gui") else "unknown" if app.get("flatpak") and flatpaks is None else "missing"
        if app.get("packageOnly") and not installed:
            distro = detect_distro()
            package = app["packages"][distro]
            command = ["dpkg-query", "-W", "-f=${Status}", package] if distro == "ubuntu" else ["rpm", "-q", package]
            try:
                result = subprocess.run(command, capture_output=True, text=True, timeout=5)
                status = "installed" if result.returncode == 0 and (distro != "ubuntu" or "install ok installed" in result.stdout) else "missing"
            except (OSError, subprocess.TimeoutExpired):
                status = "unknown"
        # A node binary without an LTS version does not satisfy the Node LTS recipe.
        if app["id"] == "node-lts" and installed:
            try:
                version = subprocess.run(["node", "--version"], capture_output=True, text=True, timeout=5)
                if version.returncode or not re.match(r"^v(22|24)\.", version.stdout.strip()):
                    status = "missing"
            except (OSError, subprocess.TimeoutExpired):
                status = "unknown"
        rows.append(dict(app, status=status))
    return rows


def installation_plan(rows, ids):
    by_id = {a["id"]: a for a in rows}
    ordered, done, visiting = [], set(), set()
    def visit(id_):
        if id_ not in by_id:
            raise ValueError(f"Aplicativo desconhecido: {id_}")
        if id_ in visiting:
            raise ValueError("Ciclo de dependências no catálogo")
        if id_ in done:
            return
        app = by_id[id_]
        if app["status"] == "installed":
            return
        if app["status"] != "missing":
            raise ValueError(f"Não é possível instalar {app['name']}: {LABELS[app['status']]}")
        visiting.add(id_)
        for dependency in app.get("dependsOn", []):
            visit(dependency)
        visiting.remove(id_)
        done.add(id_)
        ordered.append(app)
    for id_ in ids:
        visit(id_)
    return ordered


def recipe(app, distro):
    if app.get("action"):
        return app["action"]
    if app.get("packages"):
        return ["apt_install" if distro == "ubuntu" else "dnf_install", app["packages"][distro]]
    return ["flatpak_install_app", app["flatpak"]]


def display(rows):
    for i, app in enumerate(rows, 1):
        print(f"{i:3}  {LABELS[app['status']]:22} {app['name']} ({app['id']})")


def main():
    parser = argparse.ArgumentParser(description="Consulte aplicativos e instale somente os que faltam.")
    parser.add_argument("--list", action="store_true")
    parser.add_argument("--missing", action="store_true")
    parser.add_argument("--installed", action="store_true")
    parser.add_argument("--json", action="store_true")
    parser.add_argument("--install-missing", action="store_true")
    parser.add_argument("--apps", default="", help="IDs separados por vírgula")
    parser.add_argument("--profiles", default="", help="cli,dev,web,desktop,games")
    parser.add_argument("--plan", action="store_true")
    parser.add_argument("--yes", action="store_true")
    parser.add_argument("--theme", choices=("light", "dark", "system"))
    # Internal bridge: emits argv as NUL-separated data; Bash never evaluates code.
    parser.add_argument("--recipe", nargs=2, metavar=("DISTRO", "ID"), help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.missing and args.installed:
        raise ValueError("Escolha --missing ou --installed, não ambos.")
    theme_path = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "guepardo/manager-theme.txt"
    theme = "system"
    if theme_path.exists():
        saved = theme_path.read_text().strip()
        if saved in ("light", "dark", "system"):
            theme = saved
    if args.theme:
        theme = args.theme
        theme_path.parent.mkdir(parents=True, exist_ok=True)
        theme_path.write_text(theme)
    apps = load_catalog()
    if args.recipe:
        distro, id_ = args.recipe
        if distro not in ("ubuntu", "fedora"):
            raise ValueError("Distribuição inválida")
        app = next((a for a in apps if a["id"] == id_), None)
        if app is None:
            raise ValueError(f"Aplicativo desconhecido: {id_}")
        # The first field carries dependency IDs for failure propagation in Bash.
        argv = [",".join(app.get("dependsOn", [])), *recipe(app, distro)]
        sys.stdout.buffer.write(b"\0".join(a.encode() for a in argv) + b"\0")
        return 0
    distro = detect_distro()
    wanted = [s.strip() for s in args.apps.split(",") if s.strip()]
    profiles = [s.strip() for s in args.profiles.split(",") if s.strip()]
    for id_ in wanted:
        if id_ not in {a["id"] for a in apps}:
            raise ValueError(f"Aplicativo desconhecido: {id_}")
    if set(profiles) - {a["profile"] for a in apps}:
        raise ValueError("Perfil desconhecido; use cli,dev,web,desktop,games.")
    # Common per-user tool directories must be checked even in an old terminal.
    os.environ["PATH"] = os.pathsep.join(str(Path.home() / p) for p in (".local/bin", ".cargo/bin", ".bun/bin")) + os.pathsep + os.environ.get("PATH", "")
    while True:
        rows = scan(apps)
        visible = [a for a in rows if (not wanted or a["id"] in wanted) and (not profiles or a["profile"] in profiles) and (not args.missing or a["status"] == "missing") and (not args.installed or a["status"] == "installed")]
        eligible = [a for a in visible if a["status"] == "missing"]
        if args.json:
            print(json.dumps(visible, ensure_ascii=False))
            return 0
        if args.list or args.missing or args.installed:
            display(visible)
            return 0
        if args.install_missing or wanted or args.plan:
            chosen = [a["id"] for a in eligible]
        else:
            heading = f"\nGuepardo / {sum(a['status']=='installed' for a in visible)} instalados · {len(eligible)} faltando"
            color = "34" if theme == "light" else "96" if theme == "dark" else "39"
            print(f"\033[{color}m{heading}\033[0m" if sys.stdout.isatty() and not os.environ.get("NO_COLOR") else heading)
            theme_label = {"light": "Claro", "dark": "Escuro", "system": "Sistema"}[theme]
            print(f"Tema: {theme_label} | C Claro / E Escuro / S Sistema")
            answer = input("1 Ver todos | 2 Escolher faltantes | 3 Todos os faltantes\n4 Ver instalados | R Atualizar | Q Sair\n> ").strip().lower()
            if answer == "q":
                return 0
            if answer in ("c", "e", "s"):
                theme = {"c": "light", "e": "dark", "s": "system"}[answer]
                theme_path.parent.mkdir(parents=True, exist_ok=True)
                theme_path.write_text(theme)
                continue
            if answer == "1":
                display(visible)
                continue
            if answer == "4":
                display([a for a in visible if a["status"] == "installed"])
                continue
            if answer == "r":
                continue
            if answer not in ("2", "3"):
                print("Escolha 1, 2, 3, R ou Q.")
                continue
            display(eligible)
            if answer == "3":
                chosen = [a["id"] for a in eligible]
            else:
                text = input("Números separados por espaço, T para todos, Enter para voltar: ").strip().lower()
                if not text:
                    continue
                if text == "t":
                    chosen = [a["id"] for a in eligible]
                else:
                    try:
                        indexes = [int(s) for s in text.replace(",", " ").split()]
                        if not indexes or any(i < 1 or i > len(eligible) for i in indexes):
                            raise ValueError()
                        chosen = [eligible[i-1]["id"] for i in indexes]
                    except ValueError:
                        print("Use os números exibidos na lista.")
                        continue
        plan = installation_plan(rows, chosen)
        if not plan:
            print("Nenhum aplicativo faltando nesta seleção. Nada foi instalado.")
            return 0
        print("\nAplicativos a instalar (incluindo dependências):")
        display(plan)
        if args.plan:
            return 0
        if not args.yes and input("Instalar esta seleção? [s/N] ").strip().lower() != "s":
            return 0
        code = subprocess.call(["bash", str(ROOT / "scripts/manage-linux-install.sh"), distro, *(a["id"] for a in plan)])
        if code == 0:
            verified = {a["id"]: a for a in scan(apps)}
            remaining = [a["name"] for a in plan if verified[a["id"]]["status"] != "installed"]
            if remaining:
                print("A instalação terminou, mas estes aplicativos ainda não foram detectados: " + ", ".join(remaining))
                code = 1
        if code:
            print("Há pendências. Consulte o log informado e repita a seleção; os aplicativos já instalados serão preservados.")
        else:
            print(f"{len(plan)} aplicativo(s) verificado(s) após a instalação.")
        return code


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (ValueError, OSError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
    except (EOFError, KeyboardInterrupt):
        print("\nOperação cancelada. Nenhuma nova instalação foi iniciada.", file=sys.stderr)
        sys.exit(130)
