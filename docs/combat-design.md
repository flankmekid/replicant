# Combat design

This file explains the design decisions behind the combat code. The code comments
give only the fact that each line needs. The reasons are here.

## Hitstun

Hitstun is how long a hit victim is frozen. It decides what combos into what.

- A combo is **true** (cannot be escaped) when the victim's hitstun outlasts the
  attacker's own recovery.
- A combo is a **read** (can be parried) when the victim comes out of stun around the
  time the next hitbox is live.

The recovery of a basic M1 is the per-weapon client cooldown
(`WeaponConfig[weapon].client.m1.cooldown`, from 0.4 s on the dagger to 1.1 s on the
greatsword). M1 hitstun is that recovery plus `M1_ADVANTAGE`, with a floor of
`M1_MIN_HITSTUN`. This keeps the link the same on every light and medium weapon,
although their speeds are different. Startup and recovery change from weapon to
weapon. The link does not. This is the same idea as a fast jab and a slow heavy jab
that both link into the same follow-up.

At `M1_ADVANTAGE = 0.20`, the next M1's startup lands while the victim is still
frozen. A landed M1 is a true combo: the victim cannot walk out or dash out. The only
escape is a parry, which is allowed during stun (see `_Shared/Block`).

- Raise `M1_ADVANTAGE` to make M1 strings harder to parry out of.
- Lower it, or make it negative, to open the parry window.

Greatsword-family weapons do not get a free M1 chain. Their M1 hitstun
(`GREATSWORD_M1_HITSTUN`, 1.0 s) is shorter than their 1.1 s recovery, so the second
M1 is a read and never guaranteed.

M2 and E are punctuation, not part of the tight M1 rhythm. They use a flat hitstun
(`M2_HITSTUN`, `E_HITSTUN`) that is generous: landing one reliably leads into M1. A
burst can escape it. A reactive parry cannot.

During weapon hitstun the victim's WalkSpeed is `HITSTUN_STUNSPEED` (1). The victim
is almost immobile, so holding S cannot walk them back out of a combo.

## M2 endlag

`CantAnything` stays on for a short time after the M2 hitbox closes. How long depends
on the result:

| Result | Constant | Purpose |
|---|---|---|
| Hit | `M2_ENDLAG_HIT` (0.1 s) | The player earned the cancel. They can chain into M1, E, a skill, or a dash, so M2 works as a combo extender. |
| Whiff | `M2_ENDLAG_WHIFF` (0.65 s) | Missing a guard break still costs something. Otherwise M2 is a free spam button with no read attached. |

The endlag does not touch the M2 cooldown (`cfg.postCooldown`, 3 to 7 s). A player
still cannot chain M2 into another M2. M2 opens a window. It does not become the
window.

## Whiff recovery for M1 and E

M1 and E have one recovery for hit and whiff (the M1 client cooldown and
`cfg.eRecovery`). `M1E_WHIFF_RECOVERY` adds an extra `CantAnything` lock only when the
swing hit nothing. A landed swing never gets it, so combos keep their timing. Only a
missed swing costs more.

## M2 as a combo ender

M2 always works as a standalone heavy attack. When it lands while an M1 combo is open
(the server's `Combo` counter is at `M2_FINISHER_MIN_COMBO` or higher), it becomes a
combo ender: it launches the victim up and back and stuns longer, instead of the plain
push. The combo ender is the move that cashes in an M1 string. `Combo` is 1-indexed
and set on the first M1, so 2 means "at least two M1s, and the combo window has not
run out."

RunM2 makes this decision once, before the swing starts, so the whole swing commits
to one behavior.

## Uppercut and juggle

The uppercut (slide + M1) lifts the attacker and the victim into a short hang. The
attacker can then follow with an M1 string, E, or M2 while both are in the air.

- The hang is a real hold against gravity for `LAUNCH_WINDOW`, not a one-frame pop.
- Both fighters get the `Launched` attribute for the hang. With it, M1 uses the
  ground combo in the air instead of the aerial attack.
- The victim is held in a stun that can be hit. The victim is not ragdolled, because a
  ragdoll falls out of hitboxes and cannot be juggled cleanly.
- The attacker rises only when the uppercut connects. A whiffed uppercut is a
  committed swing that missed and can be punished like any M1. The attacker and the
  victim always leave the ground together.

## Running attack

The running attack (lunge M1) does not take the `setSpeed` slow of a standing M1.

The slow is right for a standing M1: it is the commitment, the tell that the defender
reads. On a running attack it defeats itself. The lunge closes about 15 studs. Then
the slow pins the attacker at WalkSpeed 4 while a sprinting target keeps moving at
about 28. In the 0.6 s from the end of the lunge to the hitbox, the target takes back
13 to 15 studs, which is every stud the lunge gained. A bigger hitbox does not fix
this.

## Lunge steering

`LungeService` runs the lunge on the server.

The boost always fires. It is the move: a forward burst, then the animation, then the
swing. It needs no target and works into empty air.

The chase engages only when the target runs away. Then the lunge steers toward the
target and keeps a follow drive through the windup, so a sprinter cannot outrun the
running attack. Against a target who faces the attacker and holds ground, there is
only the plain step-in, and the attacker has to reach them. A chase against someone
who stands their ground is only magnetism: it drags the attacker onto a target who
never tried to escape, and it makes spacing meaningless. The chase is checked again
every frame, so a target who turns to face the attacker stops being chased.

A target counts as running away if either test passes:

- Facing: they are turned away from the attacker (`FLEE_FACING_DOT`).
- Moving: their velocity away from the attacker is at least `FLEE_SPEED_MIN`.
  Strafing adds nothing.

Backing up while facing the attacker is spacing, not fleeing.

The follow speed is the target's sprint times `CHASE_SPRINT_MULT`, capped at the
weapon's boost speed. It depends on the target, not on the boost, because a 35-speed
weapon would otherwise chase at 19 against a 28 sprint, slower than the runner. The
drive stops within `STOP_DIST` of the target, so the attacker lands next to them
instead of passing through.

Targeting follows the lock-on: the locked target if there is one (the server checks
the client's `LockTarget` attribute again, so a forged attribute gains nothing),
otherwise the nearest valid target in a cone in front of the attacker.

The lunge can be beaten on purpose:

- Steering is rate-limited, so a hard cut across the attacker's facing breaks the
  track.
- A well-timed dodge or parry wins outright, because the lunge only closes distance.
  The hitbox still has to land.
- A parry or a stun stops the lunge, instead of dragging the attacker onward.

## E timing

E is a combo starter, so its lock must end with the swing, not on a flat timer. The
`CantAnything` lock is `windup + 0.05`, the same as RunM1.

`finish()` releases `activeAttacks[char]`. Until it runs, RunM1 declines the next M1.
So the lock and the release must end together, or the dead input only moves somewhere
else. `cfg.eRecovery` is per weapon, so heavy weapons can keep a real tail.

## Hyper armor

Every M2 is a guard break, so every M2 has hyper armor. Any other move can opt in with
`cfg.hyperArmor`. With armor, an incoming hit deals damage but does not stop the swing
or stun the attacker, and a clash cannot cancel the swing.

## Blocked hits

A blocked hit is not the same as a landed hit. It deals chip damage and a short, light
stagger (0.18 s, WalkSpeed 8). It does not run the on-hit pipeline, so the blocker
does not get the full weapon hitstun, and the attacker gets no mana or XP for a
blocked swing.

## On-hit mana

The attacker gets mana on every landed hit: 2% of MaxMana on M1 and 4% on M2 and E.
This is in the shared damage step and not in BuffService, so the amount is the same
with or without an active buff.

## Parry cooldown

The server owns the parry cooldown (`ParryService`). Clients keep a local copy only
for input feel.

- Pressing parry starts the full cooldown (`BASE_COOLDOWN`, 5 s) at once.
- A landed parry shortens it to `RESET_COOLDOWN` (1 s). This partial reset keeps the
  exchange going.
- A whiffed parry is never shortened, so it keeps the full lockout. No whiff
  detection is needed: the lockout is the default, and a landed parry pulls it back.
- Getting parried does not change your own cooldown. That is the trade.

## Damage formula

`damageCalculator.CalculateDamage` adds every bonus into one pool and applies it once:
the race `DamageBoost`, the armor `DamageBuff`, and the stat bonus for the damage type.
The bonuses are summed and never multiplied together, so stacking grows linearly, not
exponentially. The target's `DefenseBoost` divides the result.

| dmgType | Stat |
|---|---|
| `"Weapon"` (M1, M2, E) | Strength |
| `"Skill"` | Dexterity |
| `"Racial"` | Dexterity plus a Magic add-on |
| `nil` | None (true damage) |

Hitting a body that is already downed deals no damage, but it restarts the bleed-out
timer, so beating on a downed player keeps them down.

## WalkSpeed ownership

`SpeedService` owns every write to `Humanoid.WalkSpeed`.

Many systems change WalkSpeed: block, the M1/M2/E slow, stun, hitstop, skill
self-slows, and debuffs like Null Gaze. If each one saved the old speed and restored
it later, two effects at the same time would break each other: the last restore
overwrites the speed of the effect that is still active. Examples are blocking at full
speed after an M1, or returning to base speed instead of block speed after a hit
during a block.

So each effect pushes a modifier (a source key, a priority, and a speed) and pops it
when it ends. After every push and pop, SpeedService computes the speed again from
the live stack. The order of pushes and pops does not matter.

- The highest priority wins. Modifiers override, they do not add: a stun pins the
  player, it does not stack with block.
- On equal priority, the most recent push wins. This handles refreshes, such as beam
  ticks.
- With no modifiers, the speed is the live base (`GetBaseWalkSpeed * SpeedBoost`), so
  stamina respecs and race boosts apply with no extra code.

SpeedService owns WalkSpeed only. JumpPower, JumpHeight, and AutoRotate stay with
hitstop and stun, because far fewer systems write them.

## Block rules

`BlockResolver.Resolve` is the only place that decides what happens when a hit lands
on a blocking target. CombatCore, the per-weapon M2 and E modules, SkillFunctions,
and RacialSkills all call it, so every attack uses the same facing check, guard bar
rules, chip damage, and frame advantage.

- A blocked E: the defender is plus. The attacker gets a short recovery stun.
- A blocked M1: about neutral. A small chip, and nobody gains real advantage.
- A guard-break attack (`cfg.guardbreak`, every M2 at the moment) skips the bar and
  breaks the guard at once, for full damage. It never fills the bar.
- A hit from the side or back (outside the block cone) skips the block.
- Any other blocked hit fills the guard bar. The hit that makes the bar reach the
  maximum breaks the block. There is no grace hit.

The guard bar is a character attribute (`GuardBar`), so clients read it with
`GetAttribute` and never get out of sync with a server-side table. Only
`GuardBarService` writes it. After a break, the bar starts full and drains to empty over
`GUARD_RECOVERY_DURATION` (5 s), and the player cannot block until it is empty. A burst
(T) calls `SetStun(char, false)` first, so it also escapes a block-break stun, at the
normal burst cost.

A guard break from an attack and a guard break from a full bar use the same
`GuardBarService.Break`, so the stun, the lockout, the animation, and the 5-second
no-block recovery are the same.

## Burst

Burst (T) is a universal panic button. `BurstHandler` checks its mana cost and
cooldown. It works like a stripped Abyssal Scream: about one frame of startup, no
damage, and no stun. It knocks back and briefly ragdolls everyone in `BURST_RADIUS`,
so the user gets out of a combo, and it gives the user i-frames (the `Dodging` state,
which every hit path treats as "negate this hit") for `BURST_ACTIVE`.

Burst clears the user's stun first, so a player caught in a combo can use it. It also
escapes a block-break stun.

`BURST_WHIFF_RECOVERY` is a `CantAnything` lock the user always takes. It outlasts the
i-frames, so a burst on nothing leaves the user exposed for about a second and open to
a punish. The user is also rooted: `BURST_ROOT_WHIFF` on a whiff, and the shorter
`BURST_ROOT_HIT` when the burst catches a target.

Burst has its own handler (`BurstHandler`) instead of a SkillConfig entry in
`SkillHandler`, for three reasons:

- Everyone owns Burst, so it would fail the ownership check of SkillHandler.
- Its cost is a percentage of MaxMana (50%), which the flat `Mana` field of SkillConfig
  cannot express.
- It must work while stunned. That is the whole point of a combo breaker, and
  SkillHandler rejects casts while stunned.

BurstHandler rejects a burst while Downed, and while the user has `CantAnything`
without `Stunned`. That combination means the user is in the recovery of their own
attack, and Burst must not cancel it. Being hit (`Stunned`, with or without
`CantAnything`) and being idle are both allowed.

## Skill casts

`SkillHandler` checks every cast on the server: state, ownership (the racial skill or
an unlocked spell), the server cooldown, and the mana and HP cost.

The client arms its cooldown and the HUD swipe only when the server replies
"Accepted". A cast that the server rejects (a state check, an ownership or resource
desync, or the server cooldown) never puts the skill on cooldown on the client, so
pressing the button at the wrong time costs nothing. "Declined" lets the client drop
its prediction at once.

Offensive skills get hyper armor for their cast window (`HyperArmorDuration`, 1 s by
default), so an incoming hit deals damage but does not stop the animation or stun the
caster out of the skill. Buffs are instant and get no armor. A skill can opt out with
`HyperArmor = false`. A parry still beats the armor: every parry branch clears the
`HyperArmor` attribute before it stuns the caster.

## Dash tuning

`DashConfig` is the one tuning table for weapon-attack dashes: the forward
BodyVelocity that a weapon swing gives the attacker. Q dashes, sprint, skill dashes,
racial dashes, and mob and boss dashes are not in it.

The distance is speed times life. A 26-speed dash with a 0.3 s life covers about 7.8
studs. Tune `speed` to change how far a move carries. Tune `life` only to change how
the burst feels: a short life snaps and a long one glides.

Two guard rails apply to every value that `Get` returns: `MAX_SPEED` (50) and
`MIN_LIFE` (0.2). They make sure that a 75-speed gap closer cannot come back without a
deliberate change in one visible place. An entry with `exempt = true` skips both. It
is reserved for multi-part moves whose numbers are the move design, such as the second
step of the Tanto E.

- A speed of 0 turns a dash off. `Get` returns nil and the call site skips the
  BodyVelocity. The animation, FX, hitbox, and timing do not change. The M1 finisher
  dash is off. If it comes back, watch for whiffs: M1 knockback pushes the target back
  over the string, and the finisher dash made up for that drift.
- The air M1 hang comes from its call site (`MaxForce.Y` holds the vertical velocity
  at 0), not from this table.
- The fist family keeps a gap-closing M2 (40 against the default 26), and the longer
  weapons step in further on the running attack (50 against 35).

| Move key | Call site |
|---|---|
| `M1Finisher`, `M1Air` | `ReplicatedStorage.localHandler.Combat._Shared.M1` |
| `M1Lunge` | `ServerScriptService.modules.LungeService` |
| `M2` | `ServerScriptService.root.serverFramework.Combat._Shared.CombatCore` |
| `E` | `ReplicatedStorage.localHandler.Combat._Shared.E` |
| `TantoE1`, `TantoE2` | `ServerScriptService.root.serverFramework.Combat.Tanto.E` |
| `ShacklesM2` | `ServerScriptService.root.serverFramework.Combat.Shackles.M2` |
| `ShacklesM2Air` | `ReplicatedStorage.localHandler.Combat.Shackles.M2` |

## Character state

`stateHandler` owns character states such as `Stunned`, `Downed`, and `CantAnything`.
Each state is two things that are always written together: an entry in a Lua table
and an attribute on the character.

- The Lua table is local to the VM that required the module. The server's table and
  the client's table are separate, so a state that the server sets (`Downed`,
  `Carried`, `BeingExecuted`) never appears in the client's table. Client code must
  read attributes (`GetStateAttr`), because attributes replicate.
- `clearKey` is the only path that removes a state. It clears the table entry and the
  attribute together. Dropping the whole table when one key was last left other
  attributes set, so `GetState` and `GetAttribute` disagreed, and that let downed
  players act.
- A state set by a client (for example `Running` and `Sliding` from LocalScripts) does
  not replicate to the server, because a client's `SetAttribute` does not replicate.
  That is why attacks send the movement state as `SubType` in the payload.

`SetStun` with the `HyperArmor` attribute set does nothing: an armored attacker keeps
their move but still takes damage. After a stun ends, `DashLocked` is set for 0.15 s,
because the Dash LocalScript buffers a Q press and would otherwise slip out of a true
combo in the gap before the next hitbox.
