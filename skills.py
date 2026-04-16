#!/usr/bin/env python3
"""Clone and pin skill repos listed in skills.yaml."""

import argparse
import os
import shutil
import subprocess
import yaml

SKILLS_DIR = os.path.join(os.path.dirname(__file__), ".skills")
SKILLS_IN_YAML = os.path.join(os.path.dirname(__file__), "skills.in.yaml")
SKILLS_YAML = os.path.join(os.path.dirname(__file__), "skills.yaml")


def load_skills():
    with open(SKILLS_IN_YAML) as f:
        inputs = yaml.safe_load(f)
    with open(SKILLS_YAML) as f:
        locks = yaml.safe_load(f) or {}
    merged = {}
    for name, sk in inputs.items():
        sk["commit"] = locks.get(name, "")
        merged[name] = sk
    return merged


def save_skills(skills):
    locks = {name: sk["commit"] for name, sk in skills.items()}
    with open(SKILLS_YAML, "w") as f:
        yaml.dump(locks, f, default_flow_style=False, sort_keys=False)


def git(*args, cwd=None):
    return subprocess.run(["git", *args], cwd=cwd, check=True,
                          capture_output=True, text=True)


def clone(args):
    os.makedirs(SKILLS_DIR, exist_ok=True)
    for name, sk in load_skills().items():
        d = os.path.join(SKILLS_DIR, sk.get("dir", name))
        if os.path.isdir(os.path.join(d, ".git")):
            print(f"{name}: fetching origin/{sk['ref']}")
            git("fetch", "origin", sk["ref"], cwd=d)
        else:
            print(f"{name}: cloning {sk['repo']} -> {d}")
            git("clone", sk["repo"], d)
        print(f"{name}: checkout {sk['commit']}")
        git("checkout", sk["commit"], cwd=d)


def freeze(args):
    skills = load_skills()
    changed = False
    for name, sk in skills.items():
        out = git("ls-remote", sk["repo"], f"refs/heads/{sk['ref']}")
        parts = out.stdout.split()
        if not parts:
            print(f"{name}: ref '{sk['ref']}' not found on remote")
            continue
        new = parts[0]
        if new == sk["commit"]:
            print(f"{name}: already at latest {new[:12]}")
        else:
            print(f"{name}: {sk['commit'][:12]} -> {new[:12]}")
            sk["commit"] = new
            changed = True
    if changed:
        save_skills(skills)


def install(args):
    if getattr(args, "global"):
        claude_skills = os.path.join(os.path.expanduser("~"), ".claude", "skills")
    else:
        claude_skills = os.path.join(os.path.dirname(__file__), ".claude", "skills")
    os.makedirs(claude_skills, exist_ok=True)
    for name, sk in load_skills().items():
        repo_dir = os.path.join(SKILLS_DIR, sk.get("dir", name))
        skills_src = os.path.join(repo_dir, "skills")
        if not os.path.isdir(skills_src):
            print(f"{name}: no skills/ directory found")
            continue
        for entry in os.listdir(skills_src):
            src = os.path.join(skills_src, entry)
            if not os.path.isfile(os.path.join(src, "SKILL.md")):
                continue
            dest = os.path.join(claude_skills, entry)
            if os.path.islink(dest) or os.path.exists(dest):
                shutil.rmtree(dest) if os.path.isdir(dest) else os.remove(dest)
            shutil.copytree(src, dest)
            print(f"  {entry}: installed")


def clean(args):
    for name, sk in load_skills().items():
        d = os.path.join(SKILLS_DIR, sk.get("dir", name))
        if os.path.isdir(d):
            print(f"{name}: removing {d}")
            shutil.rmtree(d)
        else:
            print(f"{name}: {d} not present")


if __name__ == "__main__":
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(required=True)
    sub.add_parser("clone", help="clone/fetch all skills").set_defaults(fn=clone)
    sub.add_parser("freeze", help="update commits to latest").set_defaults(fn=freeze)
    install_p = sub.add_parser("install-skills", help="copy skills into .claude/skills")
    install_p.add_argument("--global", dest="global", action="store_true",
                           help="install into ~/.claude/skills instead of .claude/skills")
    install_p.set_defaults(fn=install)
    sub.add_parser("clean", help="remove cloned dirs").set_defaults(fn=clean)
    args = p.parse_args()
    args.fn(args)
