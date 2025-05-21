#!/bin/bash
set -xe

# 🔁 Clean logs
rm -rf /app/startup.log
exec > >(tee /app/startup.log) 2>&1

echo "🟡 Starting VACE AI Video Generator Setup..."

# 🕓 Timezone setup
apt-get update && apt-get install -y tzdata
ln -fs /usr/share/zoneinfo/Asia/Kolkata /etc/localtime &&     dpkg-reconfigure -f noninteractive tzdata

# 🔐 Hugging Face login
echo "🔐 Authenticating Hugging Face..."
huggingface-cli login --token "$HF_TOKEN" || true

# 📁 Create persistent model and output directories
export VACE_MODEL_PATH="/workspace/vace_model"
export VACE_OUTPUT_PATH="/workspace/output"
mkdir -p "$VACE_MODEL_PATH" "$VACE_OUTPUT_PATH"
chmod -R 777 "$VACE_MODEL_PATH" "$VACE_OUTPUT_PATH"

cd /workspace || exit 1

# 🧠 Clone VACE repo if missing
if [ ! -d "/workspace/VACE" ]; then
    echo "📥 Cloning VACE GitHub repository..."
    git clone https://github.com/ali-vilab/VACE.git /workspace/VACE
else
    echo "✅ VACE repo already exists, skipping clone."
fi

cd /workspace/VACE

# 📦 Install dependencies
pip install --upgrade pip
pip install -r requirements.txt || true
pip install huggingface_hub einops omegaconf safetensors av transformers accelerate

# ⬇️ Download VACE model using Hugging Face snapshot_download
echo "⬇️ Downloading Wan2.1-VACE-14B model..."
python3 - <<EOF
import os
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="Wan-AI/Wan2.1-VACE-14B",
    repo_type="model",
    local_dir=os.environ['VACE_MODEL_PATH'],
    local_dir_use_symlinks=False,
    token=os.environ.get("HF_TOKEN", None)
)
EOF

chmod -R 777 "$VACE_MODEL_PATH"

# 🔍 Check for model file
echo "🔍 Validating model files..."
if [ ! -f "$VACE_MODEL_PATH/pytorch_model.bin" ]; then
    echo "❌ ERROR: pytorch_model.bin not found in $VACE_MODEL_PATH"
    ls -lh "$VACE_MODEL_PATH"
    exit 1
else
    echo "✅ Found: $VACE_MODEL_PATH/pytorch_model.bin"
fi

# 🎬 Run test inference
echo "🎥 Running example video generation..."
python3 inference.py \
    --pretrained_model_path "$VACE_MODEL_PATH" \
    --prompt "a futuristic city with flying cars at sunset" \
    --output_path "$VACE_OUTPUT_PATH" \
    --steps 50

# ✅ Install and launch FileBrowser
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

# ✅ Show open ports
ss -tulpn | grep LISTEN || true

# 📄 Tail logs
echo "📄 Tailing logs..."
tail -f /workspace/filebrowser.log
