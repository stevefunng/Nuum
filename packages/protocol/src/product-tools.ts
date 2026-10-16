import { z } from "zod";
import type { ToolDefinition } from "./domain.js";
import { AgentTags } from "./domain.js";
import { OutboundMessage } from "./transcript.js";

/**
 * 委派工具（Host 执行）的名字与 schema。放 protocol 是因为它本来就是
 * Host ↔ Kernel 契约的一部分：Kernel 从这里拿 definition 给模型看，Host 从
 * 同一份拿 schema 校验参数。这样 `@nuum/host` 不必依赖 `@nuum/tools`，
 * 包边界一条规则都不用改（§3.3）。
 */
export const DelegatedToolNames = {
  createTask: "CreateTask",
  claimTask: "ClaimTask",
  readTask: "ReadTask",
  sendMessage: "SendMessage",
  updateState: "update_state",
  createAgent: "CreateAgent",
  updateAgent: "UpdateAgent",
  sendToAgent: "SendToAgent",
  readAgentTranscript: "ReadAgentTranscript",
  checkAgent: "CheckAgent",
  stopAgent: "StopAgent",
  postToWork: "PostToWork",
  handoffTask: "HandoffTask",
  readWorkTimeline: "ReadWorkTimeline",
  runWorkCli: "RunWorkCLI",
  delegateWork: "DelegateWork"
} as const;

/**
 * 参数校验先于 OutboundMessage 解析：union 成员会剥掉未知键，跨类型的字段误用
 * （如把 path 搭在 type:text 上）会被静默吞掉。这里在原始参数上拦住它，并按
 * 「什么没发出去、怎么重发」教模型自纠 —— 错误文本会原样回到模型。
 */
const OUTBOUND_FIELD_TYPES: Record<string, readonly string[]> = {
  content: ["text"],
  images: ["text"],
  path: ["attachment"],
  caption: ["attachment"],
  widget: ["widget"],
  props: ["widget"]
};

export const SendMessageParams = z
  .record(z.unknown())
  .superRefine((args, ctx) => {
    if (typeof args.type !== "string") return;
    for (const [field, allowed] of Object.entries(OUTBOUND_FIELD_TYPES)) {
      if (field in args && args[field] !== undefined && !allowed.includes(args.type)) {
        ctx.addIssue({
          code: z.ZodIssueCode.custom,
          path: [field],
          message: `${field} is only valid with type:${allowed.join(" or ")}, not type:${args.type} — it would be silently dropped. Nothing was sent. Re-send as separate SendMessage calls, one per type.`
        });
      }
    }
    // 必填字段在原始参数上拦，错误文案自己写 —— union 的通用报错说不出
    // 「哪个字段、怎么改」，模型只能靠这句话自纠。
    if (args.type === "text" && (args.content === undefined || args.content === "") && args.text === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["content"],
        message: "content is required when type is text. Nothing was sent."
      });
    }
    if (args.type === "attachment" && (args.path === undefined || args.path === "")) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["path"],
        message: "path is required when type is attachment. Nothing was sent."
      });
    }
    if (args.type === "widget" && args.widget === undefined) {
      ctx.addIssue({
        code: z.ZodIssueCode.custom,
        path: ["widget"],
        message: "widget is required when type is widget: an object with prompt and options. Nothing was sent."
      });
    }
  })
  .pipe(OutboundMessage);
export type SendMessageParams = z.infer<typeof SendMessageParams>;

export const UpdateStateParams = z.discriminatedUnion("target", [
  z.object({
    target: z.literal("profile"),
    action: z.literal("set"),
    name: z.string().optional(),
    description: z.string().optional(),
    tags: AgentTags.optional()
  }),
  z.object({
    target: z.literal("memory"),
    action: z.enum(["write", "forget"]),
    fact: z.string(),
    tier: z.enum(["profile", "log", "note"]).default("log")
  }),
  z.object({
    target: z.literal("settings"),
    action: z.literal("set"),
    project_root: z.string().nullable()
  })
]);
export type UpdateStateParams = z.infer<typeof UpdateStateParams>;

export const CreateAgentParams = z.object({
  name: z.string(),
  description: z.string(),
  first_message: z.string().optional()
});
export type CreateAgentParams = z.infer<typeof CreateAgentParams>;

export const UpdateAgentParams = z.object({
  agent_id: z.string(),
  name: z.string().optional(),
  description: z.string().optional(),
  tags: AgentTags.optional()
});
export type UpdateAgentParams = z.infer<typeof UpdateAgentParams>;

export const SendToAgentParams = z.object({
  agent_id: z.string(),
  message: z.string(),
  priority: z.boolean().optional()
});
export type SendToAgentParams = z.infer<typeof SendToAgentParams>;

export const ReadAgentTranscriptParams = z.object({
  agent_id: z.string(),
  limit: z.number().int().positive().max(200).optional()
});
export type ReadAgentTranscriptParams = z.infer<typeof ReadAgentTranscriptParams>;

export const CheckAgentParams = z.object({ agent_id: z.string() });
export type CheckAgentParams = z.infer<typeof CheckAgentParams>;

export const StopAgentParams = z.object({ agent_id: z.string() });
export type StopAgentParams = z.infer<typeof StopAgentParams>;

export const CreateTaskParams = z.object({ title: z.string().trim().min(1), description: z.string().default(""), acceptanceCriteria: z.array(z.string()).default([]), assigneeIds: z.array(z.string()).default([]) });
export type CreateTaskParams = z.infer<typeof CreateTaskParams>;
export const ClaimTaskParams = z.object({ taskId: z.string().min(1), expectedRevision: z.number().int().positive() });
export type ClaimTaskParams = z.infer<typeof ClaimTaskParams>;
export const ReadTaskParams = z.object({ taskId: z.string().optional() });
export type ReadTaskParams = z.infer<typeof ReadTaskParams>;

export const PostToWorkParams = z.object({ message: z.string().min(1) });
export type PostToWorkParams = z.infer<typeof PostToWorkParams>;

export const HandoffTaskParams = z.object({
  summary: z.string().min(1),
  status: z.enum(["review", "blocked", "done"]),
  blocker_reason: z.string().min(1).optional(),
  deliverables: z.array(z.object({
    name: z.string().min(1),
    uri: z.string().min(1),
    mime_type: z.string().optional()
  })).default([])
});
export type HandoffTaskParams = z.infer<typeof HandoffTaskParams>;

export const WorkSendMessageParams = z.object({
  type: z.literal("text"),
  content: z.string().trim().min(1),
  cardAction: z.object({
    status: z.enum(["review", "blocked"]),
    blocker_reason: z.string().trim().min(1).optional(),
    expectedRevision: z.number().int().positive().optional(),
    deliverables: HandoffTaskParams.shape.deliverables
  }).optional()
}).strict();
export type WorkSendMessageParams = z.infer<typeof WorkSendMessageParams>;

export const ReadWorkTimelineParams = z.object({ beforeSeq: z.number().int().positive().optional(), afterSeq: z.number().int().nonnegative().optional(), limit: z.number().int().positive().max(100).default(30) });
export type ReadWorkTimelineParams = z.infer<typeof ReadWorkTimelineParams>;

export const RunWorkCliParams = z.object({
  capability_id: z.string().min(1),
  args: z.array(z.string()).default([])
});
export type RunWorkCliParams = z.infer<typeof RunWorkCliParams>;

export const DelegateWorkParams = z.object({
  agent_id: z.string().min(1),
  instruction: z.string().min(1),
  task_id: z.string().min(1).optional()
});
export type DelegateWorkParams = z.infer<typeof DelegateWorkParams>;

const AGENT_ID = { type: "string", description: "The agent's id, as listed in your teammate directory." };

export const DELEGATED_TOOL_DEFINITIONS: ToolDefinition[] = [
  { name: "CreateTask", description: "Create a ready card in this NunuBar. You become its permanent owner. Include acceptance criteria and optional workers; DelegateWork starts their independent card sessions.", inputSchema: { type: "object", required: ["title"], properties: { title: { type: "string" }, description: { type: "string" }, acceptanceCriteria: { type: "array", items: { type: "string" } }, assigneeIds: { type: "array", items: { type: "string" } } } }, mutating: false },
  { name: "ClaimTask", description: "Atomically join or start a ready card as a worker, without changing its creator-owner. Blocked cards require human confirmation. ReadTask supplies expectedRevision.", inputSchema: { type: "object", required: ["taskId", "expectedRevision"], properties: { taskId: { type: "string" }, expectedRevision: { type: "integer" } } }, mutating: false },
  { name: "ReadTask", description: "Read a task's current state and revision, or list this NunuBar's tasks when taskId is omitted.", inputSchema: { type: "object", properties: { taskId: { type: "string" } } }, mutating: false },
  {
    name: DelegatedToolNames.sendMessage,
    description:
      "Say something to the user in their chat with you. This is your only voice: the user only ever sees the content of SendMessage calls, and plain text you write is an invisible scratchpad — so a reply counts only once it is inside SendMessage, including short casual ones like \"Got it\". Ending a turn where someone is waiting on you without SendMessage means they see silence. Post updates as you work, not just at the end: a real result, decision, or blocker is worth a message; routine mechanics and retries are not. Results count as delivered only inside SendMessage — an opening acknowledgement never discharges a result you owe (ack != delivery), so the last thing you do on a turn that produced one is SendMessage it. Use {\"type\":\"text\",\"content\":\"...\"} for normal messages; when a reply has two or three beats, send them as a short run of separate SendMessage calls, like quick texts, rather than one welded paragraph. Attach images to the text they belong with via images (they render inside the same bubble); use type:attachment only when the file IS the whole message. Use {\"type\":\"widget\",\"widget\":{...}} to ask a question with selectable options — sparingly: by default decide and proceed, reserving widgets for consequential or destructive go/no-go calls, true ambiguity you cannot resolve yourself, or something only the user knows. Every option must be a real, verified choice; a user's selection arrives as their next message. Sending a widget ends your turn — make it your last action.",
    inputSchema: {
      type: "object",
      required: ["type"],
      properties: {
        type: { type: "string", enum: ["text", "attachment", "widget"] },
        content: { type: "string", description: "Required when type=text: the message to show the user." },
        images: {
          type: "array",
          description: "Optional, only with type=text: images that belong with this message; they render inside the same bubble below the text.",
          items: {
            type: "object",
            required: ["path"],
            properties: {
              path: { type: "string", description: "Absolute local path to the image file." },
              alt: { type: "string", description: "Short description shown on hover and as fullscreen caption." }
            }
          }
        },
        path: { type: "string", description: "Required when type=attachment: absolute path to the file." },
        caption: { type: "string", description: "For type=attachment: one line about it." },
        widget: {
          type: "object",
          description: "Required when type=widget: a question with selectable options. The chosen option's value is sent back to you as the user's reply.",
          required: ["prompt", "options"],
          properties: {
            prompt: { type: "string", description: "The question, phrased as a natural conversational sentence — never a menu instruction." },
            helpText: { type: "string", description: "Optional short help shown under the question." },
            options: {
              type: "array",
              minItems: 1,
              maxItems: 6,
              items: {
                type: "object",
                required: ["label"],
                properties: {
                  label: { type: "string", description: "Short option label shown on the card." },
                  value: { type: "string", description: "Text sent back when picked; defaults to the label. Write it like a reply the user would actually send." },
                  description: { type: "string", description: "Optional one-line explanation under the label." },
                  style: { type: "string", enum: ["default", "primary", "danger"], description: "danger marks a destructive choice; primary marks the recommended one." }
                }
              }
            },
            allowCustom: { type: "boolean", description: "Let the user type a free-text answer instead of picking an option." }
          }
        }
      }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.updateState,
    description:
      "Change your own persistent state. target=profile rewrites your own name, tags or description; target=memory records or forgets a durable fact; target=settings sets or clears your project directory. Fields you do not pass are left alone.",
    inputSchema: {
      type: "object",
      required: ["target", "action"],
      properties: {
        target: { type: "string", enum: ["profile", "memory", "settings"] },
        action: { type: "string", enum: ["set", "write", "forget"] },
        name: { type: "string", description: "For target=profile." },
        description: { type: "string", description: "For target=profile." },
        tags: { type: "array", items: { type: "string" }, description: "For target=profile: replaces all tags; pass [] to clear." },
        project_root: { type: ["string", "null"], description: "For target=settings: absolute project directory, or null to clear it." },
        fact: { type: "string", description: "For target=memory: one self-contained fact." },
        tier: {
          type: "string",
          enum: ["profile", "log", "note"],
          description: "For target=memory: profile for standing facts, log for dated ones."
        }
      }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.createAgent,
    description:
      "Create a new teammate agent with its own chat, persona, and memory. It appears in the user's sidebar immediately. You have no tool to delete an agent, so only create one when it is genuinely useful and long-lived — for a one-off task, just do the task yourself.",
    inputSchema: {
      type: "object",
      required: ["name", "description"],
      properties: {
        name: { type: "string", description: "Short, human, and distinct from existing teammates." },
        description: { type: "string", description: "What this teammate is for." },
        first_message: { type: "string", description: "Optional first instruction to wake it with." }
      }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.updateAgent,
    description: "Rename another agent or rewrite its description. Fields you do not pass are left alone.",
    inputSchema: {
      type: "object",
      required: ["agent_id"],
      properties: { agent_id: AGENT_ID, name: { type: "string" }, description: { type: "string" }, tags: { type: "array", items: { type: "string" } } }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.sendToAgent,
    description:
      "Send a message to another agent. Delivery is asynchronous and fire-and-forget, like texting: it returns immediately, and a later reply from that teammate wakes you here — never wait or poll for one in this turn. Write the message self-contained (they cannot see your chat) and lead with the point. Waking a teammate is a real side effect: message an agent only when it serves the user's goal, never relay the user's private or unfiltered words verbatim (paraphrase the actionable point instead), and messaging several agents about the same effort is a fan-out you only make when the user explicitly asked for it. Use priority to interrupt what the recipient is currently doing — for STOP / supersede / time-critical instructions, not for ordinary replies.",
    inputSchema: {
      type: "object",
      required: ["agent_id", "message"],
      properties: {
        agent_id: AGENT_ID,
        message: { type: "string", description: "Self-contained: the other agent cannot see your chat." },
        priority: { type: "boolean", description: "Interrupt its current work instead of queueing. For STOP / supersede / time-critical instructions only." }
      }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.readAgentTranscript,
    description:
      "Read the tail of another agent's chat, to see what it has been up to or what it answered. Read-only.",
    inputSchema: {
      type: "object",
      required: ["agent_id"],
      properties: { agent_id: AGENT_ID, limit: { type: "number", description: "How many entries, newest last." } }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.checkAgent,
    description:
      "Check what another agent is doing right now, without messaging or waking it. Returns whether it is running or idle, which run it is in (your user's private chat or a Work), its recent tool activity, and the path to its transcript you can read for the full play-by-play. Read-only. Use it when a teammate you are working with seems stuck, slow, or you need its current state before deciding next steps; to actually reach it, use SendToAgent.",
    inputSchema: {
      type: "object",
      required: ["agent_id"],
      properties: { agent_id: AGENT_ID },
      description: "Pass the agent's id from your teammate directory — not a name."
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.stopAgent,
    description: "Stop what another agent is currently doing. Anything queued for it is dropped too.",
    inputSchema: { type: "object", required: ["agent_id"], properties: { agent_id: AGENT_ID } },
    mutating: false
  },
  {
    name: DelegatedToolNames.postToWork,
    description: "Post a progress update to the current Work shared room.",
    inputSchema: {
      type: "object",
      required: ["message"],
      properties: { message: { type: "string" } }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.handoffTask,
    description: "Hand the current Work task back for review, report it blocked, or—when you are the coordinator—mark a reviewed task done. This also posts the summary in the shared room.",
    inputSchema: {
      type: "object",
      required: ["summary", "status"],
      properties: {
        summary: { type: "string" },
        status: { type: "string", enum: ["review", "blocked", "done"] },
        blocker_reason: { type: "string" },
        deliverables: {
          type: "array",
          items: {
            type: "object",
            required: ["name", "uri"],
            properties: { name: { type: "string" }, uri: { type: "string" }, mime_type: { type: "string" } }
          }
        }
      }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.readWorkTimeline,
    description: "Read the latest entries from the current Work timeline.",
    inputSchema: {
      type: "object",
      properties: { limit: { type: "number" }, beforeSeq: { type: "integer" }, afterSeq: { type: "integer" } }
    },
    mutating: false
  },
  {
    name: DelegatedToolNames.runWorkCli,
    description: "Run a CLI capability explicitly installed in the current Work. No shell expansion is performed.",
    inputSchema: {
      type: "object",
      required: ["capability_id"],
      properties: {
        capability_id: { type: "string" },
        args: { type: "array", items: { type: "string" } }
      }
    },
    mutating: true
  },
  {
    name: DelegatedToolNames.delegateWork,
    description: "Dispatch a room member as a worker. Specify task_id (defaults to the current card); room-only discussion must use @ in SendMessage. Workers use independent card sessions: the creator stays owner and worker results return there. Blocked cards require human confirmation before further dispatch.",
    inputSchema: {
      type: "object",
      required: ["agent_id", "instruction"],
      properties: {
        agent_id: AGENT_ID,
        instruction: { type: "string" },
        task_id: { type: "string" }
      }
    },
    mutating: false
  }
];
