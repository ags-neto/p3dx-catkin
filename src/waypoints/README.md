# `waypoints` — a DECLARED RECONSTRUCTION

**This is not the original `waypoints` package.** The original is lost. What is
in this directory was written from the clues that survived in `p3dx-catkin`, on
the author's request ("já não tenho waypoints, se conseguires criar um,
agradecia, senão deixa estar. documenta em falta."). It says so here, in
`package.xml`, in `CMakeLists.txt` and in the node itself, so that nobody
mistakes it for the author's work. If the original ever turns up, it should
replace this directory.

## What is known — verified, with the evidence

1. **The original was a gitlink with no content anywhere.** This repository
   recorded `src/waypoints` as index mode `160000` pointing at commit
   **`115553cfa8c2ace122414ac5a9b235cd2e225693`**. That code does not exist in
   any remote that could be found: not in the Gitea instance (`aneto/*`), not in
   the author's GitHub account, not on the machine the check was run on, and not
   on the web — the commit is not reachable from any candidate repository. The
   author no longer has it. So the *original* is the thing that is missing now.
2. **Package name and node name** come from `guide.txt`, the only documented
   interface:

   ```sh
   source devel/setup.bash && rosrun waypoints waypoints_server
   ```

   That gives, with certainty: the package is named `waypoints`, the executable
   is named `waypoints_server`, and it is run with **no arguments**.
3. **There was a C++ rviz plugin side.** The rviz configuration that
   `p3dx_navigation` loads (`src/p3dx_navigation/rviz/p3dx_navigation.rviz`)
   references classes only this package could have provided:

   - a panel: `Class: waypoints/waypointPanel`
   - a tool: `Class: waypoints/Waypoints`, with `Topic: waypoint`

   That is evidence that the original package built rviz plugins (rviz plugins
   are C++) and that the topic name `waypoint` was in use.

## What is inferred — NOT verified

Everything about how the node actually talks is a guess. Where the guess is
anchored in a clue above, it says so.

| item | value here | why |
|---|---|---|
| language of the node | Python | the rviz classes prove C++ *plugins*, not a C++ *node*; see below |
| input topic | `waypoint` | the name the rviz tool publishes on — the only topic-name evidence in the repo |
| input type | `geometry_msgs/PoseStamped` | one pose per clicked point; the tool could just as well have sent a `PoseArray` |
| output topic | `waypoints` | the plural of the evidenced name; **not** evidenced |
| output type | `geometry_msgs/PoseArray` | the conventional "list of poses" message |
| latched output, `~publish_rate` 1 Hz | | a list that a late subscriber still needs |
| behaviour | append each incoming pose to a list; re-publish the whole list | the smallest thing that makes it a *server of waypoints* |
| parameters | `~frame_id` (`map`), `~input_topic`, `~output_topic`, `~publish_rate`, `~waypoints` | ROS convention, and useful for testing without rviz |

Nothing here was recovered from the original. No service, no action, no goal
dispatched to `move_base`, no message type and no rviz plugin of the original is
reproduced, because none of them is evidenced. In particular, **the rviz plugin
gap is not closed**: open `p3dx_navigation.rviz` without the original package and
rviz still reports `waypoints/Waypoints` / `waypoints/waypointPanel` as unknown
classes.

## Why Python, when the clues point at C++

The `waypoints/*` rviz classes prove the original built **C++ plugins**, but they
say nothing about the language of the node `waypoints_server`. The only surviving
part of the node's contract is `rosrun waypoints waypoints_server`: `rosrun`
selects an executable by *name*, and a Python script with that name satisfies it
exactly. Python is also the only part of this that can be checked in the
environment where it was written (`python3 -m py_compile` — there is no ROS and
no compiler toolchain there): a C++ node whose interface is a guess could not be
compiled or tested, so it would only be a more expensive guess. If the author or
the original plugins ever point at C++, `scripts/waypoints_server` is short
enough to rewrite.

## Before you rely on this

**Confirm the interface first.** Do not treat `waypoint` / `waypoints` as a
contract: ask the author, or use the original if it reappears, before pointing
another package at these topics. `tests/run.sh` only checks that this package is
structurally complete and that the node name matches what `guide.txt` runs; it
cannot check the interface, because no ROS was available where it was written.

## Running it (as reconstructed)

```sh
source devel/setup.bash
rosrun waypoints waypoints_server
```

Then, from another shell:

```sh
rostopic pub -1 /waypoint geometry_msgs/PoseStamped \
  '{header: {frame_id: map}, pose: {position: {x: 1.0, y: 0.0}}}'
rostopic echo /waypoints
```

## Licence

GPL-3.0, like the rest of this repository (Copyright (C) 2024 André Neto) — see
[`../../LICENSE`](../../LICENSE). This directory makes no copyright claim over
the lost original; it is a reconstruction that declares itself.
