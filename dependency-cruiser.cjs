/** @type {import('dependency-cruiser').IConfiguration} */
module.exports = {
  forbidden: [
    {
      name: "kernel-must-not-depend-on-host-or-desktop",
      comment: "Engine cannot depend on product Host, desktop, or UI.",
      severity: "error",
      from: { path: "^packages/kernel|^packages/sandbox|^packages/tools|^packages/executor" },
      to: { path: "^packages/host|^apps/desktop|^packages/ui" }
    },
    {
      name: "host-must-not-import-kernel-implementation",
      comment: "Host talks to Kernel only via RPC/protocol, never kernel internals.",
      severity: "error",
      from: { path: "^packages/host" },
      to: { path: "^packages/kernel|^packages/sandbox|^packages/tools|^packages/executor|^packages/ui|^apps/desktop" }
    },
    {
      name: "ui-must-not-depend-on-backend",
      severity: "error",
      from: { path: "^packages/ui" },
      to: { path: "^packages/host|^packages/kernel|^packages/sandbox|^packages/tools|^packages/executor|^apps/" }
    },
    {
      name: "kernel-and-sandbox-must-not-import-executor",
      severity: "error",
      from: { path: "^packages/kernel|^packages/sandbox|^packages/tools" },
      to: { path: "^packages/executor" }
    },
    {
      name: "executor-must-not-import-kernel",
      severity: "error",
      from: { path: "^packages/executor" },
      to: { path: "^packages/kernel" }
    }
  ],
  options: {
    doNotFollow: { path: "node_modules" },
    tsPreCompilationDeps: true,
    enhancedResolveOptions: {
      exportsFields: ["exports"],
      conditionNames: ["import", "require"]
    }
  }
};
