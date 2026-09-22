export class RequestEpoch {
  private value = 0
  begin() { return ++this.value }
  invalidate() { this.value += 1 }
  owns(owner: number) { return owner === this.value }
}

export function retainOwnedStream(epoch: RequestEpoch, owner: number, stream: MediaStream, allowed = true) {
  if (allowed && epoch.owns(owner)) return true
  stream.getTracks().forEach(track => track.stop())
  return false
}
