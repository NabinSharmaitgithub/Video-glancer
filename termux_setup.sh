#!/data/data/com.termux/files/usr/bin/bash

# Video to Screenshot PDF Converter - Termux Setup Script
# This will install all required dependencies in Termux

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting setup for Video to Screenshot PDF Converter in Termux...${NC}"

# Update packages
echo -e "${YELLOW}Updating packages...${NC}"
pkg update -y && pkg upgrade -y

# Install required system packages
echo -e "${YELLOW}Installing system dependencies...${NC}"
pkg install -y python git ffmpeg libjpeg-turbo

# Install OpenCV dependencies
pkg install -y opencv

# Setup Python environment
echo -e "${YELLOW}Setting up Python environment...${NC}"
python -m pip install --upgrade pip

# Install Python packages
echo -e "${YELLOW}Installing Python packages...${NC}"
pip install -r requirements.txt

# Create project directories
echo -e "${YELLOW}Creating project directories...${NC}"
mkdir -p video_to_pdf/{templates,static,uploads,screenshots}

# Download application files
echo -e "${YELLOW}Downloading application files...${NC}"
cd video_to_pdf

# Download app.py
curl -o app.py https://gist.githubusercontent.com/yourusername/yourapp/raw/main/app.py

# Download index.html
mkdir -p templates
curl -o templates/index.html https://gist.githubusercontent.com/yourusername/yourhtml/raw/main/index.html

# Create run script
echo -e "${YELLOW}Creating run script...${NC}"
cat > run.sh << 'EOL'
#!/data/data/com.termux/files/usr/bin/bash
python app.py
EOL

chmod +x run.sh

# Instructions
echo -e "${GREEN}Setup complete!${NC}"
echo -e "To run the application:"
echo -e "1. Change to project directory: ${YELLOW}cd video_to_pdf${NC}"
echo -e "2. Start the application: ${YELLOW}./run.sh${NC}"
echo -e "3. Open your browser to: ${YELLOW}http://localhost:5000${NC}"

echo -e "\n${YELLOW}Note:${NC}"
echo -e "- You may need to allow Termux to access storage"
echo -e "- For public access, consider using ngrok:"
echo -e "  ${YELLOW}pkg install ngrok && ngrok http 5000${NC}"

exit 0
