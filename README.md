# relicmink

Mink's bizarre adventure

Open `project.godot` in Godot 4.7. F5 starts a procedurally generated level in `main.tscn`. To try the controls, open `training.tscn` and run that scene with F6.

| Input | Action |
| --- | --- |
| A / D or Left / Right | Run and turn |
| Space | Tap for a short jump, hold for a higher jump, then press again in the air to double jump |
| Shift | Dash in the facing direction |
| H | Trigger hit and knockback on demand |

Use the raised platforms to test jumps and landings at different heights. Use a double jump or an air dash to cross the pit. Falling in returns you to the starting point. Touch the red spikes to test contact damage.

You can jump up to 100 ms after leaving a ledge. If a jump cannot start immediately, pressing Space up to 120 ms before landing queues a jump. When a double jump is available, Space uses it immediately.

The first jump gets higher the longer you hold Space during ascent. The double jump has a fixed height. Pressing Space during a dash switches into a jump if one is available. You get one air dash per airtime, and dashing keeps any unused double jump available.

See the [prefab JSON guide](docs/prefab-json.md) to add rooms, corridors, shafts, or tile aliases.
