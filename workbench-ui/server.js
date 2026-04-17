import express from "express";
import { spawn } from "child_process";

const app = express();
app.use(express.json());

const PORT = 5175;

app.get("/api/health", (_req, res) => {
  res.json({ ok: true, service: "workbench-ui-bridge" });
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

app.listen(PORT, () => {
  console.log(`WORKBENCH_UI_BRIDGE_OK http://localhost:${PORT}`);
});
