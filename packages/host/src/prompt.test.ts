import assert from "node:assert/strict";
import { test } from "node:test";
import { profileDriftNotice, renderSystemPrompt, type SystemPromptInput } from "./prompt.js";

function input(overrides: Partial<SystemPromptInput> = {}): SystemPromptInput {
  return {
    identity: { name: "Scout", description: "scans things" },
    paths: {
      profile: "/Users/me/.nuum/agents/a1/profile.json",
      settings: "/Users/me/.nuum/agents/a1/settings.json",
      agentDir: "/Users/me/.nuum/agents/a1",
      scratchDir: "/Users/me/.nuum/agents/a1/scratch"
    },
    environment: {
      os: "darwin 25.5.0",
      now: new Date("2026-09-03T09:16:00Z"),
      timeZone: "Asia/Shanghai",
      projectRoot: "/Users/me/dev/thing",
      permission: "no sandbox — anything goes."
    },
    ...overrides
  };
}

test("segments come out in the designed order", () => {
  const render = renderSystemPrompt(input());
  assert.deepEqual(
    render.segments.map((segment) => segment.id),
    ["identity", "agent-profile", "environment", "tool-guidance", "send-message", "tone"]
  );
  // 段间是空行，段内是 markdown 标题 —— 不给整段套 XML。
  assert.equal(render.text, render.segments.map((segment) => segment.text).join("\n\n"));
  assert.equal(render.text.includes("<identity>"), false);
});

test("the machine's real absolute paths reach the prompt", () => {
  const render = renderSystemPrompt(input());
  for (const expected of [
    "/Users/me/.nuum/agents/a1/profile.json",
    "/Users/me/.nuum/agents/a1/settings.json",
    "/Users/me/dev/thing"
  ]) {
    assert.ok(render.text.includes(expected), `prompt must name ${expected}`);
  }
});

test("a missing project directory says so instead of rendering a hole", () => {
  const render = renderSystemPrompt(input({ environment: { ...input().environment, projectRoot: null } }));
  assert.ok(render.text.includes("no project directory"));
  assert.equal(render.text.includes("Your project directory:"), false);
});

test("an empty description drops its line, not the whole segment", () => {
  const render = renderSystemPrompt(input({ identity: { name: "Scout", description: "" } }));
  const profile = render.segments.find((segment) => segment.id === "agent-profile")!;
  assert.equal(profile.text.includes("Description:"), false);
  assert.ok(profile.text.includes("Title: Scout"));
});

test("an agent with no name at all still gets a usable profile segment", () => {
  const render = renderSystemPrompt(input({ identity: { name: "", description: "" } }));
  const profile = render.segments.find((segment) => segment.id === "agent-profile")!;
  assert.equal(profile.text.includes("Title:"), false);
  // 名字和描述都空时段落仍要留着 —— 它还带着 profile.json 的路径。
  assert.ok(profile.text.includes("/Users/me/.nuum/agents/a1/profile.json"));
});

test("the date is rendered to the day, so the prompt survives the clock ticking", () => {
  const morning = renderSystemPrompt(input());
  const evening = renderSystemPrompt(
    input({ environment: { ...input().environment, now: new Date("2026-09-03T14:47:31Z") } })
  );
  // 带上时分秒的话每一轮 system prompt 都不同，前缀缓存一次都命中不了。
  assert.equal(morning.text, evening.text);
  assert.ok(morning.text.includes("Thursday Sep 3, 2026"));
  assert.equal(/\d\d:\d\d/.test(morning.text), false);
});

test("the date follows the given time zone, not the machine's", () => {
  // 同一瞬间在上海已是 9/4 凌晨，在洛杉矶还是 9/3 上午。
  const late = new Date("2026-09-03T17:30:00Z");
  const shanghai = renderSystemPrompt(input({ environment: { ...input().environment, now: late } }));
  const la = renderSystemPrompt(
    input({ environment: { ...input().environment, now: late, timeZone: "America/Los_Angeles" } })
  );
  assert.ok(shanghai.text.includes("Friday Sep 4, 2026"));
  assert.ok(la.text.includes("Thursday Sep 3, 2026"));
});

test("a frozen profile segment is used verbatim and the live one is still reported", () => {
  const render = renderSystemPrompt(input({ frozenProfile: "## Agent profile\n\nTitle: Old Name" }));
  const profile = render.segments.find((segment) => segment.id === "agent-profile")!;
  assert.equal(profile.text, "## Agent profile\n\nTitle: Old Name");
  // 冻结的是输出，实时渲染仍要回给调用方，否则没法判断漂没漂。
  assert.ok(render.liveProfile.includes("Title: Scout"));
  assert.equal(render.text.includes("Title: Scout"), false);
});

test("drift is reported only when the identity actually moved", () => {
  const identity = { name: "Scout", description: "scans things" };
  assert.equal(profileDriftNotice(identity, { ...identity }), null);

  const renamed = profileDriftNotice(identity, { name: "Ranger", description: "scans things" });
  assert.ok(renamed);
  assert.ok(renamed.includes("Current name: Ranger"));
  assert.ok(renamed.includes("Current description: scans things"));

  const described = profileDriftNotice(identity, { name: "Scout", description: "" });
  assert.ok(described);
  assert.ok(described.includes("(no description)"));
});
