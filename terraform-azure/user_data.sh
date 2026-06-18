#!/bin/bash
exec > >(tee /var/log/user-data.log) 2>&1

echo "Starting user_data setup for AI Inference Endpoint on Azure"

# Install Docker
apt-get update -y
apt-get install -y docker.io
systemctl enable docker
systemctl start docker

# Install NVIDIA drivers and container toolkit
apt-get install -y linux-headers-$(uname -r)
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
  | gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/$distribution/libnvidia-container.list \
  | sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' \
  | tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
apt-get update -y
apt-get install -y nvidia-container-toolkit
nvidia-ctk runtime configure --runtime=docker
systemctl restart docker

# Pull the vLLM image
docker pull vllm/vllm-openai:latest

export HF_TOKEN="${hf_token}"
MODEL="${model_id}"

# Run vLLM with OpenAI compatible server
docker run -d --name vllm \
  --gpus all \
  --restart unless-stopped \
  -e HF_TOKEN=$HF_TOKEN \
  -v /opt/huggingface:/root/.cache/huggingface \
  -p 8000:8000 \
  --ipc=host \
  vllm/vllm-openai:latest \
  --model $MODEL \
  --max-model-len 2048 \
  --gpu-memory-utilization 0.90 \
  --host 0.0.0.0

echo "vLLM container started with model $MODEL"
