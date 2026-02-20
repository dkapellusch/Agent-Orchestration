const fs = require("fs");
const os = require("os");
const path = require("path");

const THRESHOLD = ((v) => (Number.isFinite(v) && v > 0 ? v : 150))(parseInt(process.env.RPI_LEARN_THRESHOLD || "150", 10));
const ERROR_THRESHOLD = 5;
const REJECTION_THRESHOLD = 2;
const RETRY_CLUSTER_THRESHOLD = 2;
const INTERRUPT_THRESHOLD = 3;

function interruptLogPath(sessionId) {
  return path.join(os.tmpdir(), `rpi-learn-interrupts-${sessionId}`);
}

let input = "";
process.stdin.on("data", (chunk) => (input += chunk));
process.stdin.on("end", () => {
  try {
    const hook = JSON.parse(input);
    const sessionId = hook.session_id;
    if (!sessionId) process.exit(0);

    // Record interrupt and exit — no transcript analysis needed
    if (hook.hook_event_name === "PostToolUseFailure" && hook.is_interrupt) {
      const toolName = hook.tool_name || "unknown";
      fs.appendFileSync(interruptLogPath(sessionId), toolName + "\n");
      process.exit(0);
    }

    const transcriptPath = hook.transcript_path;
    if (!transcriptPath || !fs.existsSync(transcriptPath)) process.exit(0);

    // Prevent path traversal — only read transcripts under ~/.claude/
    const claudeDir = path.join(os.homedir(), ".claude");
    const resolved = fs.realpathSync(transcriptPath);
    if (!resolved.startsWith(claudeDir + path.sep)) process.exit(0);

    const stateFile = path.join(os.tmpdir(), `rpi-learn-prompted-${sessionId}`);
    if (fs.existsSync(stateFile)) process.exit(0);

    const transcript = fs.readFileSync(transcriptPath, "utf8");
    const lines = transcript.split("\n").filter(Boolean);

    const userMessageCount = (transcript.match(/"role":"user"/g) || []).length;

    const interrupts = readInterrupts(sessionId);
    const struggles = detectStruggles(lines, interrupts);

    if (struggles.hasStruggles) {
      fs.writeFileSync(stateFile, "");
      const toolList = [...struggles.errorTools].join(", ") || "unknown";
      const interruptDetail = interrupts.count > 0
        ? `${interrupts.count} user interrupts (Esc) on tools: ${[...interrupts.tools].join(", ")}. `
        : "";
      const reason = [
        `Session struggle analysis: ${struggles.errorCount} tool errors, `,
        `${struggles.retryClusterCount} retry clusters, `,
        `${struggles.rejectionCount} user rejections, `,
        `${interruptDetail}`,
        `Struggled tools: ${toolList}. `,
        `Use the Task tool (with run_in_background: true) to spawn a general-purpose subagent that: `,
        `(1) reads the full transcript at ${transcriptPath}, `,
        `(2) identifies the specific workflows/tools that caused trouble, `,
        `(3) pays special attention to user interrupts — the user hit Escape to stop Claude, which signals the approach was wrong or taking too long, `,
        `(4) suggests creating a skill (SKILL.md) for any workflow that took >3 attempts, `,
        `(5) captures debugging insights into memory via /rpi-learn patterns. `,
        `Present findings to the user before writing anything.`,
      ].join("");

      const output = JSON.stringify({
        decision: "block",
        reason,
        systemMessage:
          "Session struggle detected \u2014 analyzing for skill opportunities",
      });
      process.stdout.write(output + "\n");
    } else if (userMessageCount >= THRESHOLD) {
      fs.writeFileSync(stateFile, "");
      process.stderr.write(
        `Reminder: This was a substantial session (${userMessageCount} user messages). Consider running /rpi-learn to capture learnings.\n`
      );
    }
  } catch {
    process.exit(0);
  }
});

function readInterrupts(sessionId) {
  const logFile = interruptLogPath(sessionId);
  if (!fs.existsSync(logFile)) return { count: 0, tools: new Set() };
  const entries = fs.readFileSync(logFile, "utf8").split("\n").filter(Boolean);
  return { count: entries.length, tools: new Set(entries) };
}

function detectStruggles(lines, interrupts) {
  let errorCount = 0;
  const errorTools = new Set();
  let rejectionCount = 0;
  let retryClusterCount = 0;
  const recentToolNames = [];
  let clusterCooldown = 0;

  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    if (line.includes('"is_error":true') && !line.includes("Sibling tool call errored")) {
      errorCount++;
      const toolMatch = line.match(/"tool_use_id":"([^"]+)"/);
      if (toolMatch) {
        for (let j = Math.max(0, i - 5); j < i; j++) {
          const nameMatch = lines[j].match(/"name":"([^"]+)"/);
          if (nameMatch && lines[j].includes('"type":"tool_use"')) {
            errorTools.add(nameMatch[1]);
            break;
          }
        }
      }
    }

    if (line.includes("The user doesn't want to proceed")) {
      rejectionCount++;
    }

    if (line.includes('"type":"tool_use"')) {
      const nameMatch = line.match(/"name":"([^"]+)"/);
      if (nameMatch) {
        recentToolNames.push(nameMatch[1]);
        if (recentToolNames.length > 5) recentToolNames.shift();
        if (clusterCooldown > 0) {
          clusterCooldown--;
        } else if (recentToolNames.length >= 3) {
          const last = recentToolNames[recentToolNames.length - 1];
          let consecutive = 0;
          for (let k = recentToolNames.length - 1; k >= 0 && recentToolNames[k] === last; k--) consecutive++;
          if (consecutive >= 3) {
            retryClusterCount++;
            clusterCooldown = 3;
          }
        }
      }
    }
  }

  const hasStruggles =
    errorCount >= ERROR_THRESHOLD ||
    rejectionCount >= REJECTION_THRESHOLD ||
    retryClusterCount >= RETRY_CLUSTER_THRESHOLD ||
    interrupts.count >= INTERRUPT_THRESHOLD;

  // Merge interrupted tools into errorTools for reporting
  for (const t of interrupts.tools) errorTools.add(t);

  return {
    hasStruggles,
    errorCount,
    errorTools,
    rejectionCount,
    retryClusterCount,
  };
}
