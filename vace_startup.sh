#!/bin/bash
set -xe

# 🔁 Clean logs
rm -rf /app/startup.log
exec > >(tee /app/startup.log) 2>&1

echo "🟡 Starting ComfyUI + VACE Setup..."

# 🕓 Timezone Setup
apt-get update && \
    apt-get install -y --no-install-recommends \
    tzdata git ffmpeg wget unzip libgl1 python3-pip htop

ln -fs /usr/share/zoneinfo/Asia/Kolkata /etc/localtime && \
    dpkg-reconfigure -f noninteractive tzdata

# 🔐 Hugging Face Login
echo "🔐 Authenticating Hugging Face..."
huggingface-cli login --token "$HF_TOKEN" || true

# 📁 Prepare folders
export COMFYUI_MODELS_PATH="/workspace/models"
export COMFYUI_WORKFLOWS_PATH="/workspace/ComfyUI/workflows"
export VACE_MODEL_PATH="/workspace/VACE/vace/models/wan"
export VACE_CHECKPOINT_PATH="/workspace/models/checkpoints/Wan2.1-VACE-14B"
mkdir -p "$COMFYUI_MODELS_PATH" "$COMFYUI_WORKFLOWS_PATH" "$VACE_MODEL_PATH" "$VACE_CHECKPOINT_PATH"
chmod -R 777 "$COMFYUI_MODELS_PATH" "$VACE_MODEL_PATH" "$VACE_CHECKPOINT_PATH"

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

# 🧱 Create stub for unit folder (required by some VACE nodes)
mkdir -p /workspace/VACE/vace/models/unit
touch /workspace/VACE/vace/models/unit/README.txt

# 📦 Python requirements
pip install --upgrade pip
pip install huggingface_hub einops omegaconf safetensors av transformers accelerate torchsde aiohttp
pip install -r /workspace/VACE/requirements.txt || true

# ⬇️ Download VACE model to wan/
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

# 🧾 List downloaded model files
echo "📁 Contents of wan/ directory:"
ls -lh "$VACE_MODEL_PATH"

# 🧩 Copy model to ComfyUI checkpoints if present
echo "🔗 Copying model to ComfyUI checkpoint path..."
cp "$VACE_MODEL_PATH"/*.safetensors "$VACE_CHECKPOINT_PATH" || true
cp "$VACE_MODEL_PATH"/*.bin "$VACE_CHECKPOINT_PATH" || true

# ✅ Sanity check for ComfyUI-compatible model
echo "🔍 Validating copied model presence..."
if [ -z "$(ls -A $VACE_CHECKPOINT_PATH)" ]; then
    echo "❌ ERROR: No model found in $VACE_CHECKPOINT_PATH!"
    exit 1
else
    echo "✅ Model successfully copied to ComfyUI checkpoints."
fi

# ⬇️ Download required wan_2.1_vae.safetensors file for the workflow
echo "⬇️ Downloading VAE file for Wan2.1..."
mkdir -p /workspace/models/vae
wget -O /workspace/models/vae/wan_2.1_vae.safetensors \
https://huggingface.co/Wan-AI/Wan2.1-VACE-14B/resolve/main/wan_2.1_vae.safetensors
chmod 777 /workspace/models/vae/wan_2.1_vae.safetensors

# 🔁 Install custom nodes
echo "📦 Installing custom nodes..."
mkdir -p /workspace/ComfyUI/custom_nodes
cd /workspace/ComfyUI/custom_nodes
git clone https://github.com/ltdrdata/ComfyUI-Manager.git || true
git clone https://github.com/ltdrdata/ComfyUI-Impact-Pack.git || true
touch ComfyUI-Impact-Pack/__init__.py

# ⏳ Let filesystem settle
echo "⏳ Sleeping 5s before workflow fetch..."
sleep 5

# ⬇️ Download workflow from QuantStack
echo "⬇️ Fetching QuantStack example workflow file..."
wget -O "$COMFYUI_WORKFLOWS_PATH/vace_v2v_example_workflow.json" \
https://huggingface.co/QuantStack/Wan2.1-VACE-14B-GGUF/resolve/main/vace_v2v_example_workflow.json

# ⏳ Final delay before launching servers
echo "⏳ Sleeping 5s before launching ComfyUI and FileBrowser..."
sleep 5

# ✅ Launch ComfyUI
cd /workspace/ComfyUI
echo "🚀 Launching ComfyUI..."
python3 main.py --listen 0.0.0.0 --port 8188 > /workspace/comfyui.log 2>&1 &
sleep 5

# ✅ Install and Launch FileBrowser
cd /workspace
echo "📁 Launching FileBrowser..."
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
sleep 5

# ✅ Show open ports
echo "🌐 Open ports:"
ss -tulpn | grep LISTEN || true

# 📄 Tail logs
echo "📄 Tailing logs..."
tail -n 200 -f /workspace/comfyui.log /workspace/filebrowser.log
