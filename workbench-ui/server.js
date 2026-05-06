import express from "express";
import cors from "cors";
import multer from "multer";
import AdmZip from "adm-zip";
import fs from "fs";
import path from "path";
import { spawn } from "child_process";
import crypto from "crypto";

const PORT = 5185;
const app = express();

app.use(cors());
app.use(express.json({ limit: "50mb" }));

const upload = multer({ storage: multer.memoryStorage() });

function sha256File(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function ensureDir(p) {
  fs.mkdirSync(p, { recursive: true });
}

function clearDir(p) {
  if (fs.existsSync(p)) fs.rmSync(p, { recursive: true, force: true });
  fs.mkdirSync(p, { recursive: true });
}

function copyDir(src, dest) {
  ensureDir(dest);
  for (const e of fs.readdirSync(src, { withFileTypes: true })) {
    const s = path.join(src, e.name);
    const d = path.join(dest, e.name);
    if (e.isDirectory()) copyDir(s, d);
    else fs.copyFileSync(s, d);
  }
}

function hasBundleFiles(p) {
  return fs.existsSync(path.join(p, "manifest.json")) &&
    fs.existsSync(path.join(p, "contract.json")) &&
    fs.existsSync(path.join(p, "version.json"));
}

function findBundleRoot(repoPath) {
  const candidates = [
    repoPath,
    path.join(repoPath, "contract_bundle_v1"),
    path.join(repoPath, "workbench_bundle"),
    path.join(repoPath, "bundle"),
    path.join(repoPath, "workbench", "workspace", "input", "contract")
  ];

  for (const c of candidates) {
    if (hasBundleFiles(c)) return c;
  }

  throw new Error("No Contract Registry bundle was found in that folder.");
}

function normalizeSingleNestedFolder(_inputRoot) {
  // Deprecated no-op. Imports now stage into temp and copy only the detected bundle root.
}

function validateBundle(root) {
  if (!hasBundleFiles(root)) {
    throw new Error("The selected source is missing manifest.json, contract.json, or version.json.");
  }

  let manifest;
  let contract;
  let version;

  try {
    manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
    contract = JSON.parse(fs.readFileSync(path.join(root, "contract.json"), "utf8"));
    version = JSON.parse(fs.readFileSync(path.join(root, "version.json"), "utf8"));
  } catch (err) {
    throw new Error("One of the bundle JSON files is invalid: " + err.message);
  }

  const policyDir = path.join(root, "overlays", "policy");
  const schemaDir = path.join(root, "overlays", "schema");

  const policy = fs.existsSync(policyDir)
    ? fs.readdirSync(policyDir).filter(x => x.endsWith(".json")).sort()
    : [];

  const schema = fs.existsSync(schemaDir)
    ? fs.readdirSync(schemaDir).filter(x => x.endsWith(".json")).sort()
    : [];

  return {
    contractKey: manifest.contract_key || contract.contract_key || "contract",
    versionLabel: manifest.version_label || version.version_label || "version",
    policyCount: policy.length,
    schemaCount: schema.length,
    hashes: {
      manifest: sha256File(path.join(root, "manifest.json")),
      contract: sha256File(path.join(root, "contract.json")),
      version: sha256File(path.join(root, "version.json"))
    }
  };
}

function importFolderIntoWorkspace(sourceRoot, workspace) {
  if (!fs.existsSync(sourceRoot)) throw new Error("That folder does not exist.");

  const actualSourceRoot = findBundleRoot(sourceRoot);
  const inputRoot = path.join(workspace, "input", "contract");

  if (path.resolve(actualSourceRoot).toLowerCase() === path.resolve(inputRoot).toLowerCase()) {
    throw new Error("That folder is already the active workspace input. Choose a separate source folder.");
  }

  ensureDir(path.join(workspace, "input"));
  clearDir(inputRoot);
  copyDir(actualSourceRoot, inputRoot);

  return {
    ok: true,
    token: "SOURCE_READY",
    inputRoot,
    summary: validateBundle(inputRoot)
  };
}

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, port: PORT });
});

app.post("/api/pick-folder", (req, res) => {
  const title = req.body?.title || "Choose folder";

  const ps = `
Add-Type -AssemblyName System.Windows.Forms
$d = New-Object System.Windows.Forms.FolderBrowserDialog
$d.Description = '${String(title).replaceAll("'", "''")}'
$d.ShowNewFolderButton = $true
$r = $d.ShowDialog()
if($r -eq [System.Windows.Forms.DialogResult]::OK){ Write-Output $d.SelectedPath }
`;

  const child = spawn("powershell.exe", [
    "-NoProfile",
    "-STA",
    "-ExecutionPolicy", "Bypass",
    "-Command", ps
  ], { windowsHide: false });

  let stdout = "";
  let stderr = "";

  child.stdout.on("data", d => stdout += d.toString());
  child.stderr.on("data", d => stderr += d.toString());

  child.on("close", code => {
    const selectedPath = stdout.trim();
    if (code !== 0) return res.status(400).json({ ok: false, error: stderr || "Folder picker failed." });
    if (!selectedPath) return res.json({ ok: false, error: "Folder selection cancelled." });
    return res.json({ ok: true, selectedPath });
  });
});

app.post("/api/import-zip", upload.single("bundle"), (req, res) => {
  let tempRoot = "";
  try {
    const workspace = req.body?.workspace;
    if (!workspace) throw new Error("Workspace is missing.");
    if (!req.file) throw new Error("No zip file selected.");

    tempRoot = path.join(workspace, "_tmp_import_" + Date.now().toString());
    clearDir(tempRoot);

    const zip = new AdmZip(req.file.buffer);
    zip.extractAllTo(tempRoot, true);

    const bundleRoot = findBundleRoot(tempRoot);
    const inputRoot = path.join(workspace, "input", "contract");

    ensureDir(path.join(workspace, "input"));
    clearDir(inputRoot);
    copyDir(bundleRoot, inputRoot);

    const result = {
      ok: true,
      token: "SOURCE_READY",
      inputRoot,
      summary: validateBundle(inputRoot)
    };

    fs.rmSync(tempRoot, { recursive: true, force: true });
    return res.json(result);
  } catch (err) {
    if (tempRoot && fs.existsSync(tempRoot)) {
      fs.rmSync(tempRoot, { recursive: true, force: true });
    }
    return res.status(400).json({ ok: false, error: err.message });
  }
});

app.post("/api/import-folder", (req, res) => {
  try {
    const { folderPath, workspace } = req.body ?? {};
    if (!folderPath || !workspace) throw new Error("Source folder or workspace is missing.");
    return res.json(importFolderIntoWorkspace(folderPath, workspace));
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

app.post("/api/import-repo", (req, res) => {
  try {
    const { repoPath, workspace } = req.body ?? {};
    if (!repoPath || !workspace) throw new Error("Repo path or workspace is missing.");
    const root = findBundleRoot(repoPath);
    return res.json(importFolderIntoWorkspace(root, workspace));
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

function safeTextFileList(root) {
  const skipDirs = new Set([
    ".git", "node_modules", "dist", "build", ".next", ".vite",
    "target", "bin", "obj", "__pycache__", ".venv", "venv",
    "proofs", "packets", "registry", "workbench"
  ]);

  const maxFiles = 750;
  const files = [];

  function walk(dir) {
    if (files.length >= maxFiles) return;

    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const full = path.join(dir, entry.name);
      const rel = path.relative(root, full).replaceAll("\\", "/");

      if (entry.isDirectory()) {
        if (skipDirs.has(entry.name)) continue;
        walk(full);
      } else if (entry.isFile()) {
        const stat = fs.statSync(full);
        if (stat.size > 1024 * 1024) continue;

        files.push({
          path: rel,
          bytes: stat.size,
          sha256: sha256File(full)
        });
      }
    }
  }

  walk(root);
  return files.sort((a, b) => a.path.localeCompare(b.path));
}

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, JSON.stringify(value, null, 2) + "\n", "utf8");
}

function repoNameFromPath(repoPath) {
  return path.basename(path.resolve(repoPath))
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, ".")
    .replace(/^\.+|\.+$/g, "") || "imported.repo";
}

function createBundleFromAnyRepo(repoPath, workspace) {
  if (!fs.existsSync(repoPath)) throw new Error("Repo folder does not exist.");

  const repoStat = fs.statSync(repoPath);
  if (!repoStat.isDirectory()) throw new Error("Selected repo path is not a folder.");

  const inputRoot = path.join(workspace, "input", "contract");
  const name = repoNameFromPath(repoPath);
  const contractKey = name + ".contract.v1";
  const versionLabel = "repo-scan-v1";
  const files = safeTextFileList(repoPath);
  const sourceDigest = crypto.createHash("sha256").update(JSON.stringify(files)).digest("hex");

  ensureDir(path.join(workspace, "input"));
  clearDir(inputRoot);
  ensureDir(path.join(inputRoot, "overlays", "policy"));
  ensureDir(path.join(inputRoot, "overlays", "schema"));

  writeJson(path.join(inputRoot, "manifest.json"), {
    bundle_schema: "contract_registry.repo_intake_bundle.v1",
    contract_key: contractKey,
    version_label: versionLabel,
    source_kind: "repo_scan",
    source_path: repoPath,
    source_file_count: files.length,
    source_digest_sha256: sourceDigest,
    required_files: ["contract.json", "version.json", "manifest.json"]
  });

  writeJson(path.join(inputRoot, "contract.json"), {
    contract_key: contractKey,
    title: name,
    description: "Generated from local repo intake.",
    source_kind: "repo_scan",
    source_path: repoPath
  });

  writeJson(path.join(inputRoot, "version.json"), {
    contract_key: contractKey,
    version_label: versionLabel,
    version_no: 1,
    status: "draft",
    source_digest_sha256: sourceDigest
  });

  writeJson(path.join(inputRoot, "source_inventory.json"), {
    source_path: repoPath,
    file_count: files.length,
    files
  });

  return {
    ok: true,
    token: "SOURCE_READY",
    inputRoot,
    summary: validateBundle(inputRoot),
    repoIntake: {
      sourcePath: repoPath,
      fileCount: files.length,
      sourceDigestSha256: sourceDigest
    }
  };
}

app.post("/api/import-any-repo", (req, res) => {
  try {
    const { repoPath, workspace } = req.body ?? {};
    if (!repoPath || !workspace) throw new Error("Repo path or workspace is missing.");
    return res.json(createBundleFromAnyRepo(repoPath, workspace));
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});
app.post("/api/open-path", (req, res) => {
  try {
    const targetPath = req.body?.targetPath;
    if (!targetPath) throw new Error("No path provided.");
    if (!fs.existsSync(targetPath)) throw new Error("That path does not exist yet.");

    const child = spawn("explorer.exe", [targetPath], { windowsHide: true, detached: true });
    child.unref();

    return res.json({ ok: true });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

app.post("/api/create-upload-bundle", (req, res) => {
  try {
    const exportDir = req.body?.exportDir;
    if (!exportDir || !fs.existsSync(exportDir)) throw new Error("No export folder exists yet.");

    const runId = path.basename(exportDir);
    const outputRoot = path.resolve(exportDir, "..", "..");
    const uploadRoot = path.join(outputRoot, "upload_bundles");
    ensureDir(uploadRoot);

    const zipPath = path.join(uploadRoot, runId + ".contract-upload.zip");
    if (fs.existsSync(zipPath)) fs.rmSync(zipPath, { force: true });

    const zip = new AdmZip();
    zip.addLocalFolder(exportDir);
    zip.writeZip(zipPath);

    return res.json({
      ok: true,
      zipPath,
      zipSha256: sha256File(zipPath)
    });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});

app.post("/api/run", (req, res) => {
  const { repoRoot, workspace } = req.body ?? {};
  if (!repoRoot || !workspace) return res.status(400).json({ error: "Repo root or workspace is missing." });

  const scriptPath = path.join(repoRoot, "workbench", "scripts", "_RUN_workbench_full_pipeline_v1.ps1");

  const ps = spawn("powershell.exe", [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File", scriptPath,
    "-RepoRoot", repoRoot,
    "-Workspace", workspace
  ], { windowsHide: true });

  res.writeHead(200, {
    "Content-Type": "text/plain; charset=utf-8",
    "Transfer-Encoding": "chunked",
    "Cache-Control": "no-cache"
  });

  ps.stdout.on("data", d => res.write(d.toString()));
  ps.stderr.on("data", d => res.write("ERROR: " + d.toString()));

  ps.on("error", err => {
    res.write("ERROR: " + err.message + "\n");
    res.end();
  });

  ps.on("close", code => {
    res.write("\nEXIT_CODE:" + String(code) + "\n");
    res.end();
  });
});

const server = app.listen(PORT, () => {
  console.log("WORKBENCH_BRIDGE_READY http://localhost:" + PORT);
});

server.on("error", err => {
  if (err.code === "EADDRINUSE") {
    console.error("WORKBENCH_BRIDGE_PORT_IN_USE:" + PORT);
    process.exit(1);
  }
  console.error(err);
  process.exit(1);
});
