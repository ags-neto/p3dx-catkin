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
