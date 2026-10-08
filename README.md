# p3dx-catkin

ROS catkin workspace for the Pioneer 3-DX (P3DX) mobile robot.

## License

The repository **as a whole** is licensed under **GPL-3.0** — see [LICENSE](LICENSE)
(Copyright (C) 2024 André Neto, the year of the first commit). Third-party packages
vendored under `src/` keep their own licences:

| package | licence declared in `package.xml` |
|---|---|
| `p3dx_description` | GPL-3.0 |
| `robot`, `estop` | LGPL-3.0 |
| `ros_astra_camera` | Apache-2.0 |
| `urg_node`, `urg_c`, `laser_proc`, `rgbd_launch` | BSD |
| `object_detection`, `p3dx_navigation`, `p3dx_slam` | not declared (`TODO` in `package.xml`) |
| `rosaria` | **GPL-2.0-only** (declared in the upstream `package.xml`; the upstream repository has no licence file) |
| `waypoints` | GPL-3.0 (`GPLv3` in `package.xml`) — a **declared reconstruction**, not the original; see [`src/waypoints/README.md`](src/waypoints/README.md) |

MIT is not possible here: the GPL-3.0 package `p3dx_description` and the LGPL-3.0
`robot`/`estop` impose their own obligations on the combined work.

## OpenNI2 and the Orbbec driver are not bundled

`ros_astra_camera` needs the OpenNI2 runtime and the Orbbec driver
(`OpenNI2/Drivers/liborbbec.so` and friends). Those used to be vendored here as
prebuilt binaries under `src/ros_astra_camera/include/openni2_redist/`; they are
no longer part of this repository. They are factory/third-party artefacts and
this repository has no checked terms to redistribute them, so it does not.

Install them instead: the OpenNI2 runtime from the official OpenNI distribution
(build it from the official source tree, or use the distribution package that
provides OpenNI2 for your architecture), and the Orbbec driver from the
manufacturer's Astra SDK, or from the distribution package that ships it.

Once OpenNI2 is available system-wide the package builds as before, because the
OpenNI2 headers remain in the repository under
`src/ros_astra_camera/include/openni2/`. Anyone who prefers to keep the files
next to the source can drop them back into
`src/ros_astra_camera/include/openni2_redist/<arch>/`; that directory is now
ignored by git so it will not be committed again.

## Submodules: a clean clone must bring code, not empty directories

`src/rosaria` and `src/waypoints` were both recorded in this repository's history as
**gitlinks** (index mode `160000`, i.e. submodule entries), not as plain
directories. A gitlink stores only a commit id — the code itself lives in another
repository. For a clone to bring that code, each gitlink needs a matching entry in
`.gitmodules`; without one, `git clone` simply creates an **empty directory**.

Only `src/rosaria` is still a gitlink today. `src/waypoints` was replaced by in-tree
content written as a **declared reconstruction** of the lost original — see below.

That was the state of this repository until this fix, and it broke the build:
`src/robot/package.xml` declares `<depend>rosaria</depend>`, so while `src/rosaria`
was empty a clean clone could not be built.

### `src/rosaria` — origin identified, fixed here

`src/rosaria` points at commit `204dc0c6785abb4037c1c5ee76439cf5f50cb880` of
**<https://github.com/amor-ros-pkg/rosaria.git>**. This was verified rather than
guessed: the commit exists on that repository's `master` branch (it is the merge
commit of pull request #56) and its tree contains `package.xml`, `CMakeLists.txt`
and `RosAria.cpp`.

A `.gitmodules` entry now declares it, so a clean clone brings the code:

```sh
git clone <url> p3dx-catkin
cd p3dx-catkin
git submodule update --init -- src/rosaria
```

**Note the `-- src/rosaria`.** While `src/waypoints` was still a gitlink with no
`.gitmodules` mapping, the untargeted `git submodule update --init` aborted — git could
not resolve a URL for it — and the same happened to a bare `git submodule status`. That
is fixed: initialising by path still works, and the untargeted `git submodule update
--init` and `git submodule status` no longer complain, because every remaining gitlink
is declared.

### `src/waypoints` — the original is LOST; what is there now is a declared reconstruction

`src/waypoints` used to point at commit `115553cfa8c2ace122414ac5a9b235cd2e225693`, but
**that code does not exist in any remote that could be found** — this was checked,
not assumed. It is not:

- in the Gitea instance (`aneto/*`) — no repository matches `waypoints`;
- in the author's GitHub account (`ags-neto`) — 15 public repositories, none named
  `waypoints`, and `ags-neto/waypoints` returns 404;
- anywhere on the machine where these checks were run — there is no
  `waypoints_server` source on it;
- on the web — the commit `115553c…` is not reachable from any candidate repository.

Because the origin is unknown, **no `.gitmodules` entry was invented for it**: a
guessed URL would be worse than an honest gap. The author was asked, no longer has the
code, and authorised a reconstruction, so the gitlink was replaced by in-tree content
(`git rm --cached src/waypoints` plus the committed files) — the second of the two
honest ways out. That content is **a reconstruction, not the original work**:

> **[`src/waypoints/README.md`](src/waypoints/README.md)** is the declaration. It names
> the lost commit, says what is documented (`guide.txt` runs
> `rosrun waypoints waypoints_server`, so the package name and the node name are
> certain) and what is inferred (every topic, message type and parameter), says why it
> is Python, and tells anyone who reuses it to confirm the interface before trusting it.

What is genuinely missing now is the **original** `waypoints` package — and with it the
rviz plugins that `p3dx_navigation.rviz` expects (`waypoints/waypointPanel`,
`waypoints/Waypoints`), which the reconstruction deliberately does not reproduce. The
consequence is concrete: a clean clone now brings a real `src/waypoints/` directory
instead of an empty one, so `rosrun waypoints waypoints_server` resolves structurally —
but the interface is a guess, and `p3dx_navigation.rviz` still reports the waypoint
panel and tool as unknown classes. If the original ever reappears, it should replace the
reconstruction. Both gaps are recorded in [`tests/known-gaps.txt`](tests/known-gaps.txt).

## `guide.txt` also runs a package that is not in this workspace

The object-detection section of `guide.txt` says to run
`roslaunch darknet_ros darknet_ros.launch`, but there is **no `darknet_ros` package
under `src/`**. This is a documentation-conformance gap, not a gitlink — the package
presumably came from another workspace or from a system install. It is recorded here
and not fixed: `guide.txt` is the author's.

## One observation left for the author (licences)

The licence table above was written when `rosaria` was still an empty gitlink, so its
row reads "gitlinks with no content, no licence file to read". Now that `src/rosaria`
resolves, that row is stale: at the pinned commit, `rosaria/package.xml` declares
`<license>GPLv2</license>` (version 0.9.0). That matters for the repository-wide
GPL-3.0 decision, because GPLv2 without "or later" is not compatible with GPL-3.0.
The row was deliberately **left untouched** — the licence decision is the author's,
not this fix's.

## Tests

`tests/run.sh` checks what can be checked without ROS: that every package recorded in
the index has `package.xml` and `CMakeLists.txt`, that package names are present and
unique, that `src/CMakeLists.txt` is catkin's toplevel symlink, that every gitlink is
either declared in `.gitmodules` or a documented known gap, that `src/rosaria`
resolves at the pinned commit, that the declared submodule URL is the verified one,
that every in-tree `<depend>` points at a package that exists, that every known gap is
documented here, and (section 8) that the reconstructed `waypoints` package is
complete: no gitlink any more, a `package.xml` declaring `waypoints`, a `CMakeLists.txt`,
the node that `guide.txt` names present, executable and initialising itself under that
same name, its Python accepted by `python3 -m py_compile`, a README that declares it a
reconstruction and names the lost commit, and a `git submodule status` that no longer
fails. `tests/negative.sh` proves the suite has teeth by breaking one thing at a time in
a throwaway copy — including deleting the reconstructed node, taking its `package.xml`
away, making the node non-executable, renaming the node it initialises, corrupting its
Python, dropping the declaration, and committing the gitlink back.

They do **not** prove that the workspace builds — no ROS was available where they were
written, so `catkin_make` was never run — nor that the reconstructed `waypoints` node
does anything useful when it runs: only its structure, its node name and its syntax are
checked, and its topics are inferred (see [`src/waypoints/README.md`](src/waypoints/README.md)).

**On `rosaria`:** its upstream (`amor-ros-pkg/rosaria`) declares `GPLv2` with no "or later"
clause, which is **incompatible with the GPL-3.0 of this repository** for a combined work. It is
kept as a separate package (a collection, not a derivative), so each package keeps its own
licence — but if a single licence for the whole set is ever wanted, `rosaria` would have to be
replaced by a GPLv3-compatible alternative. This is recorded, not resolved: the licence table was
left otherwise untouched.
