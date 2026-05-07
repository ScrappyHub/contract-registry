import express from "express";
import cors from "cors";
import multer from "multer";
import AdmZip from "adm-zip";
import fs from "fs";
import path from "path";
import { spawn, execFile } from "child_process";
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
    source_digest_sha256: sourceDigest,
    overlay_policy_count: 0,
    overlay_schema_count: 0
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
function safeRelPath(input) {
  const rel = String(input || "").replaceAll("\\", "/");
  if (!rel || rel.includes("..") || path.isAbsolute(rel)) {
    throw new Error("Unsafe uploaded path.");
  }
  return rel;
}

function shouldSkipUploadedRepoFile(rel) {
  const parts = rel.split("/");
  const blocked = new Set([
    ".git", "node_modules", "dist", "build", ".next", ".vite",
    "target", "bin", "obj", "__pycache__", ".venv", "venv",
    "proofs", "packets", "registry", "workbench"
  ]);

  return parts.some((p) => blocked.has(p));
}

function writeUploadedFilesToTemp(files, tempRoot) {
  clearDir(tempRoot);

  for (const file of files) {
    const rel = safeRelPath(file.originalname);
    const outPath = path.join(tempRoot, rel);
    ensureDir(path.dirname(outPath));
    fs.writeFileSync(outPath, file.buffer);
  }
}

function detectRepoIntelligence(kept) {
  const paths = kept.map(x => x.path || "");
  const lower = paths.map(x => x.toLowerCase());

  function anyEnds(suffixes) {
    return lower.filter(p => suffixes.some(s => p.endsWith(s)));
  }

  function anyIncludes(parts) {
    return lower.filter(p => parts.some(s => p.includes(s)));
  }

  const languages = [];
  if (anyEnds([".js", ".jsx", ".ts", ".tsx"]).length) languages.push("javascript/typescript");
  if (anyEnds([".ps1", ".psm1", ".psd1"]).length) languages.push("powershell");
  if (anyEnds([".py"]).length) languages.push("python");
  if (anyEnds([".cs"]).length) languages.push("csharp");
  if (anyEnds([".rs"]).length) languages.push("rust");
  if (anyEnds([".go"]).length) languages.push("go");
  if (anyEnds([".java"]).length) languages.push("java");
  if (anyEnds([".sql"]).length) languages.push("sql");

  const packageManagers = [];
  if (lower.includes("package.json")) packageManagers.push("npm");
  if (lower.includes("pnpm-lock.yaml")) packageManagers.push("pnpm");
  if (lower.includes("yarn.lock")) packageManagers.push("yarn");
  if (lower.includes("requirements.txt") || lower.includes("pyproject.toml")) packageManagers.push("python");
  if (lower.includes("cargo.toml")) packageManagers.push("cargo");
  if (lower.includes("go.mod")) packageManagers.push("go modules");
  if (lower.includes("pom.xml") || lower.includes("build.gradle")) packageManagers.push("jvm");

  const apiCandidates = paths.filter(p => {
    const l = p.toLowerCase();
    return (
      l.endsWith("server.js") ||
      l.endsWith("server.ts") ||
      l.includes("/api/") ||
      l.includes("\\api\\") ||
      l.includes("routes") ||
      l.includes("controller") ||
      l.includes("endpoint")
    );
  }).slice(0, 50);

  const schemaCandidates = paths.filter(p => {
    const l = p.toLowerCase();
    return (
      l.includes("schema") ||
      l.endsWith(".schema.json") ||
      l.includes("/schemas/") ||
      l.includes("\\schemas\\") ||
      l.endsWith(".sql")
    );
  }).slice(0, 50);

  const licenseFiles = paths.filter(p => {
    const n = p.toLowerCase().split("/").pop();
    return n === "license" || n === "license.md" || n === "license.txt" || n === "copying";
  });

  const docs = paths.filter(p => {
    const n = p.toLowerCase().split("/").pop();
    return n === "readme.md" || n === "readme.txt" || p.toLowerCase().startsWith("docs/");
  }).slice(0, 50);

  const envExamples = paths.filter(p => {
    const n = p.toLowerCase().split("/").pop();
    return n === ".env.example" || n === "env.example" || n.endsWith(".env.example");
  });

  const dependencySignals = [];
  if (lower.includes("package.json")) dependencySignals.push("npm package manifest");
  if (lower.includes("supabase/config.toml") || anyIncludes(["supabase/migrations"]).length) dependencySignals.push("supabase");
  if (anyIncludes(["stripe", "webhook"]).length) dependencySignals.push("stripe/webhooks");
  if (lower.includes("vercel.json")) dependencySignals.push("vercel");
  if (lower.includes("dockerfile") || lower.includes("docker-compose.yml")) dependencySignals.push("docker");
  if (anyIncludes(["github/workflows", ".github/workflows"]).length) dependencySignals.push("github actions");

  const exportedSurfaces = [];
  if (apiCandidates.length) exportedSurfaces.push("api/server candidates");
  if (schemaCandidates.length) exportedSurfaces.push("schema/database candidates");
  if (anyEnds([".ps1"]).some(p => p.includes("cli") || p.includes("run"))) exportedSurfaces.push("powershell cli/runner");
  if (anyIncludes(["chrome-extension", "manifest.json"]).length) exportedSurfaces.push("browser extension candidate");
  if (anyIncludes(["electron", "tauri"]).length) exportedSurfaces.push("desktop app candidate");

  const deploymentHints = [];
  if (lower.includes("vercel.json")) deploymentHints.push("vercel");
  if (lower.includes("dockerfile") || lower.includes("docker-compose.yml")) deploymentHints.push("container");
  if (anyIncludes(["supabase/"]).length) deploymentHints.push("supabase");
  if (anyIncludes(["netlify.toml"]).length) deploymentHints.push("netlify");
  if (anyIncludes(["wrangler.toml"]).length) deploymentHints.push("cloudflare workers");

  const repoTypeScores = {
    "web app": 0,
    "backend/api": 0,
    "cli/tooling": 0,
    "desktop app": 0,
    "browser extension": 0,
    "database/schema project": 0,
    "infrastructure": 0,
    "library/sdk": 0
  };

  if (anyEnds([".jsx", ".tsx"]).length || anyIncludes(["vite.config", "next.config"]).length) repoTypeScores["web app"] += 3;
  if (apiCandidates.length) repoTypeScores["backend/api"] += 4;
  if (anyEnds([".ps1", ".sh"]).length) repoTypeScores["cli/tooling"] += 2;
  if (anyIncludes(["electron", "tauri"]).length) repoTypeScores["desktop app"] += 4;
  if (anyIncludes(["manifest.json", "chrome-extension", "mv3"]).length) repoTypeScores["browser extension"] += 3;
  if (schemaCandidates.length || anyIncludes(["migrations"]).length) repoTypeScores["database/schema project"] += 3;
  if (lower.includes("dockerfile") || lower.includes("docker-compose.yml") || anyIncludes(["terraform", "infra"]).length) repoTypeScores["infrastructure"] += 3;
  if (anyIncludes(["src/index", "lib/", "sdk"]).length) repoTypeScores["library/sdk"] += 2;

  const repoTypes = Object.entries(repoTypeScores)
    .filter(([, score]) => score > 0)
    .sort((a, b) => b[1] - a[1])
    .map(([name, score]) => ({ name, score }));

  const primaryType = repoTypes.length ? repoTypes[0].name : "general project";

  const frameworks = [];
  if (anyIncludes(["vite.config"]).length) frameworks.push("vite");
  if (anyIncludes(["next.config"]).length) frameworks.push("nextjs");
  if (anyIncludes(["react", ".jsx", ".tsx"]).length) frameworks.push("react");
  if (anyIncludes(["express"]).length || apiCandidates.some(p => p.toLowerCase().endsWith("server.js"))) frameworks.push("express/node");
  if (anyIncludes(["tauri"]).length) frameworks.push("tauri");
  if (anyIncludes(["electron"]).length) frameworks.push("electron");

  const authSurfaces = [];
  if (anyIncludes(["supabase", "auth"]).length) authSurfaces.push("supabase/auth candidates");
  if (anyIncludes(["jwt", "oauth", "session", "passport"]).length) authSurfaces.push("token/session auth candidates");

  const paymentSurfaces = [];
  if (anyIncludes(["stripe"]).length) paymentSurfaces.push("stripe");
  if (anyIncludes(["checkout", "billing", "subscription"]).length) paymentSurfaces.push("billing/subscription candidates");

  const cloudSurfaces = [];
  if (anyIncludes(["vercel"]).length) cloudSurfaces.push("vercel");
  if (anyIncludes(["supabase"]).length) cloudSurfaces.push("supabase");
  if (anyIncludes(["netlify"]).length) cloudSurfaces.push("netlify");
  if (anyIncludes(["wrangler", "cloudflare"]).length) cloudSurfaces.push("cloudflare");
  if (anyIncludes(["docker"]).length) cloudSurfaces.push("docker/container");

  const governanceSurfaces = [];
  if (anyIncludes(["policy", "policies", "overlay"]).length) governanceSurfaces.push("policy/overlay files");
  if (anyIncludes(["receipt", "receipts", "proofs"]).length) governanceSurfaces.push("receipts/proofs");
  if (anyIncludes(["signature", "sign", "verify", "sha256"]).length) governanceSurfaces.push("signature/hash verification");
  if (anyIncludes(["license"]).length) governanceSurfaces.push("license surface");

  const aiSurfaces = [];
  if (anyIncludes(["openai", "anthropic", "llm", "model", "embedding", "chatgpt"]).length) aiSurfaces.push("ai/model usage candidates");

  const envVars = [];
  const envFiles = paths.filter(p => {
    const n = p.toLowerCase().split("/").pop();
    return n === ".env" || n === ".env.example" || n.endsWith(".env.example") || n === "env.example";
  });

  for (const p of envFiles.slice(0, 20)) {
    envVars.push(p);
  }

  const permissionFiles = paths.filter(p => {
    const l = p.toLowerCase();
    return l.endsWith("manifest.json") || l.includes("permissions") || l.includes("capabilities");
  }).slice(0, 50);

  const endpointCandidates = paths.filter(p => {
    const l = p.toLowerCase();
    return (
      l.includes("/api/") ||
      l.includes("\\api\\") ||
      l.includes("/routes/") ||
      l.includes("\\routes\\") ||
      l.includes("controller") ||
      l.includes("endpoint") ||
      l.endsWith("server.js") ||
      l.endsWith("server.ts")
    );
  }).slice(0, 75);

  const semantic_summary = {
    semantic_schema: "contract_registry.repo_semantic_intelligence.v2",
    semantic_summary,
    repo_type: primaryType,
    frameworks,
    endpoint_candidates: endpointCandidates,
    auth_surfaces: authSurfaces,
    payment_surfaces: paymentSurfaces,
    cloud_surfaces: cloudSurfaces,
    governance_surfaces: governanceSurfaces,
    ai_surfaces: aiSurfaces,
    env_files: envVars,
    permission_files: permissionFiles
  };

  const riskNotes = [];
  if (!licenseFiles.length) riskNotes.push("No license file detected.");
  if (!docs.length) riskNotes.push("No README/docs detected.");
  if (envExamples.length) riskNotes.push("Environment template detected; review secrets handling.");
  if (apiCandidates.length) riskNotes.push("API or server surface candidates detected.");
  if (schemaCandidates.length) riskNotes.push("Schema/database candidates detected.");

  return {
    schema: "contract_registry.repo_intelligence.v1",
    generated_utc: new Date().toISOString(),
    languages,
    package_managers: packageManagers,
    api_candidates: apiCandidates,
    schema_candidates: schemaCandidates,
    license_files: licenseFiles,
    docs,
    env_examples: envExamples,
    semantic_schema: "contract_registry.repo_semantic_intelligence.v2",
    semantic_summary,
    repo_type: primaryType,
    repo_type_candidates: repoTypes,
    dependency_signals: dependencySignals,
    exported_surfaces: exportedSurfaces,
    deployment_hints: deploymentHints,
    risk_notes: riskNotes
  };
}

function createBundleFromUploadedRepo(files, workspace) {
  if (!files || files.length === 0) throw new Error("No repo files selected.");
  if (files.length > 1200) {
    throw new Error("Repo upload is too large for browser mode. Use the local desktop/path scanner for large repos.");
  }

  const inputRoot = path.join(workspace, "input", "contract");
  const kept = [];

  for (const file of files) {
    const rel = safeRelPath(file.originalname);

    if (shouldSkipUploadedRepoFile(rel)) continue;
    if (file.size > 1024 * 1024) continue;

    const lowerRel = rel.toLowerCase();
    if (
      lowerRel.endsWith(".pyc") ||
      lowerRel.endsWith(".pyo") ||
      lowerRel.endsWith(".dll") ||
      lowerRel.endsWith(".exe") ||
      lowerRel.endsWith(".png") ||
      lowerRel.endsWith(".jpg") ||
      lowerRel.endsWith(".jpeg") ||
      lowerRel.endsWith(".gif") ||
      lowerRel.endsWith(".webp") ||
      lowerRel.endsWith(".zip") ||
      lowerRel.includes("__pycache__/")
    ) continue;

    kept.push({
      path: rel,
      bytes: file.size,
      sha256: crypto.createHash("sha256").update(file.buffer).digest("hex")
    });
  }

  kept.sort((a, b) => a.path.localeCompare(b.path));

  const firstPath = kept[0]?.path || "uploaded.repo";
const rootName = firstPath.includes("/") ? firstPath.split("/")[0] : "uploaded.repo";
  const safeName = rootName.toLowerCase().replace(/[^a-z0-9]+/g, ".").replace(/^\.+|\.+$/g, "") || "uploaded.repo";
  const contractKey = safeName + ".contract.v1";
  const sourceDigest = crypto.createHash("sha256").update(JSON.stringify(kept)).digest("hex");

  ensureDir(path.join(workspace, "input"));
  clearDir(inputRoot);
  ensureDir(path.join(inputRoot, "overlays", "policy"));
  ensureDir(path.join(inputRoot, "overlays", "schema"));

  writeJson(path.join(inputRoot, "manifest.json"), {
    bundle_schema: "contract_registry.repo_upload_bundle.v1",
    contract_key: contractKey,
    version_label: "repo-upload-v1",
    source_kind: "repo_upload",
    source_file_count: kept.length,
    source_digest_sha256: sourceDigest,
    overlay_policy_count: 0,
    overlay_schema_count: 0
  });

  writeJson(path.join(inputRoot, "contract.json"), {
    contract_key: contractKey,
    title: safeName,
    description: "Generated from selected local repo folder.",
    source_kind: "repo_upload"
  });

  writeJson(path.join(inputRoot, "version.json"), {
    contract_key: contractKey,
    version_label: "repo-upload-v1",
    version_no: 1,
    status: "draft",
    source_digest_sha256: sourceDigest,
    overlay_policy_count: 0,
    overlay_schema_count: 0
  });

  writeJson(path.join(inputRoot, "source_inventory.json"), {
    file_count: kept.length,
    files: kept
  });

  const intelligence = detectRepoIntelligence(kept);
  writeJson(path.join(inputRoot, "repo_intelligence.json"), intelligence);

  return {
    ok: true,
    token: "SOURCE_READY",
    inputRoot,
    summary: validateBundle(inputRoot),
    repoIntake: {
      fileCount: kept.length,
      sourceDigestSha256: sourceDigest
    }
  };
}

app.post("/api/import-folder-upload", upload.array("files", 2000), (req, res) => {
  let tempRoot = "";
  try {
    const workspace = req.body?.workspace;
    if (!workspace) throw new Error("Workspace is missing.");
    if (!req.files || req.files.length === 0) throw new Error("No folder files selected.");

    tempRoot = path.join(workspace, "_tmp_folder_upload_" + Date.now().toString());
    writeUploadedFilesToTemp(req.files, tempRoot);

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
    if (tempRoot && fs.existsSync(tempRoot)) fs.rmSync(tempRoot, { recursive: true, force: true });
    return res.status(400).json({ ok: false, error: err.message });
  }
});

app.post("/api/import-repo-path", (req, res) => {
  try {
    const repoPath = req.body?.repoPath;
    const workspace = req.body?.workspace;

    if (!repoPath) throw new Error("No repo path provided.");
    if (!workspace) throw new Error("No workspace provided.");
    if (!fs.existsSync(repoPath)) throw new Error("Repo path does not exist.");
    if (!fs.statSync(repoPath).isDirectory()) throw new Error("Repo path is not a folder.");

    return res.json(createBundleFromAnyRepo(repoPath, workspace));
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});
app.post("/api/import-repo-upload", upload.array("files", 5000), (req, res) => {
  try {
    const workspace = req.body?.workspace;
    if (!workspace) throw new Error("Workspace is missing.");
    return res.json(createBundleFromUploadedRepo(req.files, workspace));
  } catch (err) {
    return res.status(400).json({ ok: false, error: err.message });
  }
});
app.post("/api/read-export-files", (req, res) => {
  try {
    const exportDir = req.body?.exportDir;

    if (!exportDir) throw new Error("No export folder provided.");
    if (!fs.existsSync(exportDir)) throw new Error("Export folder does not exist.");

    const allowed = [
      "manifest.json",
      "contract.json",
      "version.json",
      "overlay_summary.txt",
      "sha256sums.txt",
      "export_receipt.txt",
      "source_inventory.json",
      "repo_intelligence.json"
    ];

    const files = {};

    for (const name of allowed) {
      const p = path.join(exportDir, name);
      if (fs.existsSync(p) && fs.statSync(p).isFile()) {
        files[name] = fs.readFileSync(p, "utf8");
      }
    }

    return res.json({
      ok: true,
      exportDir,
      files
    });
  } catch (err) {
    return res.status(400).json({
      ok: false,
      error: err.message
    });
  }
});
app.post("/api/open-path", async (req, res) => {
  try {
    const targetPath = req.body?.targetPath;

    if (!targetPath) {
      throw new Error("No path provided.");
    }

    if (!fs.existsSync(targetPath)) {
      throw new Error("Target path does not exist.");
    }

    execFile(
      "explorer.exe",
      [targetPath],
      {
        windowsHide: false
      },
      (err) => {
        if (err) {
          console.error("OPEN_FOLDER_ERROR", err);

          return res.status(500).json({
            ok: false,
            error: err.message
          });
        }

        return res.json({
          ok: true,
          token: "OPEN_PATH_OK",
          targetPath
        });
      }
    );

  } catch (err) {
    console.error("OPEN_PATH_ROUTE_FAIL", err);

    return res.status(400).json({
      ok: false,
      error: err.message
    });
  }
});app.post("/api/create-upload-bundle", (req, res) => {
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
