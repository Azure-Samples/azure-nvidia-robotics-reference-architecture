import time
import numpy as np
from rtde_control import RTDEControlInterface as RTDEControl
from rtde_receive import RTDEReceiveInterface as RTDEReceive

rtde_frequency = 500.0
rtde_c = RTDEControl("localhost", rtde_frequency, RTDEControl.FLAG_VERBOSE | RTDEControl.FLAG_UPLOAD_SCRIPT)
rtde_r = RTDEReceive("localhost", rtde_frequency)

# --- Joint PD torque control ---
#
# UR3 max torques, can be replaced with relevant max torques.
max_torque = np.array([56.0, 56.0, 28.0, 9.0, 9.0, 9.0])

# Example gains, need to be selected for the purpose
Kp = max_torque / np.array([0.25, 0.25, 0.5, 1, 1, 1])
Kd = max_torque / (np.pi * 0.5)

q_err = np.array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
q_err_acc = np.array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
q_target = rtde_r.getTargetQ()

# Impedance Controller loop
timecounter = 0.0
while True:
    t_start = rtde_c.initPeriod()
    # Move the q target should move in an sine
    q_shoulder = 0.5 * np.sin(timecounter)
    targetoffset = np.array([0, q_shoulder, 0, 0, 0, 0])
    target_qdd = np.array([0, -q_shoulder, 0, 0, 0, 0])

    q_err_prev = q_err
    q_err = targetoffset + q_target - rtde_r.getActualQ()
    q_err_d = (q_err - q_err_prev) / (1.0 / rtde_frequency)

    torque_target = Kp * q_err + np.clip(Kd * q_err_d, a_min=0.2 * -max_torque, a_max=0.2 * max_torque)

    # Clamp target torque
    torque_target = np.clip(torque_target, a_min=-max_torque, a_max=max_torque)

    # Apply torque control
    print("torque:", torque_target.tolist())
    rtde_c.directTorque(torque_target.tolist())

    rtde_c.waitPeriod(t_start)
    timecounter = timecounter + 0.002
