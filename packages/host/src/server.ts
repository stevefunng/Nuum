import {
  ProactiveConfigureParams,
  ProactiveCheckParams,
  AgentCreateParams,
  AgentIdParams,
  AgentSendParams,
  AgentAnswerWidgetParams,
  AgentToolDecision,
  AgentUpdateParams,
  HostErrorCode,
  HostMethods,
  RpcError,
  SettingsSetParams,
  TranscriptQuery,
  WorkCatalogAddParams,
  WorkCatalogRemoveParams,
  WorkCreateParams,
  WorkDispatchParams,
  WorkContinueParams,
  WorkIdParams,
  WorkMemberAttachParams,
  WorkMemberDetachParams,
  WorkMemberMoveParams,
  WorkPostMessageParams,
  WorkTaskAssignParams,
  WorkTaskCreateParams,
  WorkTaskTranscriptParams,
  WorkTaskTransitionParams,
  WorkUpdateParams
} from "@nuum/protocol";
import { JsonRpcPeer, createStdioDuplex } from "@nuum/protocol/node";
import { HostRuntime, type HostRuntimeOptions } from "./runtime.js";

export async function createHostServer(options: HostRuntimeOptions): Promise<HostRuntime> {
  const runtime = new HostRuntime(options);
  await runtime.start();
  const peer = new JsonRpcPeer(createStdioDuplex(process.stdin, process.stdout));
  runtime.setEmitter((method, params) => peer.notify(method, params));

  peer.setHandler(async (method, raw) => {
    switch (method) {
      case HostMethods.sysHello:
        return { name: "nuum-host", version: "0.1.0" };
      case HostMethods.sysPing:
        return { ok: true, at: Date.now() };
      case HostMethods.sysShutdown:
        setImmediate(() => {
          void runtime.dispose().finally(() => process.exit(0));
        });
        return { ok: true };
      case HostMethods.settingsGet:
        return runtime.getPublicSettings();
      case HostMethods.settingsSet:
        return runtime.setSettings(SettingsSetParams.parse(raw));
      case HostMethods.agentCreate:
        return runtime.createAgent(AgentCreateParams.parse(raw ?? {}));
      case HostMethods.agentList:
        return runtime.listAgents();
      case HostMethods.agentGet:
        return runtime.getAgent(AgentIdParams.parse(raw).id);
      case HostMethods.agentUpdate:
        return runtime.updateAgent(AgentUpdateParams.parse(raw));
      case HostMethods.agentDelete:
        return runtime.deleteAgent(AgentIdParams.parse(raw).id);
      case HostMethods.agentGetTranscript: {
        const params = TranscriptQuery.parse(raw);
        return runtime.getTranscript(params.id, params.beforeSeq, params.limit);
      }
      case HostMethods.agentSend: {
        const params = AgentSendParams.parse(raw);
        return runtime.send(params.id, params.content, { attachments: params.attachments });
      }
      case HostMethods.agentAnswerWidget: {
        const params = AgentAnswerWidgetParams.parse(raw);
        return runtime.answerWidget(params.id, params.messageId, params.value);
      }
      case HostMethods.agentCancel:
        return runtime.cancel(AgentIdParams.parse(raw).id);
      case HostMethods.agentApproveTool:
      case HostMethods.agentDenyTool: {
        const params = AgentToolDecision.parse(raw);
        return runtime.decide(
          params.id,
          params.toolCallId,
          method === HostMethods.agentDenyTool ? "deny" : params.resolution
        );
      }
      case HostMethods.workCreate:
        return runtime.createWork(WorkCreateParams.parse(raw));
      case HostMethods.workList:
        return runtime.listWorks();
      case HostMethods.workGet:
        return runtime.getWork(WorkIdParams.parse(raw).id);
      case HostMethods.workUpdate:
        return runtime.updateWork(WorkUpdateParams.parse(raw));
      case HostMethods.workPostMessage:
        return runtime.postWorkMessage(WorkPostMessageParams.parse(raw));
      case HostMethods.workMemberAttach:
        return runtime.attachWorkMember(WorkMemberAttachParams.parse(raw));
      case HostMethods.workMemberDetach:
        return runtime.detachWorkMember(WorkMemberDetachParams.parse(raw));
      case HostMethods.workMemberMove:
        return runtime.moveWorkMember(WorkMemberMoveParams.parse(raw));
      case HostMethods.workTaskTranscript:
        return runtime.getWorkTaskTranscript(WorkTaskTranscriptParams.parse(raw));
      case HostMethods.workTaskCreate:
        return runtime.createWorkTask(WorkTaskCreateParams.parse(raw));
      case HostMethods.workTaskAssign:
        return runtime.assignWorkTask(WorkTaskAssignParams.parse(raw));
      case HostMethods.workTaskTransition:
        return runtime.transitionWorkTask(WorkTaskTransitionParams.parse(raw));
      case HostMethods.workContinue: {
        const params = WorkContinueParams.parse(raw);
        return runtime.continueWork(params.workId, params.eventId, params.inputAfterSeq);
      }
      case HostMethods.workStopDiscussion:
        return runtime.stopWorkDiscussion(WorkIdParams.parse(raw).id);
      case HostMethods.workDispatch:
        return runtime.dispatchWork(WorkDispatchParams.parse(raw));
      case HostMethods.workCatalogAdd:
        return runtime.addWorkCatalogEntry(WorkCatalogAddParams.parse(raw));
      case HostMethods.workCatalogRemove:
        return runtime.removeWorkCatalogEntry(WorkCatalogRemoveParams.parse(raw));
      case HostMethods.proactiveGet:
        return runtime.proactive.snapshot();
      case HostMethods.proactiveConfigure:
        return runtime.proactive.configure(ProactiveConfigureParams.parse(raw));
      case HostMethods.proactiveCheck:
        return runtime.proactive.check(ProactiveCheckParams.parse(raw).agentId);
      case HostMethods.toolsList:
        return runtime.tools();
      default:
        throw new RpcError(HostErrorCode.AGENT_NOT_FOUND, `Unknown host method: ${method}`);
    }
  });

  return runtime;
}
