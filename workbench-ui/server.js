import express from "express";
import cors from "cors";
import { spawn } from "child_process";

const app = express();
app.use(cors());
app.use(express.json());

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
