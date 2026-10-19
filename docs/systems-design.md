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
