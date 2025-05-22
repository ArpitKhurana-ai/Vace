#!/bin/bash
set -xe

# 🔁 Clean logs
rm -rf /app/startup.log
exec > >(tee /app/startup.log) 2>&1

echo "🟡 Starting ComfyUI + VACE Setup..."

# 🕓 Timezone Setup
apt-get update && apt-get install -y tzdata git ffmpeg wget unzip libgl1 python3-pip
ln -fs /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 🔐 Hugging Face Login
echo "🔐 Authenticating Hugging Face..."
huggingface-cli login --token \"$HF_TOKEN\" || true

# 📁 Prepare folders
export COMFYUI_MODELS_PATH="/workspace/models"
export COMFYUI_WORKFLOWS_PATH="/workspace/ComfyUI/workflows"
mkdir -p "$COMFYUI_MODELS_PATH" "$COMFYUI_WORKFLOWS_PATH"
chmod -R 777 "$COMFYUI_MODELS_PATH"

cd /workspace || exit 1

# 📥 Clone ComfyUI if needed
if [ ! -f "ComfyUI/main.py" ]; then
    echo "📦 Cloning ComfyUI..."
    rm -rf ComfyUI
    git clone https://github.com/comfyanonymous/ComfyUI.git
fi

# 🔁 Link models folder
rm -rf /workspace/ComfyUI/models
ln -s "$COMFYUI_MODELS_PATH" /workspace/ComfyUI/models

# 🧠 Clone VACE repo
if [ ! -d "/workspace/VACE" ]; then
    echo "📥 Cloning VACE repository..."
    git clone https://github.com/ali-vilab/VACE.git /workspace/VACE
fi

# 📦 Python requirements
pip install --upgrade pip
pip install -r /workspace/VACE/requirements.txt || true
pip install huggingface_hub einops omegaconf safetensors av transformers accelerate

# ⬇️ Download VACE model
# ✅ Set model path
export VACE_MODEL_PATH="/workspace/models/checkpoints/Wan2.1-VACE-14B"
mkdir -p "$VACE_MODEL_PATH"
chmod -R 777 "$VACE_MODEL_PATH"

# ✅ Then use it in the Python block
python3 - <<EOF
import os
from huggingface_hub import snapshot_download

snapshot_download(
    repo_id="Wan-AI/Wan2.1-VACE-14B",
    repo_type="model",
    local_dir=os.environ["VACE_MODEL_PATH"],
    local_dir_use_symlinks=False,
    token=os.environ.get("HF_TOKEN", None)
)
EOF

# 🔁 Clone custom node pack if needed (can extend here)
echo "📦 Installing custom nodes..."
mkdir -p /workspace/ComfyUI/custom_nodes
cd /workspace/ComfyUI/custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager.git || true
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git || true
touch ComfyUI-Impact-Pack/__init__.py

# ⬇️ Download example workflow JSON from QuantStack
echo "⬇️ Fetching example workflow file..."
wget -O "$COMFYUI_WORKFLOWS_PATH/vace_v2v_example_workflow.json" \\
    https://huggingface.co/QuantStack/Wan2.1-VACE-14B-GGUF/resolve/main/vace_v2v_example_workflow.json

# ✅ Sanity check: model file
echo "🔍 Validating model presence..."
if [ ! -f "/workspace/models/checkpoints/Wan2.1-VACE-14B/pytorch_model.bin" ]; then
    echo "❌ ERROR: Model not found!"
    exit 1
else
    echo "✅ VACE model ready."
fi

# ✅ Launch ComfyUI
cd /workspace/ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &

# ✅ Install FileBrowser
cd /workspace
wget https://github.com/filebrowser/filebrowser/releases/latest/download/linux-amd64-filebrowser.tar.gz -O fb.tar.gz
tar --no-same-owner -xvzf fb.tar.gz
chmod +x filebrowser
mv filebrowser /usr/local/bin/filebrowser
mkdir -p /workspace/filebrowser
chmod -R 777 /workspace/filebrowser

filebrowser \\
  -r /workspace \\
  --address 0.0.0.0 \\
  -p 8080 \\
  -d /workspace/filebrowser/filebrowser.db \\
  > /workspace/filebrowser.log 2>&1 &

# ✅ Show open ports
ss -tulpn | grep LISTEN || true

# 📄 Tail logs
echo "📄 Tailing logs..."
tail -f /workspace/comfyui.log /workspace/filebrowser.log
