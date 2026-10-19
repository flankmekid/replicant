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

When the lunge has a target, it steers toward the target and keeps a weaker drive
through the windup, so a sprinter cannot simply outrun the windup. Without a target
it is a plain forward burst that ends after 0.3 s.

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
