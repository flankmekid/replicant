# Third-party code

The MIT license in `LICENSE` covers only the code written for Replicant. The
components below keep their own licenses. They are listed in `.styluaignore` and
`selene.toml` and are not formatted or linted. Each upstream license file is in
`licenses/`, unmodified. GoodSignal and ContextActionUtility have no license file:
their terms are in the header of their own source files.

| Component | Path | Author | License | Source |
|---|---|---|---|---|
| TopbarPlus | `src/ReplicatedStorage/TopbarPlus` | ForeverHD | MPL-2.0 with the TopbarPlus Credit terms | [1ForeverHD/TopbarPlus](https://github.com/1ForeverHD/TopbarPlus) |
| GoodSignal (inside TopbarPlus) | `src/ReplicatedStorage/TopbarPlus/Icon/Packages/GoodSignal.luau` | stravant | MIT | [GoodSignal](https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f) |
| SmartBone 2 | `src/ReplicatedStorage/modules/SmartBone` | SmartBone | MIT, Copyright (c) 2024 SmartBone | [smartbone-org/SmartBone-2](https://github.com/smartbone-org/SmartBone-2) |
| Iris (inside SmartBone) | `src/ReplicatedStorage/modules/SmartBone/Dependencies/Iris` | Michael_48 | MIT, Copyright (c) 2024 Michael_48 | [SirMallard/Iris](https://github.com/SirMallard/Iris) |
| CeiveImGizmo (inside SmartBone) | `src/ReplicatedStorage/modules/SmartBone/Dependencies/Debug/Gizmo` | JakeyWasTaken | MIT, Copyright (c) 2023 JakeyWasTaken | [JakeyWasTaken/CeiveImGizmo](https://github.com/JakeyWasTaken/CeiveImGizmo) |
| HitboxClass | `src/ReplicatedStorage/modules/hitboxClass` | RedTrio | MIT, Copyright (c) 2024 RedTrio | [RedTrioVirus/HitboxClass](https://github.com/RedTrioVirus/HitboxClass) |
| Signal (inside HitboxClass) | `src/ReplicatedStorage/modules/hitboxClass/Signal.luau` | stravant, sleitnick | MIT | [GoodSignal](https://gist.github.com/stravant/b75a322e0919d60dde8a0316d1f09d2f) |
| CameraShaker | `src/ReplicatedStorage/modules/CameraShaker` | Stephen Leitnick | MIT, Copyright (c) 2019 Stephen Leitnick | [Sleitnick/RbxCameraShaker](https://github.com/Sleitnick/RbxCameraShaker) |
| ContextActionUtility | `src/ReplicatedStorage/modules/ContextActionUtility.luau` | PseudoPerson | CC BY 4.0 | [DevForum post](https://devforum.roblox.com/t/easy-mobile-buttons-contextactionutility/804219) |
| ProfileStore | `src/ServerScriptService/modules/ProfileStore.luau` | loleris (MAD STUDIO) | Apache-2.0 | [MadStudioRoblox/ProfileStore](https://github.com/MadStudioRoblox/ProfileStore) |
| Promise | `src/ServerScriptService/modules/Promise.luau` | Eryn L. K. | MIT, Copyright (c) 2019 Eryn L. K. | [evaera/roblox-lua-promise](https://github.com/evaera/roblox-lua-promise) |
| PlayerModule | `src/StarterPlayerScripts/PlayerModule` | Roblox Corporation | Roblox default script | Shipped with Roblox Studio |
| Animate | `src/StarterCharacterScripts/Animate` | Roblox Corporation | Roblox default script | Shipped with Roblox Studio |

## Terms to keep

- **TopbarPlus** asks that you either keep `Icon/Attribute.luau` unchanged or credit
  TopbarPlus in your experience's description. This repository keeps it unchanged.
- **ContextActionUtility** (CC BY 4.0) needs the credit that is in the file. Do not
  remove it.
- **ProfileStore** (Apache-2.0) and **TopbarPlus** (MPL-2.0) need their license texts
  to travel with the code, which `licenses/` does.
- **PlayerModule** and **Animate** are Roblox's own default scripts. They are not
  covered by this repository's license.
