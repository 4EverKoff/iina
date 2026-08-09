import { mkdir, readFile, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const manifest = JSON.parse(await readFile(resolve(root, "Info.json"), "utf8"));
const buildDir = resolve(root, "build");
const artifact = resolve(buildDir, `Xtream-Player-${manifest.version}.iinaplgz`);

await rm(buildDir, { recursive: true, force: true });
await mkdir(buildDir, { recursive: true });

const result = spawnSync(
  "/usr/bin/zip",
  ["-q", "-r", artifact, "Info.json", "README.md", "dist", "ui"],
  { cwd: root, stdio: "inherit" }
);
if (result.status !== 0) throw new Error(`zip failed with status ${result.status}`);

console.log(artifact);

