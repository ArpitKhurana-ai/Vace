#!/bin/bash
set -xe

# 📒 Log setup
rm -rf /app/startup.log
exec > >(tee /app/startup.log) 2>&1

echo "🚀 Starting VACE AI Video Generation Setup..."

# 🕓 Set timezone
ln -fs /usr/share/zoneinfo/Asia/Kolkata /etc/localtime &&     dpkg-reconfigure -f noninteractive tzdata

# 📦 Install system dependencies
apt-get update && apt-get install -y git ffmpeg wget unzip libgl1 python3-pip

# 🔐 Hugging Face login (non-blocking)
echo "🔐 Authenticating Hugging Face..."
huggingface-cli login --token "$HF_TOKEN" || true

# 📁 Setup workspace
cd /workspace || exit 1
mkdir -p /workspace/model /workspace/output
chmod -R 777 /workspace

# 🧠 Clone VACE GitHub repo
if [ ! -d "/workspace/VACE" ]; then
  echo "📥 Cloning VACE repository..."
  git clone https://github.com/ali-vilab/VACE.git /workspace/VACE
else
  echo "📂 VACE repository already present. Skipping clone."
fi

cd /workspace/VACE

# 📦 Install Python dependencies
pip install --upgrade pip
pip install -r requirements.txt || true
pip install huggingface_hub einops omegaconf safetensors av transformers accelerate || true

# 📥 Download model from Hugging Face using snapshot_download
echo "⬇️ Downloading Wan2.1-VACE-14B model..."
python3 - <<EOF
import os
from huggingface_hub import snapshot_download

model_dir = "/workspace/model"
snapshot_download(
    repo_id="Wan-AI/Wan2.1-VACE-14B",
    repo_type="model",
    local_dir=model_dir,
    local_dir_use_symlinks=False,
    token=os.environ.get("HF_TOKEN", None)
)
EOF

# 🧪 Sanity check for model weights
echo "🔍 Verifying model files..."
if [ ! -f "/workspace/model/pytorch_model.bin" ]; then
  echo "❌ Model download failed or file missing: pytorch_model.bin"
  ls -lh /workspace/model
  exit 1
fi
echo "✅ Model files verified."

# 📽️ Run example inference (edit prompt as needed)
echo "🎬 Running test video generation..."
python3 inference.py \
  --pretrained_model_path /workspace/model \
  --prompt "a futuristic city with flying cars at sunset" \
  --output_path /workspace/output \
  --steps 50

# ✅ Install FileBrowser for file access
cd /workspace
wget https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz -O fb.tar.gz
tar --no-same-owner -xvzf fb.tar.gz
chmod +x filebrowser
mv filebrowser /usr/local/bin/filebrowser
mkdir -p /workspace/filebrowser
chmod -R 777 /workspace/filebrowser

filebrowser \
  -r /workspace \
  --address 0.0.0.0 \
  -p 8080 \
  -d /workspace/filebrowser/filebrowser.db \
  > /workspace/filebrowser.log 2>&1 &

# ✅ Show running services
ss -tulpn | grep LISTEN || true

# 📄 Tail logs
echo "📄 Tailing logs..."
tail -f /workspace/filebrowser.log
