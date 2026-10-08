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
| `rosaria`, `waypoints` | gitlinks with no content, no licence file to read |

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
