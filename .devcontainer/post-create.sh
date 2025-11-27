#!/bin/bash
set -e

echo "🚀 Setting up MLOps Workshop environment..."

# Install kind (Kubernetes in Docker)
echo "📦 Installing kind..."
curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.30.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/
echo "✅ kind installed"

# Install workshop dependencies for all modules
# echo "📦 Installing Python dependencies..."
# if [ -f requirements.txt ]; then
#     pip install --upgrade pip
#     pip install -r requirements.txt
#     echo "✅ Python dependencies installed"
# else
#     echo "⚠️  No requirements.txt found in root, skipping..."
# fi

# # Install module-specific dependencies
# for module_dir in modules/module-*; do
#     if [ -f "$module_dir/requirements.txt" ]; then
#         echo "📦 Installing dependencies for $module_dir..."
#         pip install -r "$module_dir/requirements.txt"
#     fi
# done

echo ""
echo "✅ MLOps Workshop environment ready!"
echo ""
echo "Next steps:"
echo "  1. Start with Module 0 (Environment Setup)"
echo "  2. Follow the workshop modules in order"
echo "  3. All tools are pre-installed: Python, Go, Docker, kubectl, kind"
echo ""
echo "Happy learning! 🎉"
