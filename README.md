# docker_config

Docker configurations and scripts used to set up a local ROS 2 + CARLA simulator environment.

## History

During the CUERT 24-25 season we used a **ROS 1 Noetic + CARLA** environment for our autonomous driving stack.

> During the CUERT 24-25 season, we didn't focus as much on the physical vehicle competition, and instead focused on the virtual competition.

This setup worked well for the team, and provided a good environment where all of our systems could be tested and integrated.

However, as we moved into the CUERT 25-26 season, we decided to migrate to **ROS 2 Foxy** (The latest version supported by our main compute unit the [Jetson Xavier AGX](https://www.nvidia.com/en-us/autonomous-machines/embedded-systems/jetson-xavier-series/)) and were facing difficulties with the **CARLA simulator**, so we decided to use **Gazebo Classic** as our main simulator (a popular, but very visually unpleasant simulator and not really made for autonomous driving simulations).

Moving into the CUERT 26-27 season, we were enlightened by the concept of containerized development environments, and decided to migrate our entire stack to **ROS 2 Humble + CARLA** using Docker containers. This allows us to have a consistent development environment across all team members, regardless of their host OS.

Hopefully, we can continue to use this setup for the next few seasons, and can continue to improve it as we go.

> Yes, we will have to migrate to ROS 2 Jazzy eventually, but we will cross that bridge when we get there. Give me a break!

## ⚠️ Before You Begin

Please don't hesitate to reach out to the team if you have any questions or issues regarding this setup as early as possible. We are happy to help you get up and running with this environment.

Please don't leave issues unresolved. The main reason we made this setup script is to make it easier for new team members to get up and running with the environment, and we want to make sure that everyone has a good experience with it.

## Setup Architecture

This repository spins up a **two-container simulation stack** using Docker Compose:

- **`ros2_humble_env`**: A ROS 2 Humble development container (based on `osrf/ros:humble-desktop`) housing your mounted workspace and development toolchain.
- **`carla_sim`**: A CARLA 0.9.16 simulator container configured for X11 display forwarding or headless execution.

---

## Linux Host Environment

This setup script, *while primarily focused on containerization and host independence*, has so far only been tested on **Ubuntu 22.04 LTS** so it is recommended to use this OS for the host environment. Other Linux distributions may work too.

Please see the [Installation Alternatives & Windows (WSL2) Support](#-installation-alternatives--windows-wsl2-support) section for more information on other setup options.

Follow the instructions below to get your Ubuntu 22.04 dual boot host environment ready:

- Download Ubuntu 22.04 LTS (Jammy Jellyfish) desktop image from the official Ubuntu website.

- Follow this [video](https://www.youtube.com/watch?v=GXxTxBPKecQ) to install Ubuntu alongside Windows as a dual boot.

- Allocate 70GB of space or more for Ubuntu (Yes, it's a lot, but it's necessary).

- Make yourself familiar with Ubuntu and install **VSCode** and **Discord**.

## Host Prerequisites

Before running the setup script, ensure your host environment meets the following requirements:

1. **Docker & Docker Compose**: Installed and runnable without `sudo` (your user added to the `docker` group).
2. **NVIDIA GPU Support (If applicable)**: `nvidia-container-toolkit` installed on the host OS.

---

## Setup Script Walkthrough

Running `./docker_setup.sh` prompts you for environment settings, generates a tailored `Dockerfile` and `compose.yml`, configures your shell, and optionally builds the environment.

### 1. ROS Container & Workspace Paths

- **ROS Container Name**: Default is `ros2_humble_sim`.
- **Host Workspace Path**: Default is `${HOME}/ros2_ws`.
- **Container Workspace Path**: Default is `/workspace`.

### 2. Generated Deliverables

- **`Dockerfile`**: Builds the ROS 2 Humble and CARLA (0.9.16) base images.
- **`compose.yml`**: Orchestrates container startup.
- **Shell Aliases**: Appends helper aliases to your `~/.bashrc`:
  - `enter_<container_name>` (e.g., `enter_ros2_humble_sim`): Interactive shell inside the ROS 2 container.
  - `run_carla`: Grants local X11 display access (`xhost +local:`) and launches CARLA in GUI mode inside the container (`./CarlaUE4.sh --ros2 -nosound`).
  - `run_carla_low_quality`: Grants local X11 display access (`xhost +local:`) and launches CARLA in low quality mode (`./CarlaUE4.sh --ros2 -nosound -quality-level=Low`).
  - `run_carla_headless`: Grants local X11 display access (`xhost +local:`) and launches CARLA in headless mode (`./CarlaUE4.sh -RenderOffScreen --ros2 -nosound`).

---

## Daily Usage & Operations

### Entering the ROS 2 Container

To access your ROS 2 workspace, open a new terminal session and run your generated alias:

```bash
enter_ros2_humble_sim
```

### Running the CARLA Simulator

- **High Quality Mode**:

  ```bash
  run_carla
  ```

- **Low Quality Mode**:

  ```bash
  run_carla_low_quality
  ```

- **Headless Mode (No GUI)**:

  ```bash
  run_carla_headless
  ```

- **Interactive Bash Shell in the CARLA Container**:

  ```bash
  docker exec -it carla_0_9_16 bash
  ```

---

### Testing

To make sure that your ROS 2 + CARLA environment is functioning correctly, verify the following:

1. Run the CARLA simulator in any mode (GUI, low quality, or headless).
2. In a separate terminal, enter the ROS 2 container using the alias `enter_ros2_humble_sim`.
3. Inside the ROS 2 container, run the following command to start the manual control example:

    ```bash
    python3 ./PythonAPI/examples/manual_control.py
    ```

4. If everything is set up correctly, you should see a pygame window pop up, allowing you to control a random vehicle in the CARLA simulator using your keyboard.

5. In another terminal, enter the ROS 2 container and run the following command to check if CARLA is communicating with ROS 2:

    ```bash
    ros2 topic list
    ```

    You should see a list of topics being published by CARLA, such as

    ```bash
    /carla/actor24/ackermann_control_cmd
    /carla/actor24/actor27
    /carla/actor24/actor28
    /carla/actor24/actor29/camera_info
    /carla/actor24/actor29/image
    /carla/actor24/vehicle_control_cmd
    ```

---

### Managing Container States

- **Check running containers:**

  ```bash
  docker ps
  ```

- **Stop the stack manually:**

  ```bash
  docker compose stop
  ```

- **Start the stack after a manual stop:**

  ```bash
  xhost +local: && docker compose start
  ```

- **Rebuild after modifying dependencies in `Dockerfile`:**

  ```bash
  docker compose down
  docker compose up -d --build
  ```

---

## Installation Alternatives & Windows (WSL2) Support

### Windows via WSL2 (Recommended for Windows Users, don't use a VM!)

If you are developing on Windows 10/11, you can run this entire environment using **WSL2**. *HOWEVER*, you will have to navigate the process on your own since this setup script has only been tested on native Linux hosts.

---

### Host-Native Linux Setup (Without Docker)

If you prefer a direct host installation on Ubuntu 22.04 without docker containers, refer to the official documentation:

- [ROS 2 Humble Installation Guide](https://docs.ros.org/en/humble/Installation.html)
- [CARLA 0.9.16 Simulator Documentation](https://carla.readthedocs.io/en/0.9.16/)
