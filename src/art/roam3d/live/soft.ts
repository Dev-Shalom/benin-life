// Live players: other players are SOFT colliders (pure TypeScript). You cannot walk through them, nothing shoves anybody, and nobody can
// be trapped: if you push against someone for 1.5 s without getting anywhere, players become passable for each other for a moment
// (and stay so until you no longer overlap). Both phones run the same rule for their own body, so it works from either side.
export class StuckGuard {
  private blocked = 0;
  private until = 0;
  /** Seconds a push against a player may last before it gives way. */
  readonly after: number;
  /** Seconds of passing through. */
  readonly pass: number;
  constructor(after = 1.5, pass = 2.5) {
    this.after = after;
    this.pass = pass;
  }

  /**
   * Call once per step. `wanted` = the speed the player asks for (m/s), `real` = what he got, `touching` = a live player is within reach,
   * `overlapping` = standing inside somebody. Returns true when players are passable right now.
   */
  step(simT: number, dt: number, wanted: number, real: number, touching: boolean, overlapping: boolean): boolean {
    if (touching && wanted > 0.5 && real < wanted * 0.35) this.blocked += dt;
    else this.blocked = Math.max(0, this.blocked - dt * 2);
    if (this.blocked >= this.after) {
      this.until = simT + this.pass;
      this.blocked = 0;
    }
    // never end the pass while still standing inside somebody
    if (overlapping && simT < this.until + 0.01) this.until = Math.max(this.until, simT + 0.4);
    return simT < this.until;
  }

  passable(simT: number): boolean {
    return simT < this.until;
  }

  reset() {
    this.blocked = 0;
    this.until = 0;
  }
}
