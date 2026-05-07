# ComfyUI Docker Build File v1.0.1 by John Aldred
# https://www.johnaldred.com
# https://github.com/kaouthia

# Use NVIDIA CUDA base image with Python for GPU support
FROM nvidia/cuda:12.6.3-runtime-ubuntu24.04

# Allow passing in your host UID/GID (defaults 1000:1000)
ARG UID=1000
ARG GID=1000

# Install OS deps, Python, and create the non-root user
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      git \
      python3 \
      python3-pip \
      python3-venv \
      libgl1 \
      libglx-mesa0 \
      libglib2.0-0 \
      fonts-dejavu-core \
      fontconfig \
 && ln -s /usr/bin/python3 /usr/bin/python \
 && groupadd --force --gid ${GID} appuser \
 && useradd --uid ${UID} --gid ${GID} --create-home --shell /bin/bash appuser || true \
 && rm -rf /var/lib/apt/lists/*

# Switch to non-root user
USER $UID:$GID

# make ~/.local/bin available on the PATH so scripts like tqdm, torchrun, etc. are found
ENV PATH=/home/appuser/.local/bin:$PATH

# Set the working directory
WORKDIR /app

# Clone the ComfyUI repository (replace URL with the official repo)
RUN git clone https://github.com/comfyanonymous/ComfyUI.git

# Change directory to the ComfyUI folder
WORKDIR /app/ComfyUI

# Install PyTorch with CUDA support, then ComfyUI dependencies
RUN pip install --no-cache-dir --break-system-packages \
      torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu126 \
 && pip install --no-cache-dir --break-system-packages -r requirements.txt

# Copy and enable the startup script (kept at the end of the layer chain so
# entrypoint edits don't invalidate the heavy pytorch install above).
USER root
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
USER $UID:$GID

# Expose the port that ComfyUI will use (change if needed)
EXPOSE 8188

# Run entrypoint first, then start ComfyUI
ENTRYPOINT ["/entrypoint.sh"]
CMD ["python","/app/ComfyUI/main.py","--listen","0.0.0.0"]
