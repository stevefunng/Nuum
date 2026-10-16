import type { WorkSnapshot } from "@nuum/protocol";

/** One renderer is one replica. Cached projection and its watermark move together. */
export class RoomSnapshotReplica {
  private readonly rooms = new Map<string, WorkSnapshot>();

  get(roomId: string): WorkSnapshot | undefined { return this.rooms.get(roomId); }
  appliedThroughSeq(roomId: string): number { return this.get(roomId)?.throughSeq ?? 0; }

  apply(snapshot: WorkSnapshot): WorkSnapshot {
    const id = snapshot.profile.id;
    const previous = this.rooms.get(id);
    if (previous && snapshot.throughSeq < previous.throughSeq) return previous;
    if (snapshot.events.length !== snapshot.throughSeq || snapshot.events.some((event, index) => event.workId !== id || event.seq !== index + 1)) {
      throw new Error("Room snapshot is not a complete event prefix");
    }
    if (previous && previous.events.some((event, index) => snapshot.events[index]?.id !== event.id)) {
      throw new Error("Room snapshot conflicts with the applied event prefix");
    }
    const next = previous && previous.catalog.revision > snapshot.catalog.revision
      ? { ...snapshot, catalog: previous.catalog } : snapshot;
    this.rooms.set(id, next);
    return next;
  }
}
