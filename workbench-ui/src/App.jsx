import { useEffect, useRef, useState } from "react";

const API = "http://localhost:5185";

function after(label, text) {
  const line = text.split(/\r?\n/).find((x) => x.startsWith(label));
  return line ? line.slice(label.length).trim() : "";
}

function done(step, log) {
  return log.includes("STEP_OK: " + step);
}

function technicalClauses(files) {
  try {
    const raw = files?.["technical_clauses.json"];
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function repoIntelligence(files) {
  try {
    const raw = files?.["repo_intelligence.json"];
    return raw ? JSON.parse(raw) : null;
  } catch {
    return null;
  }
}

function inventorySummary(files) {
  try {
    const raw = files?.["source_inventory.json"];
    if (!raw) return null;

    const inv = JSON.parse(raw);
    const items = Array.isArray(inv.files) ? inv.files : [];

    const extCounts = {};
    const folderCounts = {};

    for (const item of items) {
      const p = item.path || "";
      const parts = p.split("/");
      const folder = parts.length > 1 ? parts[0] : "(root)";
      const name = parts[parts.length - 1] || "";
      const dot = name.lastIndexOf(".");
      const ext = dot >= 0 ? name.slice(dot).toLowerCase() : "(none)";

      folderCounts[folder] = (folderCounts[folder] || 0) + 1;
      extCounts[ext] = (extCounts[ext] || 0) + 1;
    }

    const topExt = Object.entries(extCounts).sort((a,b) => b[1] - a[1]).slice(0, 6);
    const topFolders = Object.entries(folderCounts).sort((a,b) => b[1] - a[1]).slice(0, 6);

    return {
      fileCount: inv.file_count || items.length,
      topExt,
      topFolders
    };
  } catch {
    return null;
  }
}

function friendly(operation, err) {
  const msg = err?.message || String(err || "Unknown error");
  if (msg === "Failed to fetch") {
    return operation + " failed because the local bridge did not respond. Make sure npm run dev is running and the bridge is on port 5185.";
  }
  return operation + " failed: " + msg;
}

export default function App() {
  const [repoRoot] = useState("C:\\dev\\contract-registry");
  const [workspace] = useState("C:\\dev\\contract-registry\\workbench\\workspace");

  const [bundleFolderPath, setBundleFolderPath] = useState("");
  const [repoPathText, setRepoPathText] = useState("C:\\dev\\contract-registry");
  const [repoScanPath, setRepoScanPath] = useState("");

  const [bridgeOk, setBridgeOk] = useState(false);
  const [source, setSource] = useState(null);
  const [sourcePath, setSourcePath] = useState("");
  const [status, setStatus] = useState("Choose a source");
  const [error, setError] = useState("");
  const [log, setLog] = useState("");
  const [busy, setBusy] = useState(false);
  const [upload, setUpload] = useState(null);
  const [showTech, setShowTech] = useState(false);
  const [showPreview, setShowPreview] = useState(false);
  const [intakeMeta, setIntakeMeta] = useState(null);
  const [historyResult, setHistoryResult] = useState(null);
  const [exportFiles, setExportFiles] = useState(null);
  const [selectedExportFile, setSelectedExportFile] = useState("");
  const [openNotice, setOpenNotice] = useState("");
  const [copyNotice, setCopyNotice] = useState("");

  const zipRef = useRef(null);
  const bundleFolderRef = useRef(null);
  const repoFolderRef = useRef(null);

  const exportDir = after("EVIDENCE_EXPORT_DIR:", log);
  const releaseDir = after("LATEST_RELEASE:", log);
  const receipt = after("EVIDENCE_EXPORT_RECEIPT:", log);
  const receiptHash = after("EVIDENCE_EXPORT_RECEIPT_SHA256:", log);
  const ready = log.includes("WORKBENCH_FULL_PIPELINE_GREEN");
  const projectSummary = inventorySummary(exportFiles);
  const intelligence = repoIntelligence(exportFiles);
  const clauses = technicalClauses(exportFiles);
  const manifestText = exportFiles?.["manifest.json"] || "";
  let manifestSummary = null;
  try {
    manifestSummary = manifestText ? JSON.parse(manifestText) : null;
  } catch {
    manifestSummary = null;
  }

  const displayedContractKey =
    manifestSummary?.contract_key ||
    source?.contractKey ||
    "-";

  const displayedFileCount =
    manifestSummary?.source_file_count ||
    projectSummary?.fileCount ||
    intakeMeta?.fileCount ||
    "-";

  useEffect(() => {
    checkBridge();
  }, []);

  async function checkBridge() {
    try {
      const res = await fetch(API + "/api/health");
      const data = await res.json();
      setBridgeOk(!!data.ok);
      if (data.ok) setError("");
    } catch (e) {
      setBridgeOk(false);
      setError(friendly("Bridge check", e));
    }
  }

  function clearSource() {
    setSource(null);
    setSourcePath("");
    setUpload(null);
    setLog("");
    setExportFiles(null);
    setSelectedExportFile("");
    setShowPreview(false);
    setIntakeMeta(null);
    setHistoryResult(null);
  }

  function fail(message) {
    clearSource();
    setError(message || "Something went wrong.");
    setStatus("Needs attention");
  }

  function setSourceReady(data, pathText, logText) {
    setSource(data.summary);
    setSourcePath(pathText);
    setIntakeMeta({
      fileCount: data?.repoIntake?.fileCount || data?.summary?.manifest?.source_file_count || null,
      sourceDigest: data?.repoIntake?.sourceDigestSha256 || data?.summary?.manifest?.source_digest_sha256 || "",
      mode: data?.summary?.manifest?.source_kind || "bundle"
    });
    setLog(logText + "\n");
    setError("");
    setStatus("Source ready");
  }

  async function scanRepoPath() {
    if (!repoPathText.trim()) {
      fail("Local path scan failed: enter a repo folder path first.");
      return;
    }

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Scanning local path...");

    try {
      const res = await fetch(API + "/api/import-repo-path", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoPath: repoPathText.trim(), workspace })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error);

      setSourceReady(data, repoPathText.trim(), "Source generated from local path scan.");
    } catch (e) {
      fail(friendly("Local path scan", e));
    } finally {
      setBusy(false);
    }
  }

  async function uploadFolderFiles(files, endpoint, label) {
    if (!files || files.length === 0) return;

    setBusy(true);
    clearSource();
    setError("");
    setStatus(label + "...");

    try {
      const form = new FormData();
      for (const file of Array.from(files)) {
        const rel = file.webkitRelativePath || file.name;
        form.append("files", file, rel);
      }
      form.append("workspace", workspace);

      const res = await fetch(API + endpoint, {
        method: "POST",
        body: form
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error);

      setSourceReady(data, "Selected folder", label + ".");
    } catch (e) {
      fail(friendly(label, e));
    } finally {
      setBusy(false);
      if (bundleFolderRef.current) bundleFolderRef.current.value = "";
      if (repoFolderRef.current) repoFolderRef.current.value = "";
    }
  }

  async function importZip(file) {
    if (!file) return;

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Importing zip...");

    try {
      const form = new FormData();
      form.append("bundle", file);
      form.append("workspace", workspace);

      const res = await fetch(API + "/api/import-zip", { method: "POST", body: form });
      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, file.name, "Source imported from zip.");
    } catch (e) {
      fail(friendly("Zip import", e));
    } finally {
      setBusy(false);
      if (zipRef.current) zipRef.current.value = "";
    }
  }

  async function importFolder() {
    if (!bundleFolderPath.trim()) {
      fail("Choose Bundle Folder failed: paste a bundle folder path first.");
      return;
    }

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Importing folder...");

    try {
      const res = await fetch(API + "/api/import-folder", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ folderPath: bundleFolderPath.trim(), workspace })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, bundleFolderPath.trim(), "Source imported from folder.");
    } catch (e) {
      fail(friendly("Folder import", e));
    } finally {
      setBusy(false);
    }
  }

  async function scanRepo() {
    if (!repoScanPath.trim()) {
      fail("Scan Repo failed: paste a repo folder path first.");
      return;
    }

    setBusy(true);
    clearSource();
    setError("");
    setStatus("Scanning repo...");

    try {
      const res = await fetch(API + "/api/import-any-repo", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoPath: repoScanPath.trim(), workspace })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);
      setSourceReady(data, repoScanPath.trim(), "Source generated from repo scan.");
    } catch (e) {
      fail(friendly("Repo scan", e));
    } finally {
      setBusy(false);
    }
  }

  async function buildPackage() {
    if (!source) {
      setError("Build Package failed: choose a source first.");
      setStatus("Needs attention");
      return;
    }

    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Building package...");
    setLog("");

    try {
      const res = await fetch(API + "/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoRoot, workspace })
      });

      if (!res.body) throw new Error("Build response stream missing.");

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let full = "";

      while (true) {
        const item = await reader.read();
        if (item.done) break;
        const chunk = decoder.decode(item.value, { stream: true });
        full += chunk;
        setLog((prev) => prev + chunk);
      }

      if (full.includes("WORKBENCH_FULL_PIPELINE_GREEN")) {
        setStatus("Package ready");
      } else {
        setStatus("Needs attention");
        setError("Build finished, but the green success token was not found. Open technical details.");
      }
    } catch (e) {
      setStatus("Needs attention");
      setError(friendly("Build package", e));
    } finally {
      setBusy(false);
    }
  }

  async function createUploadBundle() {
    if (!exportDir) {
      setError("Create Upload Bundle failed: build a package first.");
      setStatus("Needs attention");
      return;
    }

    setBusy(true);
    setError("");
    setStatus("Creating upload bundle...");

    try {
      const res = await fetch(API + "/api/create-upload-bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ exportDir })
      });

      const data = await res.json();

      if (!data.ok) throw new Error(data.error);

      setUpload(data);

      try {
        await recordPackageHistory(exportDir, data.zipPath || "");
      } catch (historyErr) {
        setError("Upload bundle created, but package history failed: " + historyErr.message);
      }

      setStatus("Upload bundle ready");
    } catch (e) {
      setStatus("Needs attention");
      setError(friendly("Create upload bundle", e));
    } finally {
      setBusy(false);
    }
  }

  async function copyText(label, value) {
    if (!value) {
      setError(label + " copy failed: nothing to copy yet.");
      setStatus("Needs attention");
      return;
    }

    try {
      await navigator.clipboard.writeText(value);
      setCopyNotice(label + " copied.");
      setError("");
    } catch {
      setError(label + " copy failed. Select and copy it manually from the Evidence section.");
      setStatus("Needs attention");
    }
  }

  async function readExportFiles() {
    if (!exportDir) {
      setError("Preview Export Files failed: build a package first.");
      setStatus("Needs attention");
      return;
    }

    try {
      const res = await fetch(API + "/api/read-export-files", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ exportDir })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error);

      setExportFiles(data.files);
      setSelectedExportFile(Object.keys(data.files || {})[0] || "");
      setShowPreview(true);
      setError("");
    } catch (e) {
      setError(friendly("Preview Export Files", e));
      setStatus("Needs attention");
    }
  }

  async function openPath(targetPath) {
    if (!targetPath) return;

    try {
      const res = await fetch(API + "/api/open-path", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ targetPath })
      });

      const data = await res.json();
      if (!data.ok) throw new Error(data.error || "Open folder failed.");

      setOpenNotice("Opened: " + targetPath);
      setError("");
    } catch (e) {
      setOpenNotice("");
      setError(friendly("Open folder", e));
      setStatus("Needs attention");
    }
  }

  async function recordPackageHistory(nextExportDir, nextUploadPath = "") {
    const res = await fetch(API + "/api/record-package-history", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        workspace,
        exportDir: nextExportDir,
        uploadZipPath: nextUploadPath
      })
    });

    const data = await res.json();
    if (!data.ok) throw new Error(data.error || "Package history failed.");

    setHistoryResult(data);
    return data;
  }

  async function runAll() {
    if (!source) {
      setError("Run All failed: choose a source first.");
      setStatus("Needs attention");
      return;
    }

    setBusy(true);
    setError("");
    setUpload(null);
    setStatus("Building package...");
    setLog("");

    let full = "";
    let nextExportDir = "";

    try {
      const buildRes = await fetch(API + "/api/run", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ repoRoot, workspace })
      });

      if (!buildRes.body) throw new Error("Build response stream missing.");

      const reader = buildRes.body.getReader();
      const decoder = new TextDecoder();

      while (true) {
        const item = await reader.read();
        if (item.done) break;
        const chunk = decoder.decode(item.value, { stream: true });
        full += chunk;
        setLog((prev) => prev + chunk);
      }

      if (!full.includes("WORKBENCH_FULL_PIPELINE_GREEN")) {
        throw new Error("Build finished, but the green success token was not found. Open technical details.");
      }

      nextExportDir = after("EVIDENCE_EXPORT_DIR:", full);
      if (!nextExportDir) {
        throw new Error("Build finished, but no export folder was found.");
      }

      setStatus("Creating upload bundle...");

      const uploadRes = await fetch(API + "/api/create-upload-bundle", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ exportDir: nextExportDir })
      });

      const uploadData = await uploadRes.json();
      if (!uploadData.ok) throw new Error(uploadData.error);

      setUpload(uploadData);

      try {
        await recordPackageHistory(nextExportDir, uploadData.zipPath || "");
      } catch (historyErr) {
        setError("Upload bundle created, but package history failed: " + historyErr.message);
      }

      setStatus("Upload bundle ready");
    } catch (e) {
      setStatus("Needs attention");
      setError(friendly("Run All", e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="app">
      <aside>
        <h1>Contract Registry</h1>
        <p>Workbench</p>

        <div className="side-status">
          <span>Bridge</span>
          <b className={bridgeOk ? "green" : "red"}>{bridgeOk ? "Connected" : "Offline"}</b>
        </div>

        <div className="side-status">
          <span>Status</span>
          <b>{status}</b>
        </div>
      </aside>

      <main>
        <header>
          <h2>Build Contract Package</h2>
          <p>Import a contract bundle, or scan a local repo into a generated bundle.</p>
        </header>

        {error && <div className="error">{error}</div>}
        {openNotice && <div className="success top-notice">{openNotice}</div>}
        {copyNotice && <div className="success top-notice">{copyNotice}</div>}

        <section className="cards">
          <div className="card">
            <div className="num">1</div>
            <h3>Choose source</h3>
            <p>Choose a bundle zip/folder, or scan a local repo path directly from disk.</p>

            <div className="buttons">
              <label className="button">
                Choose Zip
                <input ref={zipRef} type="file" accept=".zip" onChange={(e) => importZip(e.target.files?.[0])} />
              </label>
            </div>

            <div className="pick-grid">
              <label className="pick-card">
                <span className="pick-title">Bundle folder</span>
                <span className="pick-text">Choose an unzipped bundle folder</span>
                <strong>Choose Bundle Folder</strong>
                <input
                  ref={bundleFolderRef}
                  type="file"
                  webkitdirectory="true"
                  directory=""
                  multiple
                  onChange={(e) => uploadFolderFiles(e.target.files, "/api/import-folder-upload", "Bundle folder import")}
                />
              </label>

              <div className="pick-card manual-path-card">
                <span className="pick-title">Local repo path recommended</span>
                <span className="pick-text">Best for normal and large repos. Scans directly from disk.</span>
                <input
                  className="manual-path-input"
                  value={repoPathText}
                  onChange={(e) => setRepoPathText(e.target.value)}
                  placeholder="C:\dev\my-repo"
                />
                <button onClick={scanRepoPath} disabled={busy || !bridgeOk}>Scan Local Path</button>
              </div>

              <label className="pick-card">
                <span className="pick-title">Repo folder upload</span>
                <span className="pick-text">Fallback only. Use Local repo path for real projects.</span>
                <strong>Small Repo Upload</strong>
                <input
                  ref={repoFolderRef}
                  type="file"
                  webkitdirectory="true"
                  directory=""
                  multiple
                  onChange={(e) => uploadFolderFiles(e.target.files, "/api/import-repo-upload", "Repo scan")}
                />
              </label>
            </div>

            <div className={source ? "notice good" : "notice"}>
              {source ? (
                <>
                  <b>Source ready</b>
                  <span>{source.contractKey} / {source.versionLabel}</span>
                  <small>{sourcePath}</small>
                  {intakeMeta?.fileCount && <small>{intakeMeta.fileCount} files scanned</small>}
                  {intakeMeta?.sourceDigest && <small>digest: {intakeMeta.sourceDigest}</small>}
                </>
              ) : (
                "No source selected yet."
              )}
            </div>
          </div>

          <div className="card">
            <div className="num">2</div>
            <h3>Build package</h3>
            <p>Runs inspect, build, verify, and export using the local engine.</p>

            <div className="action-row stack-actions">
              <button className="primary" onClick={buildPackage} disabled={busy || !bridgeOk || !source}>
                {busy ? "Working..." : "Build Package"}
              </button>

              <button className="run-all" onClick={runAll} disabled={busy || !bridgeOk || !source}>
                Run All
              </button>
            </div>

            <p className="hint">Run All builds, verifies, exports, and creates the upload bundle.</p>

            <div className="steps">
              <span className={done("inspect", log) ? "done" : ""}>Inspect</span>
              <span className={done("build", log) ? "done" : ""}>Build</span>
              <span className={done("verify", log) ? "done" : ""}>Verify</span>
              <span className={done("export", log) ? "done" : ""}>Export</span>
            </div>
          </div>

          <div className="card">
            <div className="num">3</div>
            <h3>Review result</h3>

            {ready ? (
              <>
                <div className="result-summary">
                  <div>
                    <span>Package</span>
                    <strong>{displayedContractKey}</strong>
                  </div>

                  <div>
                    <span>Files scanned</span>
                    <strong>{displayedFileCount}</strong>
                  </div>

                  <div>
                    <span>Verification</span>
                    <strong>{ready ? "Passed" : "-"}</strong>
                  </div>

                  <div>
                    <span>Upload bundle</span>
                    <strong>{upload?.zipPath ? "Ready" : "Not created"}</strong>
                  </div>
                </div>

                <div className="notice good">
                  <b>Package created</b>
                  <span>Ready for review or upload packaging.</span>
                </div>

                {historyResult && (
                  <div className="diff-panel">
                    <h3>Version History</h3>
                    <div className="diff-grid">
                      <div>
                        <span>History entries</span>
                        <strong>{historyResult.history_count || 1}</strong>
                      </div>

                      <div>
                        <span>Current package</span>
                        <strong>{historyResult.entry?.contract_key || displayedContractKey}</strong>
                      </div>

                      <div>
                        <span>Files scanned</span>
                        <strong>{historyResult.entry?.source_file_count || displayedFileCount}</strong>
                      </div>

                      <div>
                        <span>Recorded</span>
                        <strong>{historyResult.token || "-"}</strong>
                      </div>
                    </div>

                    {!historyResult.diff && (
                      <p className="diff-note">First recorded package for this workspace. Future runs will show changes here.</p>
                    )}

                    {historyResult.diff && (
                      <div className="diff-note">
                        Previous package found. Diff summary will expand in the next slice.
                      </div>
                    )}
                  </div>
                )}

                <div className="action-row">
                  <button onClick={() => openPath(exportDir)}>Open Export Folder</button>
                  <button onClick={readExportFiles}>Preview Package</button>
                  <button onClick={createUploadBundle} disabled={busy}>Create Upload Bundle</button>
                  <button onClick={() => copyText("Upload bundle path", upload?.zipPath)}>Copy Upload Path</button>
                  <button onClick={() => copyText("Receipt hash", receiptHash)}>Copy Receipt Hash</button>
                </div>

                {upload && (
                  <div className="upload-ready">
                    <b>Upload bundle ready</b>
                    <span>This is the file you would upload or submit to the hosted registry.</span>
                    <code>{upload.zipPath}</code>
                    <code>{upload.zipSha256}</code>
                  </div>
                )}
              </>
            ) : (
              <div className="notice">Build the package to see the result.</div>
            )}
          </div>
        </section>

        {showPreview && exportFiles && (
          <section className="preview-panel">
            <div className="preview-head">
              <h3>Package Preview</h3>
              <button onClick={() => setShowPreview(false)}>Close Preview</button>
            </div>

            <div className="package-explorer">
              <div className="package-summary">
                <div>
                  <span>Files</span>
                  <strong>{Object.keys(exportFiles).length}</strong>
                </div>
                <div>
                  <span>Export</span>
                  <strong>{exportDir ? "Ready" : "-"}</strong>
                </div>
                <div>
                  <span>Receipt</span>
                  <strong>{receiptHash ? "Verified" : "-"}</strong>
                </div>
              </div>

              {intelligence && (
                <div className="intelligence-panel">
                  <h3>Repo Intelligence</h3>

                  <div className="intel-grid">
                    <div>
                      <span>Languages</span>
                      <strong>{(intelligence.languages || []).join(", ") || "Not detected"}</strong>
                    </div>

                    <div>
                      <span>Package managers</span>
                      <strong>{(intelligence.package_managers || []).join(", ") || "Not detected"}</strong>
                    </div>

                    <div>
                      <span>API candidates</span>
                      <strong>{(intelligence.api_candidates || []).length}</strong>
                    </div>

                    <div>
                      <span>Schema candidates</span>
                      <strong>{(intelligence.schema_candidates || []).length}</strong>
                    </div>

                    <div>
                      <span>Docs</span>
                      <strong>{(intelligence.docs || []).length ? "Found" : "Not detected"}</strong>
                    </div>

                    <div>
                      <span>License</span>
                      <strong>{(intelligence.license_files || []).length ? "Found" : "Not detected"}</strong>
                    </div>
                  </div>

                  {(intelligence.risk_notes || []).length > 0 && (
                    <div className="risk-notes">
                      <h4>Review notes</h4>
                      {(intelligence.risk_notes || []).map((note, index) => (
                        <p key={index}>{note}</p>
                      ))}
                    </div>
                  )}
                </div>
              )}

              {clauses && (
                <div className="clauses-panel">
                  <h3>Contract Clauses</h3>
                  <p>{clauses.clause_count || 0} machine-readable clauses generated from repo intelligence.</p>

                  <div className="clauses-list">
                    {(clauses.clauses || []).map((clause, index) => (
                      <div className={"clause-card " + (clause.severity || "info")} key={index}>
                        <div>
                          <strong>{clause.title}</strong>
                          <span>{clause.type} Â· {clause.severity}</span>
                        </div>

                        {(clause.evidence || []).length > 0 && (
                          <ul>
                            {(clause.evidence || []).slice(0, 5).map((item, i) => (
                              <li key={i}>{item}</li>
                            ))}
                          </ul>
                        )}
                      </div>
                    ))}
                  </div>
                </div>
              )}

              {projectSummary && (
                <div className="project-summary">
                  <div>
                    <span>Scanned files</span>
                    <strong>{projectSummary.fileCount}</strong>
                  </div>

                  <div>
                    <span>Top extensions</span>
                    <p>{projectSummary.topExt.map(([k,v]) => `${k} ${v}`).join(" ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· ") || "-"}</p>
                  </div>

                  <div>
                    <span>Top folders</span>
                    <p>{projectSummary.topFolders.map(([k,v]) => `${k} ${v}`).join(" ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬ÃƒÂ¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã‚Â¦ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã¢â‚¬Â ÃƒÂ¢Ã¢â€šÂ¬Ã¢â€žÂ¢ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã¢â‚¬Â¦Ãƒâ€šÃ‚Â¡ÃƒÆ’Ã†â€™Ãƒâ€ Ã¢â‚¬â„¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€¦Ã‚Â¡ÃƒÆ’Ã†â€™ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡ÃƒÆ’Ã¢â‚¬Å¡Ãƒâ€šÃ‚Â· ") || "-"}</p>
                  </div>
                </div>
              )}

              <div className="explorer-grid">
                <div className="file-list">
                  {Object.keys(exportFiles).map((name) => (
                    <button
                      key={name}
                      className={selectedExportFile === name ? "file-tab active" : "file-tab"}
                      onClick={() => setSelectedExportFile(name)}
                    >
                      {name}
                    </button>
                  ))}
                </div>

                <div className="file-reader">
                  <h4>{selectedExportFile || "No file selected"}</h4>
                  <pre>{selectedExportFile ? exportFiles[selectedExportFile] : "Select a file."}</pre>
                </div>
              </div>
            </div>
          </section>
        )}

        <section className="advanced">
          <button onClick={() => setShowTech(!showTech)}>
            {showTech ? "Hide verification log" : "Show verification log"}
          </button>

          {showTech && (
            <div className="details">
              <h3>Verification Evidence</h3>
              <code>Release: {releaseDir || "-"}</code>
              <code>Export: {exportDir || "-"}</code>
              <code>Receipt: {receipt || "-"}</code>
              <code>Receipt SHA-256: {receiptHash || "-"}</code>
              <h3>Technical log</h3>
              <pre>{log || "No log yet."}</pre>
            </div>
          )}
        </section>
      </main>
    </div>
  );
}
