# Conventions

These rules apply to all code in `src/` except third-party code. Third-party code is
listed in `.styluaignore`. Do not edit it.

## Formatting

StyLua formats the code. The configuration is in `stylua.toml`: tabs, column width 100,
Unix line endings.

```sh
stylua src
stylua --check src
selene src
```

## Naming

- Use camelCase for locals and functions.
- Use PascalCase for services, remotes, and module instances.
- Do not use UPPER_CASE. This also applies to constants.

## Comments

1. A comment says why. If the code already says what happens, do not write a comment.
2. Do not write history. Do not write "this was changed because", "the old version
   did", or "fixed X". Git keeps the history.
3. Do not write section banners, "Step 1:" narration, or commented-out code.
4. Write full sentences. Start with a capital letter and end with a period.
5. Use plain `--` lines for every comment. Do not use `--[[ ]]` blocks. The maximum
   line length is 100 columns.
6. Every file starts with the license header and a short paragraph about the purpose
   of the file:

   ```lua
   -- SPDX-License-Identifier: MIT
   --
   -- Owns every write to Humanoid.WalkSpeed. Other scripts request a speed
   -- change here and never write WalkSpeed directly.
   ```

7. Public module functions get a doc header in kernel-doc style. Local helpers do not.

   ```lua
   -- CooldownTracker.Register() - show a cooldown on the client HUD
   -- @id: a unique key for the cooldown
   -- @label: the text on the HUD entry
   -- @duration: the length in seconds
   --
   -- Return: nothing.
   ```

8. Use trailing comments only on short table fields, for example a unit on a config
   value.
9. Use only the markers `TODO:` and `FIXME:`.
10. Do not explain the internals of another module. That text goes stale. Write only
    the one fact that this code needs.

## Log messages

- Use this format: `` warn(`[ScriptName] Sentence with {context}.`) ``. The tag is the
  literal name of the script.
- Use `warn` for bad input that the script survives, for example a malformed payload.
- Use `error` only for programmer mistakes that must stop the script.
- Do not leave debug `print` calls in the code.

## Data keys

Do not rename string keys. This includes ProfileStore data keys, attribute names,
remote names, and instance names used in `FindFirstChild` or `WaitForChild` calls.
A rename breaks saved data or the place file.
