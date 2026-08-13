# Lunar Drift — Project Tree

```
res://
├── .gitattributes
├── .gitignore
├── export_presets.cfg
├── project.godot
├── README.md
│
├── assets/
│   ├── FBX/
│   └── models/
│
├── autoloads/
│   ├── economy_manager.gd
│   ├── game_manager.gd
│   ├── high_score_manager.gd
│   └── mobile_controls_loader.gd
│
├── resources/
│   ├── materials/
│   │   └── outline_material.tres
│   └── economy/
│       ├── cosmetic_item.gd
│       └── cosmetic_items/
│           ├── moon_accent_cool_white.tres
│           ├── sound_pack_strings.tres
│           ├── trail_paper_fragments.tres
│           ├── ui_theme_kraft_paper.tres
│           └── vessel_folded_hull.tres
│
├── shaders/
│   ├── water/
│   │   └── water.gdshader
│   └── outline/
│       └── outline.gdshader
│
└── scenes/
    ├── main/
    │   ├── main.tscn
    │   ├── main.gd
    │   ├── camera_rig.gd
    │   ├── intro_sequence.gd
    │   └── speed_lines.gd
    │
    ├── player/
    │   ├── player.tscn
    │   ├── player.gd
    │   └── moon_energy.gd        (now the multiplier meter, not energy)
    │
    ├── world/
    │   ├── ocean_follow.gd
    │   ├── moon_rig.gd
    │   └── procedural_world.gd
    │
    ├── object/
    │   ├── windmill.tscn
    │   ├── tower_windmill.tscn
    │   └── windmill_blades.gd
    │
    ├── startup/
    │   ├── loading_screen.tscn
    │   ├── loading_screen.gd
    │   ├── studio_logo.tscn
    │   ├── studio_logo.gd
    │   └── glow_texture.gd
    │
    ├── transitions/
    │   ├── fade_transition.tscn
    │   └── fade_transition.gd
    │
    ├── obstacles/                 (empty — Phase 6 lives inside procedural_world.gd instead)
    │
    └── ui/
        ├── main_menu.tscn
        ├── main_menu.gd
        ├── hud.tscn
        ├── hud.gd
        │
        ├── mobile/
        │   ├── mobile_controls.tscn
        │   ├── mobile_input_controller.gd
        │   ├── round_touch_button.gd
        │   └── cooldown_ring.gd
        │
        └── store/
            ├── store.tscn
            ├── store.gd
            ├── cosmetic_card.tscn
            └── cosmetic_card.gd
```

## Autoloads (singletons)

| Script | Role |
|---|---|
| `game_manager.gd` | Run state (MENU/PLAYING/PAUSED/GAME_OVER), `state_changed` signal |
| `economy_manager.gd` | Persistent currency (`shards`, `shards_changed`) — backs the Shades collectible payout and the Store |
| `high_score_manager.gd` | Best score persistence, `report_score()` |
| `mobile_controls_loader.gd` | Loads/wires `mobile_controls.tscn` on touch platforms |

## Notable systems not previously tracked in the build-log README

- **Store / cosmetics economy** (`resources/economy/`, `scenes/ui/store/`) —
  `CosmeticItem` resource type with at least 5 items already authored
  (moon accent color, sound pack, trail effect, UI theme, hull skin).
  Backed by `EconomyManager.shards`.
- **Mobile touch controls** (`scenes/ui/mobile/`) — round touch buttons
  with cooldown-ring visual feedback, loaded via the
  `mobile_controls_loader.gd` autoload rather than baked into `hud.tscn`
  directly.
- **Real mesh assets** (`assets/FBX/`, `assets/models/`) — the project has
  moved past pure procedural-primitive props for at least some objects
  (windmill/tower_windmill in `scenes/object/`).
