import express from "express";
import cors from "cors";
import multer from "multer";
import AdmZip from "adm-zip";
import fs from "fs";
import path from "path";
import { spawn } from "child_process";
import crypto from "crypto";

const PORT = 5175;
const app = express();

app.use(cors());
app.use(express.json({ limit: "25mb" }));

const upload = multer({ storage: multer.memoryStorage() });

function sha256File(filePath) {
  const bytes = fs.readFileSync(filePath);
  return crypto.createHash("sha256").update(bytes).digest("hex");
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function clearDir(dirPath) {
  if (fs.existsSync(dirPath)) {
    fs.rmSync(dirPath, { recursive: true, force: true });
  }
  fs.mkdirSync(dirPath, { recursive: true });
}

function copyDir(src, dest) {
  ensureDir(dest);

  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function normalizeExtractedRoot(inputRoot) {
  const entries = fs.readdirSync(inputRoot, { withFileTypes: true });
  const dirs = entries.filter((x) => x.isDirectory());
  const files = entries.filter((x) => x.isFile());

  if (files.length === 0 && dirs.length === 1) {
    const nested = path.join(inputRoot, dirs[0].name);

    for (const name of fs.readdirSync(nested)) {
      fs.renameSync(path.join(nested, name), path.join(inputRoot, name));
    }

    fs.rmSync(nested, { recursive: true, force: true });
  }
}

function findRepoBundleRoot(repoPath) {
  const candidates = [
    repoPath,
    path.join(repoPath, "workbench_bundle"),
    path.join(repoPath, "contract_bundle_v1"),
    path.join(repoPath, "bundle"),
    path.join(repoPath, "workbench", "workspace", "input", "contract")
  ];

  for (const candidate of candidates) {
    if (
      fs.existsSync(path.join(candidate, "manifest.json")) &&
      fs.existsSync(path.join(candidate, "contract.json")) &&
      fs.existsSync(path.join(candidate, "version.json"))
    ) {
      return candidate;
    }
  }

  throw new Error("IMPORT_FAIL_REPO_BUNDLE_NOT_FOUND");
}

function validateImportedBundle(bundleRoot) {
  const manifestPath = path.join(bundleRoot, "manifest.json");
  const contractPath = path.join(bundleRoot, "contract.json");
  const versionPath = path.join(bundleRoot, "version.json");

  const policyDir = path.join(bundleRoot, "overlays", "policy");
  const schemaDir = path.join(bundleRoot, "overlays", "schema");

  for (const requiredPath of [manifestPath, contractPath, versionPath]) {
    if (!fs.existsSync(requiredPath)) {
      throw new Error("IMPORT_FAIL_MISSING_FILE: " + requiredPath);
    }
  }

  let manifest;
  let contract;
  let version;

  try {
    manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
    contract = JSON.parse(fs.readFileSync(contractPath, "utf8"));
    version = JSON.parse(fs.readFileSync(versionPath, "utf8"));
  } catch (err) {
    throw new Error("IMPORT_FAIL_INVALID_JSON: " + err.message);
  }

  const policyFiles = fs.existsSync(policyDir)
    ? fs.readdirSync(policyDir).filter((x) => x.toLowerCase().endsWith(".json")).sort()
    : [];

  const schemaFiles = fs.existsSync(schemaDir)
    ? fs.readdirSync(schemaDir).filter((x) => x.toLowerCase().endsWith(".json")).sort()
    : [];

  return {
    manifest,
    contract,
    version,
    hashes: {
      manifest: sha256File(manifestPath),
      contract: sha256File(contractPath),
      version: sha256File(versionPath)
    },
    counts: {
      policyOverlays: policyFiles.length,
      schemaOverlays: schemaFiles.length
    },
    files: {
      policy: policyFiles,
      schema: schemaFiles
    }
  };
}

function importFromFolder(sourcePath, workspace) {
  if (!fs.existsSync(sourcePath)) {
    throw new Error("IMPORT_FAIL_SOURCE_NOT_FOUND");
  }

  const inputRoot = path.join(workspace, "input", "contract");
  const sourceResolved = path.resolve(sourcePath).toLowerCase();
  const inputResolved = path.resolve(inputRoot).toLowerCase();

  if (sourceResolved === inputResolved) {
    throw new Error("IMPORT_FAIL_SOURCE_EQUALS_DESTINATION");
  }

  ensureDir(path.join(workspace, "input"));
  clearDir(inputRoot);
  copyDir(sourcePath, inputRoot);
  normalizeExtractedRoot(inputRoot);

  const summary = validateImportedBundle(inputRoot);

  return {
    ok: true,
    token: "WORKBENCH_IMPORT_OK",
    importedTo: inputRoot,
    summary
  };
}

function makeUploadBundle(exportDir) {
  if (!exportDir || !fs.existsSync(exportDir)) {
    throw new Error("EXPORT_UPLOAD_FAIL_EXPORT_DIR_NOT_FOUND");
  }

  const stat = fs.statSync(exportDir);
  if (!stat.isDirectory()) {
    throw new Error("EXPORT_UPLOAD_FAIL_EXPORT_DIR_NOT_DIRECTORY");
  }

  const runId = path.basename(exportDir);
  const outputRoot = path.resolve(exportDir, "..", "..");
  const uploadRoot = path.join(outputRoot, "upload_bundles");

  ensureDir(uploadRoot);

  const zipPath = path.join(uploadRoot, runId + ".contract.upload_bundle.zip");

  if (fs.existsSync(zipPath)) {
    fs.rmSync(zipPath, { force: true });
  }

  const zip = new AdmZip();
  zip.addLocalFolder(exportDir);
  zip.writeZip(zipPath);

  return {
    zipPath,
    zipSha256: sha256File(zipPath),
    runId,
    uploadRoot
  };
}

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    service: "workbench-ui-bridge",
    port: PORT
  });
});

app.post("/api/import-bundle", upload.single("bundle"), (req, res) => {
  try {
    const workspace = req.body?.workspace || "C:\\dev\\contract-registry\\workbench\\workspace";

    if (!req.file) {
      return res.status(400).json({ ok: false, error: "IMPORT_FAIL_NO_FILE" });
    }

    const inputRoot = path.join(workspace, "input", "contract");

    ensureDir(path.join(workspace, "input"));
    clearDir(inputRoot);

    const zip = new AdmZip(req.file.buffer);
    zip.extractAllTo(inputRoot, true);

    normalizeExtractedRoot(inputRoot);

    const summary = validateImportedBundle(inputRoot);

    return res.json({
      ok: true,
      token: "WORKBENCH_IMPORT_OK",
      importedTo: inputRoot,
      summary
    });
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message || "IMPORT_FAIL_UNKNOWN"
    });
  }
});

app.post("/api/import-folder", (req, res) => {
  try {
    const { folderPath, workspace } = req.body ?? {};

    if (!folderPath || !workspace) {
      return res.status(400).json({ ok: false, error: "IMPORT_FAIL_MISSING_INPUT" });
    }

    return res.json(importFromFolder(folderPath, workspace));
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message || "IMPORT_FAIL_FOLDER_UNKNOWN"
    });
  }
});

app.post("/api/import-repo", (req, res) => {
  try {
    const { repoPath, workspace } = req.body ?? {};

    if (!repoPath || !workspace) {
      return res.status(400).json({ ok: false, error: "IMPORT_FAIL_MISSING_INPUT" });
    }

    const bundleRoot = findRepoBundleRoot(repoPath);
    const result = importFromFolder(bundleRoot, workspace);

    result.sourceRepo = repoPath;
    result.sourceBundleRoot = bundleRoot;

    return res.json(result);
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message || "IMPORT_FAIL_REPO_UNKNOWN"
    });
  }
});


app.post("/api/pick-folder", (req, res) => {
  try {
    const title = req.body?.title || "Choose folder";

    const psCode = `
Add-Type -AssemblyName System.Windows.Forms
$dialog = New-Object System.Windows.Forms.FolderBrowserDialog
$dialog.Description = '${title.replace(/'/g, "''")}'
$dialog.ShowNewFolderButton = $true
$result = $dialog.ShowDialog()
if($result -eq [System.Windows.Forms.DialogResult]::OK){
  [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
  Write-Output $dialog.SelectedPath
}
`;

    const child = spawn("powershell.exe", [
      "-NoProfile",
      "-STA",
      "-ExecutionPolicy", "Bypass",
      "-Command", psCode
    ], { windowsHide: false });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (data) => stdout += data.toString());
    child.stderr.on("data", (data) => stderr += data.toString());

    child.on("close", (code) => {
      const selectedPath = stdout.trim();

      if (code !== 0) {
        return res.status(400).json({ ok: false, error: "PICK_FOLDER_FAILED: " + stderr });
      }

      if (!selectedPath) {
        return res.json({ ok: false, error: "PICK_FOLDER_CANCELLED" });
      }

      return res.json({ ok: true, selectedPath });
    });
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message || "PICK_FOLDER_FAIL" });
  }
});
app.post("/api/open-path", (req, res) => {
  try {
    const { targetPath } = req.body ?? {};

    if (!targetPath) {
      return res.status(400).json({ ok: false, error: "OPEN_PATH_MISSING_INPUT" });
    }

    if (!fs.existsSync(targetPath)) {
      return res.status(400).json({ ok: false, error: "OPEN_PATH_NOT_FOUND" });
    }

    const child = spawn("explorer.exe", [targetPath], {
      windowsHide: true,
      detached: true
    });

    child.unref();

    return res.json({
      ok: true,
      token: "OPEN_PATH_OK",
      targetPath
    });
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message || "OPEN_PATH_FAIL"
    });
  }
});

app.post("/api/export-upload-bundle", (req, res) => {
  try {
    const { exportDir } = req.body ?? {};
    const result = makeUploadBundle(exportDir);

    return res.json({
      ok: true,
      token: "WORKBENCH_EXPORT_UPLOAD_BUNDLE_OK",
      ...result
    });
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message || "EXPORT_UPLOAD_BUNDLE_FAIL"
    });
  }
});

app.post("/run", (req, res) => {
  const { repoRoot, workspace } = req.body ?? {};

  if (!repoRoot || !workspace) {
    return res.status(400).json({ error: "MISSING_INPUT" });
  }

  const scriptPath = `${repoRoot}\\workbench\\scripts\\_RUN_workbench_full_pipeline_v1.ps1`;

  const ps = spawn("powershell.exe", [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy", "Bypass",
    "-File", scriptPath,
    "-RepoRoot", repoRoot,
    "-Workspace", workspace
  ], {
    windowsHide: true
  });

  res.writeHead(200, {
    "Content-Type": "text/plain; charset=utf-8",
    "Transfer-Encoding": "chunked",
    "Cache-Control": "no-cache"
  });

  ps.stdout.on("data", (data) => {
    res.write(data.toString());
  });

  ps.stderr.on("data", (data) => {
    res.write("ERR: " + data.toString());
  });

  ps.on("error", (err) => {
    res.write("ERR: PROCESS_START_FAILED: " + err.message + "\n");
    res.end();
  });

  ps.on("close", (code) => {
    res.write("\nPROCESS_EXIT_CODE:" + String(code) + "\n");
    res.end();
  });
});

const server = app.listen(PORT, () => {
  console.log("WORKBENCH_UI_BRIDGE_OK http://localhost:" + PORT);
});

server.on("error", (err) => {
  if (err && err.code === "EADDRINUSE") {
    console.error("WORKBENCH_UI_BRIDGE_PORT_IN_USE:" + PORT);
    process.exit(1);
  }

  console.error(err);
  process.exit(1);
});
