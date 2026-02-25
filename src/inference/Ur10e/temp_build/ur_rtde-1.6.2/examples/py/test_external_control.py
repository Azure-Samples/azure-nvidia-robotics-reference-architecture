from rtde_control import RTDEControlInterface as RTDEControl
import time
rtde_frequency = 500.0
rtde_c = RTDEControl("192.168.56.101", rtde_frequency, RTDEControl.FLAG_VERBOSE | RTDEControl.FLAG_USE_EXT_UR_CAP)

task_frame = [0, 0, 0, 0, 0, 0]
selection_vector = [0, 0, 1, 0, 0, 0]
wrench_down = [0, 0, -10, 0, 0, 0]
wrench_up = [0, 0, 10, 0, 0, 0]
force_type = 2
limits = [2, 2, 1.5, 1, 1, 1]

# Execute 500Hz control loop for 4 seconds, each cycle is 2ms
for i in range(2000):
    t_start = rtde_c.initPeriod()
    # First move the robot down for 2 seconds, then up for 2 seconds
    if i > 1000:
        rtde_c.forceMode(task_frame, selection_vector, wrench_up, force_type, limits)
    else:
        rtde_c.forceMode(task_frame, selection_vector, wrench_down, force_type, limits)
    rtde_c.waitPeriod(t_start)

rtde_c.forceModeStop()
rtde_c.stopScript()
time.sleep(1)
print("Script stopped! calling destructor of RTDEControlInterface")
del rtde_c
print("Trying again...")
rtde_c = RTDEControl("192.168.56.101", rtde_frequency, RTDEControl.FLAG_VERBOSE | RTDEControl.FLAG_USE_EXT_UR_CAP)

task_frame = [0, 0, 0, 0, 0, 0]
selection_vector = [0, 0, 1, 0, 0, 0]
wrench_down = [0, 0, -10, 0, 0, 0]
wrench_up = [0, 0, 10, 0, 0, 0]
force_type = 2
limits = [2, 2, 1.5, 1, 1, 1]

# Execute 500Hz control loop for 4 seconds, each cycle is 2ms
for i in range(2000):
    t_start = rtde_c.initPeriod()
    # First move the robot down for 2 seconds, then up for 2 seconds
    if i > 1000:
        rtde_c.forceMode(task_frame, selection_vector, wrench_up, force_type, limits)
    else:
        rtde_c.forceMode(task_frame, selection_vector, wrench_down, force_type, limits)
    rtde_c.waitPeriod(t_start)

rtde_c.forceModeStop()
rtde_c.stopScript()
