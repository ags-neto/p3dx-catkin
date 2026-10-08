cmake_minimum_required(VERSION 3.0.2)
project(waypoints)

## DECLARED RECONSTRUCTION - not the original package. See README.md.
##
## This package is Python only: one node, no libraries and no messages of its
## own, so the catkin side is just "install the script".
##
## Note what is deliberately NOT here: the rviz configuration used by
## p3dx_navigation references classes that the original package must have
## provided (waypoints/waypointPanel, waypoints/Waypoints), i.e. it built C++
## rviz plugins and exported a plugin description. Those plugins are not
## reproduced: inventing them would be an unverifiable guess, and rviz would
## fail to load them anyway. See README.md.

find_package(catkin REQUIRED)

catkin_package()

catkin_install_python(PROGRAMS
  scripts/waypoints_server
  DESTINATION ${CATKIN_PACKAGE_BIN_DESTINATION}
)
