# VUDDY (Vulnerable Code Clone Detection) Docker Image
FROM ubuntu:22.04

# Set non-interactive mode to avoid prompts during installation
ENV DEBIAN_FRONTEND=noninteractive

# Update system packages and install required packages
RUN apt-get update && apt-get install -y \
    # Python 3 and development tools
    python3 \
    python3-pip \
    python3-dev \
    python3-tk \
    # Java Runtime Environment
    openjdk-8-jre \
    # Version Control System
    git \
    # Build essentials and utilities
    build-essential \
    curl \
    wget \
    vim \
    # Required system libraries
    libssl-dev \
    libffi-dev \
    # Clean up apt cache to reduce image size
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /app

# Copy VUDDY source code
RUN git clone https://github.com/seokjeon/vuddy.git

# Change to hmark directory for default operation
WORKDIR /app/vuddy

# Default command - show help message
CMD ["/bin/bash", "-c", "echo 'VUDDY Container Ready' && echo 'Run: python3 hmark.py --help for usage' && /bin/bash"]