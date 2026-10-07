#!/bin/bash

# Prevent auto-closing terminal on completion or error
finish() {
    echo -e "\nPress Enter to exit..."
    read -r
}
trap finish EXIT

# 1. Ask for Container Name & Folder Mounts
echo "--- ROS 2 Humble Setup ---"
read -p "Enter desired ROS 2 container name [ros2_humble_sim]: " ROS2_CONTAINER
ROS2_CONTAINER=${ROS2_CONTAINER:-ros2_humble_sim}

read -p "Enter absolute path of HOST workspace [/home/$USER/ros2_ws]: " HOST_DIR
HOST_DIR=${HOST_DIR:-/home/$USER/ros2_ws}

read -p "Enter target path INSIDE container [/workspace]: " CONTAINER_DIR
CONTAINER_DIR=${CONTAINER_DIR:-/workspace}

mkdir -p "$HOST_DIR"
mkdir -p "$HOME/.ssh"
touch "$HOME/.Xauthority"

# 3. Ask for GPU Passthrough
echo -e "\n--- GPU Configuration ---"
read -p "Enable GPU passthrough? (y/n) [y]: " ENABLE_GPU
ENABLE_GPU=${ENABLE_GPU:-y}

GPU_TYPE=""
if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]]; then
    read -p "Specify GPU vendor ('nvidia', 'intel', or 'amd') [nvidia]: " GPU_TYPE
    GPU_TYPE=${GPU_TYPE:-nvidia}
fi

# 3b. Install & Configure NVIDIA Container Toolkit if needed
if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]] && [[ "$GPU_TYPE" == "nvidia" ]]; then
    echo -e "\n--- Checking NVIDIA Container Toolkit ---"
    if ! command -v nvidia-ctk &> /dev/null; then
        echo "NVIDIA Container Toolkit not found. Attempting installation..."
        sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
        sudo nvidia-ctk runtime configure --runtime=docker
        sudo systemctl restart docker
    else
        echo "NVIDIA Container Toolkit is already installed."
    fi
fi

# 4. Generate Dockerfile
echo -e "\nGenerating Dockerfile..."
cat << EOF > Dockerfile
FROM osrf/ros:humble-desktop

RUN apt-get update && apt-get install -y \
    openssh-client \
    sudo \
    curl \
    iputils-ping \
    net-tools \
    python3-pip \
    python3-colcon-common-extensions \
    python3-argcomplete \
    ros-humble-rmw-fastrtps-cpp \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir carla==0.9.16

RUN echo "source /opt/ros/humble/setup.bash" >> /etc/bash.bashrc && \
    echo "source /usr/share/colcon_argcomplete/hook/colcon-argcomplete.bash" >> /etc/bash.bashrc && \
    echo "if [ -f ${CONTAINER_DIR}/install/setup.bash ]; then source ${CONTAINER_DIR}/install/setup.bash; fi" >> /etc/bash.bashrc

WORKDIR ${CONTAINER_DIR}

CMD ["sleep", "infinity"]
EOF

# 5. Generate compose.yml
echo "Generating compose.yml..."

cat << EOF > compose.yml
services:
  ros2_humble_env:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: ${ROS2_CONTAINER}
    restart: unless-stopped
    privileged: true
    network_mode: "host"
    ipc: "host"
    pid: "host"
    ulimits:
      rtprio: 99
      memlock: -1
    environment:
      - DISPLAY=\${DISPLAY:-:0}
      - QT_X11_NO_MITSHM=1
      - ROS_DOMAIN_ID=0
      - RMW_IMPLEMENTATION=rmw_fastrtps_cpp
      - XAUTHORITY=/root/.Xauthority
EOF

if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]] && [[ "$GPU_TYPE" == "nvidia" ]]; then
    cat << EOF >> compose.yml
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
EOF
elif [[ "$ENABLE_GPU" =~ ^[Yy]$ ]]; then
    cat << EOF >> compose.yml
      - LIBGL_ALWAYS_SOFTWARE=0
EOF
fi

cat << EOF >> compose.yml
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - /dev:/dev:rw
      - ${HOME}/.ssh:/root/.ssh:ro
      - ${HOME}/.Xauthority:/root/.Xauthority:ro
      - ${HOST_DIR}:${CONTAINER_DIR}:rw
EOF

if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]]; then
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        cat << EOF >> compose.yml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [compute, graphics, utility, display]
EOF
    elif [[ "$GPU_TYPE" == "intel" ]] || [[ "$GPU_TYPE" == "amd" ]]; then
        cat << EOF >> compose.yml
    devices:
      - /dev/dri:/dev/dri
EOF
    fi
fi

cat << EOF >> compose.yml

  carla_sim:
    image: carlasim/carla:0.9.16
    container_name: carla_0_9_16
    restart: unless-stopped
    privileged: true
    network_mode: "host"
    ipc: "host"
    environment:
      - DISPLAY=\${DISPLAY:-:0}
      - QT_X11_NO_MITSHM=1
      - XAUTHORITY=/root/.Xauthority
EOF

if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]] && [[ "$GPU_TYPE" == "nvidia" ]]; then
    cat << EOF >> compose.yml
      - NVIDIA_VISIBLE_DEVICES=all
      - NVIDIA_DRIVER_CAPABILITIES=all
EOF
fi

cat << EOF >> compose.yml
    volumes:
      - /tmp/.X11-unix:/tmp/.X11-unix:rw
      - ${HOME}/.Xauthority:/root/.Xauthority:ro
    command: ["sleep", "infinity"]
EOF

if [[ "$ENABLE_GPU" =~ ^[Yy]$ ]]; then
    if [[ "$GPU_TYPE" == "nvidia" ]]; then
        cat << EOF >> compose.yml
    deploy:
      resources:
        reservations:
          devices:
            - driver: nvidia
              count: all
              capabilities: [compute, graphics, utility, display]
EOF
    elif [[ "$GPU_TYPE" == "intel" ]] || [[ "$GPU_TYPE" == "amd" ]]; then
        cat << EOF >> compose.yml
    devices:
      - /dev/dri:/dev/dri
EOF
    fi
fi

# 6. Add bashrc aliases
echo -e "\n--- Bash Alias Setup ---"
ALIAS_ROS="enter_${ROS2_CONTAINER}"
ALIAS_ROS_CMD="alias $ALIAS_ROS='xhost +local: && docker exec -it ${ROS2_CONTAINER} bash'"

ALIAS_CARLA="run_carla"
ALIAS_CARLA_CMD="alias $ALIAS_CARLA='xhost +local: && docker exec -it carla_0_9_16 ./CarlaUE4.sh --ros2 -nosound'"

ALIAS_CARLA_LOW_QUALITY="run_carla_low_quality"
ALIAS_CARLA_LOW_QUALITY_CMD="alias $ALIAS_CARLA_LOW_QUALITY='xhost +local: && docker exec -it carla_0_9_16 ./CarlaUE4.sh --ros2 -nosound -quality-level=Low'"

ALIAS_CARLA_HEADLESS="run_carla_headless"
ALIAS_CARLA_HEADLESS_CMD="alias $ALIAS_CARLA_HEADLESS='xhost +local: && docker exec -it carla_0_9_16 ./CarlaUE4.sh -RenderOffScreen --ros2 -nosound'"

add_alias_if_missing() {
    local name="$1"
    local cmd="$2"
    if grep -q "alias $name=" ~/.bashrc 2>/dev/null; then
        echo "Alias '$name' already exists in ~/.bashrc."
    else
        echo "$cmd" >> ~/.bashrc
        echo "Added alias '$name' to ~/.bashrc."
    fi
}

add_alias_if_missing "$ALIAS_ROS" "$ALIAS_ROS_CMD"
add_alias_if_missing "$ALIAS_CARLA" "$ALIAS_CARLA_CMD"
add_alias_if_missing "$ALIAS_CARLA_LOW_QUALITY" "$ALIAS_CARLA_LOW_QUALITY_CMD"
add_alias_if_missing "$ALIAS_CARLA_HEADLESS" "$ALIAS_CARLA_HEADLESS_CMD"

# 7. Execution Prompt
echo -e "\n--- Execution ---"
read -p "Do you want to run 'docker compose up -d --build' now? (y/n) [y]: " RUN_COMPOSE
RUN_COMPOSE=${RUN_COMPOSE:-y}

DOCKER_CMD="docker"
if ! docker info >/dev/null 2>&1; then
    if sudo docker info >/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
    else
        echo "Error: Docker daemon is not running or accessible."
        exit 1
    fi
fi

if [[ "$RUN_COMPOSE" =~ ^[Yy]$ ]]; then
    if command -v xhost &> /dev/null; then
        xhost +local: > /dev/null 2>&1
    fi
    echo "Starting containers..."
    $DOCKER_CMD compose up -d --build

    echo -e "\nExtracting PythonAPI from CARLA container to host workspace..."
    if [ ! -d "$HOST_DIR/PythonAPI" ]; then
        $DOCKER_CMD cp carla_0_9_16:./PythonAPI "$HOST_DIR/PythonAPI"
        sudo chown -R $USER:$USER "$HOST_DIR/PythonAPI" 2>/dev/null || true
        echo "PythonAPI successfully copied to $HOST_DIR/PythonAPI"
    else
        echo "Directory $HOST_DIR/PythonAPI already exists. Skipping copy."
    fi

    echo -e "\nSetup successful! Containers are running in the background."
    echo "Useful terminal commands (open a NEW terminal window to use aliases):"
    echo "  - Enter ROS 2 environment : $ALIAS_ROS"
    echo "  - Start CARLA (GUI)      : $ALIAS_CARLA"
    echo "  - Start CARLA (Headless) : $ALIAS_CARLA_HEADLESS"
    echo "  - Run PythonAPI scripts   : Inside $ALIAS_ROS -> cd ${CONTAINER_DIR}/PythonAPI/examples"
else
    echo -e "\nSetup complete. You can start the environment later by running:"
    echo "  xhost +local: && $DOCKER_CMD compose up -d --build"
fi