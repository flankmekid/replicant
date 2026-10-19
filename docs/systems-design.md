# Systems design

This file explains design decisions outside of combat. Combat decisions are in
`combat-design.md`.

## Character setup order

Two server scripts handle `CharacterAdded`, and both write the appearance:

- `mainGameHandler` owns armor (Shirt and Pants), stats, and inventory visuals.
- `RaceHandler` owns skin, face, hair, and race items. It also runs
  `CleanAccessories`, which destroys every accessory not named `EquipSlot_*`.

If `CleanAccessories` runs after `LoadAllVisuals`, it removes the inventory visuals.
A fixed wait in each script does not prevent this: `HandleCharacterLoad` can yield for
a long time (`WaitForChild` calls with 10-second timeouts and a wait for the
character to enter Workspace). So `mainGameHandler` sets the `BaseSetupComplete`
attribute when it is done, and `RaceHandler` waits for that attribute.

## Server-owned prices

Every price for weapons, items, and skills is set in `mainGameHandler`. The client
still sends a price argument, but the server ignores it. If the server trusted the
client's price, a crafted remote call could buy anything for free. Something that is
not in a price table is not for sale.

Skills are priced by slot (Z = 1000, X = 1500, C = 2500), the same as the trainer
dialogues. The slot is the skill's index in `SkillConfig.WeaponSkills`, so there is no
second list to keep in sync. The server also checks the family mastery level for the
slot (15, 20, 25), because the trainer checks it only on the client.

`ChangeWeapon` is the free tutorial path. It grants only seed weapons. Branch weapons
and hybrids go through `BuyWeapon`, which charges for them.

## Level 10 class quest

The level 10 milestone means "you may now be armed", so buying the branch weapon
completes it. The trainer has nothing to teach until level 15, so the trainer cannot
be the completion. The completion is in `BuyWeapon`, the only server-side purchase
path, so it works for every branch weapon and a client cannot fake it by firing
`QuestAction`.

Completion is per family, not per weapon: buying either fist weapon completes
`ClassQuest_Fists_10`. A player who ignores the quest marker and finds the Oni alone
still gets credit. The quest is a hint, not a rail, and the UI never shows Akuma.

Completing the quest hands control back to the class quest reconciler (below). A
player who is already past level 15 gets the next checkpoint at once, without waiting
for a level-up that already happened.

## Class quest reconciler

Class quest state is a function of the profile, not a reaction to a level-up event.
The reconciler (`QuestServer.ReconcileClassQuests`) asks one question per weapon
family: "Given this family's mastery and the class quests already completed, what is
the lowest unearned checkpoint at or below the current level?" It runs on login, on
mastery gain, and on quest completion, so no checkpoint can be skipped or stranded,
in any order.

A one-shot level-up signal fails in two ways:

- Crossing two milestones (for example 10 and 15) in one XP award assigns the second
  quest while the first is still active. The prerequisite check drops it, and nothing
  fires it again.
- Completing a checkpoint late (for example `_10` at mastery 22) never shows `_15` or
  `_20`, because the level-ups that would trigger them are in the past.

Only one class quest per family is open at a time: the player visits the trainer
before the next checkpoint unlocks. Class quests do not chain through `NextQuest`.
Completing one runs the reconciler, which opens the next earned checkpoint.

On login, `RestoreSession` runs the reconciler for every family before it sends the
quest list, so a checkpoint lost in an earlier session comes back.

## Hybrid skills

Hybrid weapons (Guandao, Scythe) have no class quests and no XP bar of their own. Each
of their three skills unlocks when both parent families reach a level: 15/15 for Z,
20/20 for X, 25/25 for C. The lower parent level decides. The hybrid trainer, who is
found in the world, hands over the weapon itself. The reconciler does not grant it, and
a player who holds a Guandao has already done eight class quests and needs no marker.
`UnlockSpell` does nothing for a skill the player already has, so the hybrid
reconciler is safe to run any number of times.

## Downed state

A player whose HP would drop to `downedThresholdPct` of max HP or lower goes down
instead of dying. NPCs never go down. `DownedManager` owns the whole life cycle:

- A downed body never gets up on its own. Its ragdoll has no duration and no stun
  timer. Only a revive, an execution, or a carry changes it.
- The revive timer (`reviveTimer`, 30 s) stands the player up with
  `reviveHpPct` of max HP. It pauses while the body is carried or being executed.
- Hitting a downed body deals no damage but restarts the revive timer, so beating
  on a downed player keeps them down.
- The body is pinned with SpeedService `PIN` priority, the top of the stack, so no
  other speed effect can make a downed player walk.
- Anyone who goes down drops the body they carry.

The knockdown ragdolls first and sets `Downed` after, so the body is on the floor
before any other system sees it as downed.

## Stat spread

Players invest 0 to 50 points in each stat. The curves are in `StatScaling`, the one
place that both the server and the client read. The values at level 50 (with a soft
cap at 40, after which a point gives 30% of its value) are:

| Stat | Effect |
|---|---|
| Vitality | +100 max HP, additive, from a hand-tuned back-heavy table |
| Strength | +35% weapon damage (M1, E, M2) |
| Dexterity | +50% skill damage |
| Magic | +50% racial skill damage, +100 max mana, 5x passive mana regen, 2x in-combat regen |
| Stamina | a third wall run at 10, a second dash at 30, a momentum soft cap at 20, +1 WalkSpeed per 10 points |

Damage bonuses are additive fractions (0.35 means +35%). `damageCalculator` adds them
to the race and armor bonuses in one pool and applies it once, so they never multiply
each other.

Skill points are bought with Liturgy on a rising curve: all 150 cost about 200k
Liturgy. Assigning a skill point to a stat is free, one to one. A respec frees every
assigned point and keeps the bought ones.

## Weapon families

Every weapon belongs to a seed family. Branch weapons share the family of their seed
weapon, so skills from both branches (for example a Monk Z and an Akuma X) fit in one
loadout. A hybrid weapon is its own family for its skill list, but it has no XP bar:
swinging it gives half the XP to each of its two parent families. The hybrid weapon
unlocks when both parents reach level 10, and its skills at 15, 20, and 25 (see Hybrid
skills).

## Climbing

A climb (a ledge grab or the wall climb) needs the player to be airborne and armed.
Arming stops a single ground press from launching the player up a wall:

- A space press on the ground is only a jump. It does not arm.
- A separate press in the air arms, and that same press tries the climb. So a climb
  from the ground takes two taps. `InputBegan` fires only on a fresh press, so holding
  jump cannot count as the second tap.
- A wall run arms (it sets the `WallRanRecently` attribute), so after a wall run a
  single press in the air climbs.
- Touching the ground disarms. While armed in the air, the player can climb again
  without arming again.

Letting go of a ledge is not a climb, so it is checked before the armed check: while
hanging, the player is Seated, not airborne.

The jump input is buffered like the dash: a press that cannot act (during the climb
cooldown or a short state block) is retried for `bufferWindow` seconds. The climb
yields, so `actionRunning` keeps a retry from starting a second climb during the
first.

Hold-to-catch makes the grab timing forgiving: while the jump key is held and the
player is armed, the client tries to grab a ledge every frame. It does not snap onto
a ledge the player tries to fall past, because a ground hold never arms. It never
runs while hanging, because a grab check while hanging lets go.

A ledge must be a solid, mostly opaque part with no side thinner than
`minLedgeThickness`. Characters, NPCs, and their gear are never ledges.
