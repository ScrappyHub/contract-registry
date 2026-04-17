import express from "express";
import cors from "cors";
import multer from "multer";
import AdmZip from "adm-zip";
import fs from "fs";
import path from "path";
import { spawn } from "child_process";
import crypto from "crypto";

const app = express();
app.use(cors());
app.use(express.json());

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

function validateImportedBundle(bundleRoot) {
  const manifestPath = path.join(bundleRoot, "manifest.json");
  const contractPath = path.join(bundleRoot, "contract.json");
  const versionPath = path.join(bundleRoot, "version.json");
  const policyDir = path.join(bundleRoot, "overlays", "policy");
  const schemaDir = path.join(bundleRoot, "overlays", "schema");

  const required = [manifestPath, contractPath, versionPath];
  for (const p of required) {
    if (!fs.existsSync(p)) {
      throw new Error("IMPORT_FAIL_MISSING_FILE: " + p);
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
    ? fs.readdirSync(policyDir).filter(x => x.toLowerCase().endsWith(".json")).sort()
    : [];

  const schemaFiles = fs.existsSync(schemaDir)
    ? fs.readdirSync(schemaDir).filter(x => x.toLowerCase().endsWith(".json")).sort()
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

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "workbench-ui-bridge" });
});

app.post("/api/import-bundle", upload.single("bundle"), (req, res) => {
  try {
    const workspace =
      req.body?.workspace || "C:\\dev\\contract-registry\\workbench\\workspace";

    if (!req.file) {
      return res.status(400).json({ ok: false, error: "IMPORT_FAIL_NO_FILE" });
    }

    const inputRoot = path.join(workspace, "input", "contract");
    clearDir(inputRoot);

    const zip = new AdmZip(req.file.buffer);
    zip.extractAllTo(inputRoot, true);

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

app.post("/api/run-pipeline", (req, res) => {
  const repoRoot = req.body?.repoRoot || "C:\\dev\\contract-registry";
  const workspace = req.body?.workspace || "C:\\dev\\contract-registry\\workbench\\workspace";
  const scriptPath = `${repoRoot}\\workbench\\scripts\\_RUN_workbench_full_pipeline_v1.ps1`;

  const child = spawn(
    "powershell.exe",
    [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      scriptPath,
      "-RepoRoot",
      repoRoot,
      "-Workspace",
      workspace
    ],
    { windowsHide: true }
  );

  let stdout = "";
  let stderr = "";
  let responded = false;

  child.stdout.on("data", (chunk) => {
    stdout += chunk.toString();
  });

  child.stderr.on("data", (chunk) => {
    stderr += chunk.toString();
  });

  child.on("error", (err) => {
    if (responded) return;
    responded = true;
    res.status(500).json({
      ok: false,
      error: `PROCESS_START_FAILED: ${err.message}`,
      stdout,
      stderr
    });
  });

  child.on("close", (code) => {
    if (responded) return;
    responded = true;

    const success =
      code === 0 &&
      stdout.includes("WORKBENCH_FULL_PIPELINE_GREEN");

    res.status(success ? 200 : 500).json({
      ok: success,
      exitCode: code,
      stdout,
      stderr
    });
  });
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

app.listen(5175, () => {
  console.log("WORKBENCH_UI_BRIDGE_OK http://localhost:5175");
});
