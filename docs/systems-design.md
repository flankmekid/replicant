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

Completing the quest hands control back to the quest reconciler. A player who is
already past level 15 gets the next checkpoint at once, without waiting for a level-up
that already happened.
